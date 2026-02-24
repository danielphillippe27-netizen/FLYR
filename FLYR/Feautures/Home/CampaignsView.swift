import SwiftUI

struct CampaignsView: View {
    @State private var campaignFilter: CampaignFilter = .active
    @State private var showingNewCampaign = false
    @State private var showPaywall = false
    @State private var selectedCampaignID: UUID?

    @StateObject private var storeV2 = CampaignV2Store.shared
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var entitlementsService: EntitlementsService

    var body: some View {
        VStack(spacing: 0) {
            listContent
        }
        .navigationTitle("Campaigns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(CampaignFilter.allCases) { filterOption in
                        Button(filterOption.rawValue) {
                            campaignFilter = filterOption
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(campaignFilter.rawValue)
                            .font(.system(size: 15, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createCampaignTapped()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(item: $selectedCampaignID) { campaignID in
            NewCampaignDetailView(campaignID: campaignID, store: storeV2)
        }
        .fullScreenCover(isPresented: $showingNewCampaign) {
            NavigationStack {
                NewCampaignScreen(store: storeV2)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                showingNewCampaign = false
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            storeV2.routeToV2Detail = { campaignID in
                selectedCampaignID = campaignID
            }
        }
    }

    private var listContent: some View {
        CampaignsListView(
            externalFilter: $campaignFilter,
            showCreateCampaign: $showingNewCampaign,
            onCreateCampaignTapped: createCampaignTapped,
            onCampaignTapped: { selectedCampaignID = $0 }
        )
    }

    /// Same action for toolbar + and empty state "+ Create Campaign" button.
    private func createCampaignTapped() {
        HapticManager.light()
        Task {
            let canCreate = await canCreateCampaignInCurrentPlan()
            await MainActor.run {
                if canCreate {
                    showingNewCampaign = true
                } else {
                    showPaywall = true
                }
            }
        }
    }

    private func canCreateCampaignInCurrentPlan() async -> Bool {
        if entitlementsService.canUsePro {
            return true
        }
        if !storeV2.campaigns.isEmpty {
            return false
        }
        let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId)
        do {
            let campaigns = try await CampaignsAPI.shared.fetchCampaignsMetadata(workspaceId: workspaceId)
            return campaigns.isEmpty
        } catch {
            return storeV2.campaigns.isEmpty
        }
    }
}

#Preview {
    NavigationStack {
        CampaignsView()
            .environmentObject(AppUIState())
    }
}
