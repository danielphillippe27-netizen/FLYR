import SwiftUI
import Supabase
import Combine

/// Full-screen batch creation view with configuration options
struct CreateBatchView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreateBatchViewModel()
    
    let campaignId: UUID
    let onBatchCreated: (Batch) -> Void
    
    @State private var name: String = ""
    @State private var qrType: QRType = .landingPage
    @State private var landingPageId: UUID? = nil
    @State private var customURL: String = ""
    @State private var exportFormat: ExportFormat = .pdf
    
    @FocusState private var isNameFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.bg
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Batch Name
                        nameSection
                        
                        // QR Type Selection
                        QRTypeSelector(selectedType: $qrType) { newType in
                            // Reset dependent fields when type changes
                            if newType != .landingPage {
                                landingPageId = nil
                            }
                            if newType != .customURL {
                                customURL = ""
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Conditional Fields
                        conditionalFieldsSection
                        
                        // Export Format
                        ExportFormatPicker(selectedFormat: $exportFormat) { _ in }
                            .padding(.horizontal, 16)
                        
                        // Spacer for bottom button
                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.top, 8)
                }
                
                // Sticky Bottom Button
                VStack {
                    Spacer()
                    createButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.bg.opacity(0),
                                    Color.bg.opacity(0.95),
                                    Color.bg
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .navigationTitle("Create Batch")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadLandingPages()
                await viewModel.loadUserDefaultWebsite()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Configure your QR batch before generating.")
                .font(.system(size: 17))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - Name Section
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Name")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            TextField("Enter batch name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 17))
                .focused($isNameFieldFocused)
                .submitLabel(.done)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Conditional Fields Section
    
    @ViewBuilder
    private var conditionalFieldsSection: some View {
        if qrType == .landingPage {
            LandingPagePicker(
                pages: viewModel.landingPages,
                selectedId: $landingPageId
            ) { selectedId in
                landingPageId = selectedId
            }
            .padding(.horizontal, 16)
        } else if qrType == .customURL {
            CustomUrlInput(url: $customURL)
                .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Create Button
    
    private var createButton: some View {
        Button(action: {
            Task {
                await createBatch()
            }
        }) {
            HStack {
                if viewModel.isCreating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Create")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFormValid ? Color(hex: "#FF584A") : Color(.systemGray4))
            )
        }
        .disabled(!isFormValid || viewModel.isCreating)
    }
    
    // MARK: - Validation
    
    private var isFormValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        
        switch qrType {
        case .landingPage:
            return landingPageId != nil
        case .customURL:
            return !customURL.trimmingCharacters(in: .whitespaces).isEmpty &&
                   URL(string: customURL) != nil
        case .directLink, .map:
            return true
        }
    }
    
    // MARK: - Actions
    
    private func createBatch() async {
        // Get current user ID
        guard let userId = try? await SupabaseManager.shared.client.auth.session.user.id else {
            viewModel.errorMessage = "Please sign in to create a batch"
            return
        }
        
        // Create batch model
        let batch = Batch(
            userId: userId,
            name: name.trimmingCharacters(in: .whitespaces),
            qrType: qrType,
            landingPageId: qrType == .landingPage ? landingPageId : nil,
            customURL: qrType == .customURL ? customURL.trimmingCharacters(in: .whitespaces) : nil,
            exportFormat: exportFormat
        )
        
        viewModel.isCreating = true
        viewModel.errorMessage = nil
        
        do {
            // Create batch in database
            let createdBatch = try await BatchRepository.shared.createBatch(batch)
            
            // Generate QR codes for all addresses
            let qrCodes = try await BatchQRGenerator.generateBatchQRCodes(
                createdBatch,
                campaignId: campaignId,
                userDefaultWebsite: viewModel.userDefaultWebsite
            )
            
            print("✅ [Create Batch] Created batch with \(qrCodes.count) QR codes")
            
            // Trigger export if needed (will be handled by view model)
            onBatchCreated(createdBatch)
            dismiss()
        } catch {
            viewModel.errorMessage = "Failed to create batch: \(error.localizedDescription)"
            print("❌ [Create Batch] Error: \(error)")
        }
        
        viewModel.isCreating = false
    }
}

// MARK: - View Model

@MainActor
class CreateBatchViewModel: ObservableObject {
    @Published var landingPages: [LandingPage] = []
    @Published var userDefaultWebsite: String?
    @Published var isCreating = false
    @Published var errorMessage: String?
    
    func loadLandingPages() async {
        do {
            landingPages = try await LandingPagesAPI.shared.fetchLandingPages()
        } catch {
            print("⚠️ [Create Batch] Failed to load landing pages: \(error)")
        }
    }
    
    func loadUserDefaultWebsite() async {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let userId = session.user.id
            
            let response: PostgrestResponse<[UserSettings]> = try await SupabaseManager.shared.client
                .from("user_settings")
                .select("default_website")
                .eq("user_id", value: userId.uuidString)
                .limit(1)
                .execute()
            
            userDefaultWebsite = response.value.first?.default_website
        } catch {
            print("⚠️ [Create Batch] Failed to load default website: \(error)")
            userDefaultWebsite = nil
        }
    }
}

