import SwiftUI

struct CampaignsView: View {
    @State private var campaignFilter: CampaignFilter = .active
    @State private var showingNewCampaign = false
    @State private var selectedCampaignID: UUID?

    @StateObject private var storeV2 = CampaignV2Store.shared
    @EnvironmentObject private var uiState: AppUIState

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
        .onAppear {
            storeV2.routeToV2Detail = { campaignID in
                selectedCampaignID = campaignID
            }
        }
    }

    private var listContent: some View {
        CampaignsListView(
            externalFilter: $campaignFilter,
            onCreateCampaignTapped: createCampaignTapped,
            onCampaignTapped: { selectedCampaignID = $0 }
        )
    }
    
    /// Same action for toolbar + and empty state "+ Create Campaign" button.
    private func createCampaignTapped() {
        HapticManager.light()
        showingNewCampaign = true
    }
}

#Preview {
    NavigationStack {
        CampaignsView()
            .environmentObject(AppUIState())
    }
}
