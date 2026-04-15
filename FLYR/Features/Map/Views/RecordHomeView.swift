import SwiftUI

/// Session tab root: Start Session when idle; campaign map when a campaign is selected; path map for other sessions.
struct RecordHomeView: View {
    @EnvironmentObject private var uiState: AppUIState
    @ObservedObject private var sessionManager = SessionManager.shared

    private var activeRouteWorkContext: RouteWorkContext? {
        guard let ctx = uiState.selectedRouteWorkContext,
              let mapId = recordTabMapCampaignId,
              ctx.campaignId == mapId else {
            return nil
        }
        return ctx
    }

    /// One stable campaign id for the map so starting a session does not swap view branches (avoids full map reload).
    private var recordTabMapCampaignId: UUID? {
        sessionManager.campaignId ?? uiState.selectedMapCampaignId
    }

    private var inSessionMode: Bool {
        sessionManager.sessionId != nil || sessionManager.isActive
    }

    var body: some View {
        Group {
            if sessionManager.isActive, sessionManager.campaignId == nil {
                legacySessionFallbackView
            } else if let campaignId = recordTabMapCampaignId {
                CampaignMapView(
                    campaignId: campaignId.uuidString,
                    routeWorkContext: activeRouteWorkContext,
                    onDismissFromMap: inSessionMode ? nil : {
                        uiState.clearMapSelection()
                    }
                )
                .id(campaignId.uuidString.lowercased())
            } else {
                SessionStartView(showCancelButton: false)
            }
        }
        .toolbar(inSessionMode ? .hidden : .visible, for: .navigationBar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // End session summary is presented from MainTabView.fullScreenCover so it always shows on top
    }

    private var legacySessionFallbackView: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Legacy session detected")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.text)
                Text("This session format is no longer supported. End it and start a campaign session to continue.")
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
                Button {
                    HapticManager.light()
                    SessionManager.shared.stop()
                } label: {
                    Text("End Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    RecordHomeView()
}
