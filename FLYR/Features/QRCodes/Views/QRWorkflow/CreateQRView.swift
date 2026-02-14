import SwiftUI
import Combine

/// View for creating QR codes with URL (direct link) destination
struct CreateQRView: View {
    let selectedCampaignId: UUID?
    
    @StateObject private var viewModel = CreateQRViewModel()
    @State private var showPrintView = false
    @State private var generatedQRCodeId: UUID?
    
    init(selectedLandingPageId: UUID? = nil, selectedCampaignId: UUID? = nil) {
        self.selectedCampaignId = selectedCampaignId
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Destination Type Section (URL only)
                destinationTypeSection
                
                // URL Field
                destinationFieldsSection
                
                // Campaign Section (Optional)
                campaignSection
                
                // Farm Section (Optional)
                farmSection
                
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
                        .font(.flyrFootnote)
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
            }
            viewModel.updateCampaignName()
            viewModel.updateFarmName()
        }
        .onChange(of: viewModel.destinationType) { _, _ in
            viewModel.destinationValue = ""
        }
        .sheet(isPresented: $viewModel.showCampaignPicker) {
            CampaignPickerSheet(
                campaigns: viewModel.campaigns,
                selectedCampaignId: $viewModel.selectedCampaignId
            ) { _ in
                viewModel.updateCampaignName()
            }
        }
        .sheet(isPresented: $viewModel.showFarmPicker) {
            FarmPickerSheet(
                farms: viewModel.farms,
                selectedFarmId: $viewModel.selectedFarmId
            ) { _ in
                viewModel.updateFarmName()
            }
        }
    }
    
    private var destinationTypeSection: some View {
        FormSection("QR Destination") {
            FormRowMenuPicker("Destination Type",
                             options: QRDestinationType.allCases,
                             selection: $viewModel.destinationType)
        }
        .formContainerPadding()
    }
    
    private var destinationFieldsSection: some View {
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
    
    private var canGenerate: Bool {
        guard !viewModel.isGenerating else { return false }
        return !viewModel.destinationValue.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private func generateQRCode() async {
        viewModel.isGenerating = true
        defer { viewModel.isGenerating = false }
        
        do {
            let qrUrl = viewModel.destinationType.buildURL(
                value: viewModel.destinationValue.isEmpty ? nil : viewModel.destinationValue,
                campaignId: viewModel.selectedCampaignId,
                landingPageId: nil
            )
            
            guard let base64Image = QRCodeGenerator.generateBase64(from: qrUrl) else {
                await MainActor.run {
                    viewModel.error = "Failed to generate QR code image"
                }
                return
            }
            
            var metadataDict: [String: AnyCodable] = [:]
            metadataDict["destination_type"] = AnyCodable(viewModel.destinationType.rawValue)
            
            let qrCode = try await QRRepository.shared.createQRCodeWithSlug(
                campaignId: viewModel.selectedCampaignId,
                farmId: viewModel.selectedFarmId,
                landingPageId: nil,
                slug: nil,
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
    @Published var farms: [FarmListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var selectedFarmId: UUID?
    @Published var qrStyle: QRStyle = .light
    @Published var includeLogo: Bool = false
    
    @Published var destinationType: QRDestinationType = .directLink
    @Published var destinationValue: String = ""
    
    @Published var showCampaignPicker = false
    @Published var showFarmPicker = false
    
    @Published var selectedCampaignName: String?
    @Published var selectedFarmName: String?
    
    @Published var isLoadingCampaigns = false
    @Published var isLoadingFarms = false
    @Published var isGenerating = false
    @Published var error: String?
    
    private let campaignsAPI = CampaignsAPI.shared
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
