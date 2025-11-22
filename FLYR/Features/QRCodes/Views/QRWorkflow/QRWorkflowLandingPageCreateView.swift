import SwiftUI
import PhotosUI
import Combine

/// View for creating a new landing page (QR Workflow)
struct QRWorkflowLandingPageCreateView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (UUID) -> Void
    
    @StateObject private var viewModel = QRWorkflowLandingPageCreateViewModel()
    @State private var selectedCampaignId: UUID?
    @State private var title: String = ""
    @State private var slug: String = ""
    @State private var headline: String = ""
    @State private var subheadline: String = ""
    @State private var ctaType: String = "book"
    @State private var ctaUrl: String = ""
    @State private var selectedImage: PhotosPickerItem?
    @State private var heroImage: UIImage?
    @State private var showDuplicateError = false
    
    private let ctaTypes = ["book", "learn_more", "call", "contact", "custom"]
    
    var body: some View {
        Form {
            Section("Campaign") {
                if viewModel.isLoadingCampaigns {
                    ProgressView()
                } else {
                    Picker("Campaign", selection: $selectedCampaignId) {
                        Text("Select Campaign").tag(UUID?.none)
                        ForEach(viewModel.campaigns) { campaign in
                            Text(campaign.name).tag(UUID?.some(campaign.id))
                        }
                    }
                }
            }
            
            Section("Landing Page Details") {
                TextField("Title", text: $title)
                    .textInputAutocapitalization(.words)
                
                HStack {
                    TextField("Slug", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    Button("Generate") {
                        slug = CampaignLandingPage.generateSlug(from: title.isEmpty ? "landing-page" : title)
                    }
                    .font(.caption)
                }
                
                TextField("Headline", text: $headline)
                    .textInputAutocapitalization(.sentences)
                
                TextField("Subheadline", text: $subheadline)
                    .textInputAutocapitalization(.sentences)
            }
            
            Section("Call to Action") {
                Picker("CTA Type", selection: $ctaType) {
                    ForEach(ctaTypes, id: \.self) { type in
                        Text(type.replacingOccurrences(of: "_", with: " ").capitalized).tag(type)
                    }
                }
                
                TextField("CTA URL", text: $ctaUrl)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            
            Section("Hero Image") {
                if let heroImage = heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                    
                    Button("Remove Image") {
                        self.heroImage = nil
                        selectedImage = nil
                    }
                    .foregroundColor(.red)
                } else {
                    PhotosPicker(selection: $selectedImage, matching: .images) {
                        HStack {
                            Image(systemName: "photo")
                            Text("Select Image")
                        }
                    }
                }
            }
        }
        .navigationTitle("Create Landing Page")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await saveLandingPage()
                    }
                }
                .disabled(!canSave)
            }
        }
        .alert("Landing Page Exists", isPresented: $showDuplicateError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This campaign already has a landing page. Please edit the existing landing page instead.")
        }
        .task {
            await viewModel.loadCampaigns()
        }
        .onChange(of: selectedImage) { _, newItem in
            Task {
                if let newItem = newItem {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            heroImage = image
                        }
                    }
                }
            }
        }
    }
    
    private var canSave: Bool {
        selectedCampaignId != nil && !slug.isEmpty
    }
    
    private func saveLandingPage() async {
        guard let campaignId = selectedCampaignId else { return }
        
        viewModel.isSaving = true
        defer { viewModel.isSaving = false }
        
        do {
            // Upload hero image if present
            var heroUrl: String? = nil
            if let heroImage = heroImage {
                heroUrl = try await SupabaseLandingPageService.shared.uploadHeroImage(heroImage, campaignId: campaignId)
            }
            
            // Create landing page
            let landingPage = try await SupabaseLandingPageService.shared.createLandingPage(
                campaignId: campaignId,
                slug: slug.isEmpty ? CampaignLandingPage.generateSlug(from: title.isEmpty ? "landing-page" : title) : slug,
                title: title.isEmpty ? nil : title,
                headline: headline.isEmpty ? nil : headline,
                subheadline: subheadline.isEmpty ? nil : subheadline,
                heroType: .image,
                heroUrl: heroUrl,
                ctaType: ctaType,
                ctaUrl: ctaUrl.isEmpty ? nil : ctaUrl
            )
            
            await MainActor.run {
                onSave(landingPage.id)
                dismiss()
            }
        } catch let err {
            // Check for unique constraint violation
            let nsError = err as NSError
            if nsError.domain.contains("Postgrest") || nsError.localizedDescription.contains("unique") {
                await MainActor.run {
                    showDuplicateError = true
                }
            } else {
                await MainActor.run {
                    viewModel.error = "Failed to create landing page: \(err.localizedDescription)"
                }
            }
        }
    }
}

@MainActor
class QRWorkflowLandingPageCreateViewModel: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var isLoadingCampaigns = false
    @Published var isSaving = false
    @Published var error: String?
    
    private let campaignsAPI = CampaignsAPI.shared
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        defer { isLoadingCampaigns = false }
        
        do {
            let dbRows = try await campaignsAPI.fetchCampaignsMetadata()
            campaigns = dbRows.map { CampaignListItem(from: $0) }
        } catch {
            self.error = "Failed to load campaigns: \(error.localizedDescription)"
        }
    }
}

