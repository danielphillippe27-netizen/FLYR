import SwiftUI

struct MainTabView: View {
    @State private var campaignContext = CampaignContext()
    @EnvironmentObject var uiState: AppUIState
    @ObservedObject private var sessionManager = SessionManager.shared
    /// Item-driven so cover only shows when we have data; no empty state.
    @State private var endSessionSummaryItem: EndSessionSummaryItem?

    private enum Tab: Int {
        case home = 0, map = 1, record = 2, leads = 3, leaderboard = 4, settings = 5
    }

    private var recordHighlight: Bool {
        uiState.selectedMapCampaignId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch uiState.selectedTabIndex {
                case Tab.home.rawValue:
                    NavigationStack { HomeView() }
                case Tab.map.rawValue:
                    NavigationStack { FullScreenMapView() }
                case Tab.record.rawValue:
                    NavigationStack { RecordHomeView() }
                case Tab.leads.rawValue:
                    NavigationStack { ContactsHubView() }
                case Tab.leaderboard.rawValue:
                    NavigationStack { LeaderboardTabView() }
                case Tab.settings.rawValue:
                    NavigationStack { SettingsView() }
                default:
                    NavigationStack { HomeView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if uiState.showTabBar {
                UberStyleTabBar(
                    selectedIndex: uiState.selectedTabIndex,
                    onSelect: { index in
                        HapticManager.tabSwitch()
                        uiState.selectedTabIndex = index
                    },
                    recordHighlight: recordHighlight,
                    accentColor: campaignContext.accentColor
                )
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .campaignContext(campaignContext)
        .onChange(of: sessionManager.isActive) { _, isActive in
            withAnimation(.easeInOut(duration: 0.25)) {
                uiState.showTabBar = !isActive
            }
        }
        .onChange(of: sessionManager.sessionId) { _, newId in
            withAnimation(.easeInOut(duration: 0.25)) {
                uiState.showTabBar = (newId == nil && !sessionManager.isActive)
            }
            // Clear campaign selection only when starting a session (so Record stays on map when ending; we clear on summary dismiss)
            if newId != nil {
                uiState.selectedMapCampaignId = nil
                uiState.selectedMapCampaignName = nil
            }
        }
        .onAppear {
            let inSession = sessionManager.isActive || sessionManager.sessionId != nil
            if inSession { uiState.showTabBar = false }
        }
        .task {
            await sessionManager.restoreActiveSessionIfNeeded()
        }
        .onChange(of: sessionManager.pendingSessionSummary) { _, newValue in
            guard let data = newValue else { return }
            endSessionSummaryItem = EndSessionSummaryItem(data: data)
            sessionManager.pendingSessionSummary = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionEnded)) { _ in
            // Fallback if @Published wasn't observed (e.g. tab not in hierarchy when session ended)
            if endSessionSummaryItem == nil, let data = SessionManager.lastEndedSummary {
                endSessionSummaryItem = EndSessionSummaryItem(data: data)
            }
        }
        .fullScreenCover(item: $endSessionSummaryItem) { item in
            ShareActivityGateView(data: item.data) {
                endSessionSummaryItem = nil
                sessionManager.pendingSessionSummary = nil
                uiState.selectedMapCampaignId = nil
                uiState.selectedMapCampaignName = nil
            }
        }
    }
}
