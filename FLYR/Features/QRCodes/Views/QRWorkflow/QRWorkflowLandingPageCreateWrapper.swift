import SwiftUI
import Combine

/// Wrapper view that goes directly to the designer, auto-selecting the first campaign
struct QRWorkflowLandingPageCreateWrapper: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (UUID) -> Void
    
    @StateObject private var viewModel = QRWorkflowLandingPageCreateWrapperViewModel()
    @State private var selectedCampaignId: UUID?
    
    var body: some View {
        NavigationStack {
            if let campaignId = selectedCampaignId,
               let campaign = viewModel.campaigns.first(where: { $0.id == campaignId }) {
                LandingPageCreateView(
                    campaignId: campaignId,
                    campaignName: campaign.name,
                    onCreated: {
                        // After creation, fetch the landing page ID and call onSave
                        Task {
                            if let landingPage = try? await SupabaseLandingPageService.shared.fetchLandingPage(campaignId: campaignId) {
                                await MainActor.run {
                                    onSave(landingPage.id)
                                    dismiss()
                                }
                            }
                        }
                    }
                )
            } else if viewModel.isLoadingCampaigns {
                ProgressView("Loading campaigns...")
                    .navigationTitle("Create Landing Page")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                dismiss()
                            }
                        }
                    }
            } else if let firstCampaign = viewModel.campaigns.first {
                // Auto-select first campaign and show designer immediately
                LandingPageCreateView(
                    campaignId: firstCampaign.id,
                    campaignName: firstCampaign.name,
                    onCreated: {
                        Task {
                            if let landingPage = try? await SupabaseLandingPageService.shared.fetchLandingPage(campaignId: firstCampaign.id) {
                                await MainActor.run {
                                    onSave(landingPage.id)
                                    dismiss()
                                }
                            }
                        }
                    }
                )
                .task {
                    // Auto-select first campaign
                    selectedCampaignId = firstCampaign.id
                }
            } else {
                // No campaigns - show error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.muted)
                    
                    Text("No Campaigns")
                        .font(.headline)
                        .foregroundColor(.text)
                    
                    Text("You need to create a campaign first before creating a landing page.")
                        .font(.subheadline)
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .navigationTitle("Create Landing Page")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadCampaigns()
        }
    }
}

@MainActor
class QRWorkflowLandingPageCreateWrapperViewModel: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var isLoadingCampaigns = false
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

