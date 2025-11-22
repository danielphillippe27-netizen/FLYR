import SwiftUI
import Combine

/// View for creating QR codes with campaign and landing page selection
struct CreateQRView: View {
    let selectedLandingPageId: UUID?
    let selectedCampaignId: UUID?
    
    @StateObject private var viewModel = CreateQRViewModel()
    @State private var showPrintView = false
    @State private var generatedQRCodeId: UUID?
    
    init(selectedLandingPageId: UUID? = nil, selectedCampaignId: UUID? = nil) {
        self.selectedLandingPageId = selectedLandingPageId
        self.selectedCampaignId = selectedCampaignId
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Destination Type Section
                destinationTypeSection
                
                // Conditional Destination Fields
                destinationFieldsSection
                
                // Landing Page Section (for landingPage destination type)
                if viewModel.destinationType == .landingPage {
                    landingPageSection
                }
                
                // Campaign Section (Optional)
                campaignSection
                
                // Farm Section (Optional)
                farmSection
                
                // Spacer to reveal CTA above tab bar
                Rectangle()
                    .fill(.clear)
                    .frame(height: 8)
            }
        }
        .navigationTitle("New QR Code")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let err = viewModel.error {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                PrimaryButton(title: "Generate QR Code", enabled: canGenerate) {
                    Task { await generateQRCode() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            .background(.ultraThinMaterial)
        }
        .navigationDestination(isPresented: $showPrintView) {
            if let qrCodeId = generatedQRCodeId {
                PrintQRView(qrCodeId: qrCodeId)
            }
        }
        .task {
            await viewModel.loadCampaigns()
            await viewModel.loadFarms()
            if let selectedCampaignId = selectedCampaignId {
                viewModel.selectedCampaignId = selectedCampaignId
                await viewModel.loadLandingPages(for: selectedCampaignId)
            }
            if let selectedLandingPageId = selectedLandingPageId {
                viewModel.selectedLandingPageId = selectedLandingPageId
            }
            // Update names for any pre-selected values
            viewModel.updateLandingPageName()
            viewModel.updateCampaignName()
            viewModel.updateFarmName()
        }
        .onChange(of: viewModel.destinationType) { _, _ in
            // Reset destination value when type changes
            viewModel.destinationValue = ""
        }
        .sheet(isPresented: $viewModel.showLandingPagePicker) {
            LandingPagePickerSheet(
                selectedLandingPageId: $viewModel.selectedLandingPageId
            ) { landingPageId, name in
                viewModel.selectedLandingPageName = name
            }
        }
        .sheet(isPresented: $viewModel.showCampaignPicker) {
            CampaignPickerSheet(
                campaigns: viewModel.campaigns,
                selectedCampaignId: $viewModel.selectedCampaignId
            ) { campaignId in
                viewModel.updateCampaignName()
                if let campaignId = campaignId {
                    Task {
                        await viewModel.loadLandingPages(for: campaignId)
                    }
                } else {
                    viewModel.landingPages = []
                    viewModel.selectedLandingPageId = nil
                }
            }
        }
        .sheet(isPresented: $viewModel.showFarmPicker) {
            FarmPickerSheet(
                farms: viewModel.farms,
                selectedFarmId: $viewModel.selectedFarmId
            ) { farmId in
                viewModel.updateFarmName()
            }
        }
    }
    
    // MARK: - Destination Type Section
    
    private var destinationTypeSection: some View {
        FormSection("QR Destination") {
            FormRowMenuPicker("Destination Type",
                             options: QRDestinationType.allCases,
                             selection: $viewModel.destinationType)
        }
        .formContainerPadding()
    }
    
    // MARK: - Destination Fields Section
    
    private var destinationFieldsSection: some View {
        Group {
            switch viewModel.destinationType {
            case .landingPage:
                EmptyView()
                
            case .directLink:
                FormSection("URL") {
                    HStack {
                        TextField(viewModel.destinationType.valuePlaceholder, text: $viewModel.destinationValue)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 16))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .formContainerPadding()
            }
        }
    }
    
    // MARK: - Landing Page Section
    
    private var landingPageSection: some View {
        FormSection("Landing Page") {
            FormRowButton(
                title: "Landing Page",
                value: viewModel.selectedLandingPageName,
                placeholder: "Select Landing Page"
            ) {
                viewModel.showLandingPagePicker = true
            }
        }
        .formContainerPadding()
    }
    
    // MARK: - Campaign Section (Optional)
    
    private var campaignSection: some View {
        FormSection("Campaign (Optional)") {
            if viewModel.isLoadingCampaigns {
                ProgressView()
                    .padding(12)
            } else {
                FormRowButton(
                    title: "Campaign",
                    value: viewModel.selectedCampaignName,
                    placeholder: "None"
                ) {
                    viewModel.showCampaignPicker = true
                }
            }
        }
        .formContainerPadding()
    }
    
    // MARK: - Farm Section (Optional)
    
    private var farmSection: some View {
        FormSection("Farm (Optional)") {
            if viewModel.isLoadingFarms {
                ProgressView()
                    .padding(12)
            } else {
                FormRowButton(
                    title: "Farm",
                    value: viewModel.selectedFarmName,
                    placeholder: "None"
                ) {
                    viewModel.showFarmPicker = true
                }
            }
        }
        .formContainerPadding()
    }
    
    // MARK: - Validation
    
    private var canGenerate: Bool {
        guard !viewModel.isGenerating else { return false }
        
        switch viewModel.destinationType {
        case .landingPage:
            return viewModel.selectedLandingPageId != nil
        case .directLink:
            return !viewModel.destinationValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    
    private func generateQRCode() async {
        viewModel.isGenerating = true
        defer { viewModel.isGenerating = false }
        
        do {
            // Generate slug (only for campaign/landingPage types that use redirect)
            var slug: String? = nil
            var qrUrl: String
            
            switch viewModel.destinationType {
            case .landingPage:
                // For landing page, use slug-based redirect
                slug = QRSlugGenerator.generateLowercase(length: 8)
                qrUrl = viewModel.destinationType.buildURL(
                    value: slug,
                    campaignId: viewModel.selectedCampaignId,
                    landingPageId: viewModel.selectedLandingPageId
                )
                
            case .directLink:
                // For URL, build URL directly from destination value
                qrUrl = viewModel.destinationType.buildURL(
                    value: viewModel.destinationValue.isEmpty ? nil : viewModel.destinationValue,
                    campaignId: viewModel.selectedCampaignId,
                    landingPageId: viewModel.selectedLandingPageId
                )
            }
            
            // Generate QR code image
            guard let base64Image = QRCodeGenerator.generateBase64(from: qrUrl) else {
                await MainActor.run {
                    viewModel.error = "Failed to generate QR code image"
                }
                return
            }
            
            // Prepare metadata
            var metadataDict: [String: AnyCodable] = [:]
            metadataDict["destination_type"] = AnyCodable(viewModel.destinationType.rawValue)
            
            // Create QR code in database
            let qrCode = try await SupabaseQRService.shared.createQRCodeWithSlug(
                campaignId: viewModel.selectedCampaignId,
                farmId: viewModel.selectedFarmId,
                landingPageId: viewModel.destinationType == .landingPage ? viewModel.selectedLandingPageId : nil,
                slug: slug,
                qrUrl: qrUrl,
                qrImage: base64Image,
                variant: nil,
                metadata: metadataDict.isEmpty ? nil : metadataDict
            )
            
            await MainActor.run {
                generatedQRCodeId = qrCode.id
                showPrintView = true
            }
        } catch {
            await MainActor.run {
                viewModel.error = "Failed to create QR code: \(error.localizedDescription)"
            }
        }
    }
}

enum QRStyle: String, CaseIterable {
    case light
    case dark
    case appleShadow
}

@MainActor
class CreateQRViewModel: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var landingPages: [CampaignLandingPage] = []
    @Published var farms: [FarmListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var selectedLandingPageId: UUID?
    @Published var selectedFarmId: UUID?
    @Published var qrStyle: QRStyle = .light
    @Published var includeLogo: Bool = false
    
    // Destination Type
    @Published var destinationType: QRDestinationType = .landingPage
    @Published var destinationValue: String = ""
    
    // Picker state
    @Published var showLandingPagePicker = false
    @Published var showCampaignPicker = false
    @Published var showFarmPicker = false
    
    // Display names
    @Published var selectedLandingPageName: String?
    @Published var selectedCampaignName: String?
    @Published var selectedFarmName: String?
    
    @Published var isLoadingCampaigns = false
    @Published var isLoadingLandingPages = false
    @Published var isLoadingFarms = false
    @Published var isGenerating = false
    @Published var error: String?
    
    private let campaignsAPI = CampaignsAPI.shared
    private let landingPageService = SupabaseLandingPageService.shared
    private let qrRepository = QRRepository.shared
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        defer { isLoadingCampaigns = false }
        
        do {
            let dbRows = try await campaignsAPI.fetchCampaignsMetadata()
            campaigns = dbRows.map { CampaignListItem(id: $0.id, name: $0.title, addressCount: nil) }
        } catch {
            self.error = "Failed to load campaigns: \(error.localizedDescription)"
        }
    }
    
    func loadLandingPages(for campaignId: UUID) async {
        isLoadingLandingPages = true
        defer { isLoadingLandingPages = false }
        
        do {
            if let landingPage = try await landingPageService.fetchLandingPage(campaignId: campaignId) {
                landingPages = [landingPage]
            } else {
                landingPages = []
            }
        } catch {
            self.error = "Failed to load landing pages: \(error.localizedDescription)"
            landingPages = []
        }
    }
    
    func loadFarms() async {
        isLoadingFarms = true
        defer { isLoadingFarms = false }
        
        do {
            let farmRows = try await qrRepository.fetchFarms()
            farms = farmRows.map { $0.toFarmListItem() }
            updateFarmName()
        } catch {
            self.error = "Failed to load farms: \(error.localizedDescription)"
        }
    }
    
    func updateLandingPageName() {
        if let landingPageId = selectedLandingPageId {
            // Try to find in loaded landing pages first
            if let landingPage = landingPages.first(where: { $0.id == landingPageId }) {
                selectedLandingPageName = landingPage.headline ?? landingPage.slug
            }
            // If not found, the picker sheet will set the name directly
        } else {
            selectedLandingPageName = nil
        }
    }
    
    func updateCampaignName() {
        if let campaignId = selectedCampaignId,
           let campaign = campaigns.first(where: { $0.id == campaignId }) {
            selectedCampaignName = campaign.name
        } else {
            selectedCampaignName = nil
        }
    }
    
    func updateFarmName() {
        if let farmId = selectedFarmId,
           let farm = farms.first(where: { $0.id == farmId }) {
            selectedFarmName = farm.name
        } else {
            selectedFarmName = nil
        }
    }
}

