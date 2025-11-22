import SwiftUI
import Combine
import Supabase

struct LandingPagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLandingPageId: UUID?
    let onSelect: (UUID?, String?) -> Void
    
    @StateObject private var viewModel = LandingPagePickerSheetViewModel()
    
    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.allLandingPages.isEmpty {
                    VStack(spacing: 16) {
                        Text("No landing pages found")
                            .foregroundColor(.secondary)
                        NavigationLink {
                            QRWorkflowLandingPageCreateWrapper(onSave: { landingPageId in
                                Task {
                                    await viewModel.loadLandingPages()
                                    selectedLandingPageId = landingPageId
                                    if let landingPage = viewModel.allLandingPages.first(where: { $0.id == landingPageId }) {
                                        let name = landingPage.headline ?? landingPage.slug
                                        onSelect(landingPageId, name)
                                    } else {
                                        onSelect(landingPageId, nil)
                                    }
                                    dismiss()
                                }
                            })
                        } label: {
                            Text("Create New Landing Page")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Button {
                        selectedLandingPageId = nil
                        onSelect(nil, nil)
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedLandingPageId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    ForEach(viewModel.allLandingPages) { landingPage in
                        Button {
                            selectedLandingPageId = landingPage.id
                            let name = landingPage.headline ?? landingPage.slug
                            onSelect(landingPage.id, name)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(landingPage.headline ?? landingPage.slug)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.primary)
                                    if let campaignName = viewModel.campaignNames[landingPage.campaignId] {
                                        Text(campaignName)
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedLandingPageId == landingPage.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    
                    Section {
                        NavigationLink {
                            QRWorkflowLandingPageCreateWrapper(onSave: { landingPageId in
                                Task {
                                    await viewModel.loadLandingPages()
                                    selectedLandingPageId = landingPageId
                                    if let landingPage = viewModel.allLandingPages.first(where: { $0.id == landingPageId }) {
                                        let name = landingPage.headline ?? landingPage.slug
                                        onSelect(landingPageId, name)
                                    } else {
                                        onSelect(landingPageId, nil)
                                    }
                                    dismiss()
                                }
                            })
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text("Create New Landing Page")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Landing Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadLandingPages()
            }
        }
    }
}

@MainActor
class LandingPagePickerSheetViewModel: ObservableObject {
    @Published var allLandingPages: [CampaignLandingPage] = []
    @Published var campaignNames: [UUID: String] = [:]
    @Published var isLoading = false
    
    private let campaignsAPI = CampaignsAPI.shared
    
    func loadLandingPages() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response: [CampaignLandingPage] = try await SupabaseManager.shared.client
                .from("campaign_landing_pages")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            
            allLandingPages = response
            
            // Load campaign names
            let campaignIds = Set(allLandingPages.map { $0.campaignId })
            for campaignId in campaignIds {
                do {
                    let campaign = try await campaignsAPI.fetchCampaign(id: campaignId)
                    campaignNames[campaignId] = campaign.title
                } catch {
                    campaignNames[campaignId] = "Unknown Campaign"
                }
            }
        } catch {
            print("❌ Error loading landing pages: \(error)")
        }
    }
}

