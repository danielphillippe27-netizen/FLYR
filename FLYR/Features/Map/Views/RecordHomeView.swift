import SwiftUI

/// Record tab root: Start Session when idle; campaign map when building session active or when campaign selected on Map; path map for other sessions.
struct RecordHomeView: View {
    @EnvironmentObject private var uiState: AppUIState
    @ObservedObject private var sessionManager = SessionManager.shared

    private var inSessionMode: Bool {
        sessionManager.sessionId != nil || sessionManager.isActive
    }

    var body: some View {
        Group {
            if sessionManager.sessionId != nil, let campaignId = sessionManager.campaignId {
                CampaignMapView(campaignId: campaignId.uuidString)
            } else if sessionManager.isActive {
                SessionMapView()
            } else if let campaignId = uiState.selectedMapCampaignId {
                // Campaign selected on Map tab: show campaign map ready to start session (Tap Record = ready)
                CampaignMapView(campaignId: campaignId.uuidString)
            } else {
                SessionStartView(showCancelButton: false)
            }
        }
        .toolbar(inSessionMode ? .hidden : .visible, for: .navigationBar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // End session summary is presented from MainTabView.fullScreenCover so it always shows on top
    }
}

#Preview {
    RecordHomeView()
}
