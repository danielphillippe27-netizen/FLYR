import SwiftUI

struct MainTabView: View {
    @State private var campaignContext = CampaignContext()
    @EnvironmentObject var uiState: AppUIState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var sessionManager = SessionManager.shared
    /// Item-driven so cover only shows when we have data; no empty state.
    @State private var endSessionSummaryItem: EndSessionSummaryItem?

    private enum Tab: Int {
        case home = 0, record = 1, leads = 2, leaderboard = 3, settings = 4
    }

    private var recordHighlight: Bool {
        uiState.selectedMapCampaignId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch uiState.selectedTabIndex {
                case Tab.home.rawValue:
                    // HomeView owns NavigationStack(path:) + destinations; an outer stack causes path type mismatch crashes.
                    HomeView()
                case Tab.record.rawValue:
                    NavigationStack { RecordHomeView() }
                case Tab.leads.rawValue:
                    // ContactsHubView owns NavigationStack + lead destination.
                    ContactsHubView()
                case Tab.leaderboard.rawValue:
                    NavigationStack { LeaderboardTabView() }
                case Tab.settings.rawValue:
                    // SettingsView owns NavigationStack around its form.
                    SettingsView()
                default:
                    HomeView()
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
                uiState.showTabBar = !isActive || sessionManager.sessionRestoredThisLaunch
            }
        }
        .onChange(of: sessionManager.sessionId) { _, newId in
            withAnimation(.easeInOut(duration: 0.25)) {
                uiState.showTabBar = (newId == nil && !sessionManager.isActive) || sessionManager.sessionRestoredThisLaunch
            }
            // Clear campaign selection only when starting a session (so Record stays on map when ending; we clear on summary dismiss)
            if newId != nil {
                uiState.selectedMapCampaignId = nil
                uiState.selectedMapCampaignName = nil
            }
        }
        .onAppear {
            let inSession = sessionManager.isActive || sessionManager.sessionId != nil
            if inSession, !sessionManager.sessionRestoredThisLaunch {
                uiState.showTabBar = false
            } else {
                uiState.showTabBar = true
            }
        }
        .task {
            await sessionManager.restoreActiveSessionIfNeeded()
        }
        .fullScreenCover(isPresented: $sessionManager.staleActiveSessionNeedsResolution) {
            StaleActiveSessionResolutionView(sessionManager: sessionManager)
                .interactiveDismissDisabled(true)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await sessionManager.appDidBecomeActive() }
            case .inactive, .background:
                Task { await sessionManager.appDidEnterBackground() }
            @unknown default:
                break
            }
        }
        .onChange(of: sessionManager.pendingSessionSummary) { _, newValue in
            guard let data = newValue else { return }
            endSessionSummaryItem = EndSessionSummaryItem(
                data: data,
                sessionID: sessionManager.pendingSessionSummarySessionId,
                campaignMapSnapshot: SessionManager.lastEndedSummaryMapSnapshot
            )
            if let sessionId = sessionManager.pendingSessionSummarySessionId {
                Task {
                    if let persisted = try? await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionId) {
                        await MainActor.run {
                            let preservedSegments = endSessionSummaryItem?.data.renderedPathSegments
                            let preservedHomeCoordinates = endSessionSummaryItem?.data.completedHomeCoordinates ?? []
                            let preservedDemo = endSessionSummaryItem?.data.isDemoSession ?? false
                            let preservedCampaignSnapshot = endSessionSummaryItem?.campaignMapSnapshot
                            let summary = persisted.toSummaryData()
                                .withRenderedPathSegments(preservedSegments)
                                .withCompletedHomeCoordinates(preservedHomeCoordinates)
                                .withIsDemoSession(preservedDemo)
                            endSessionSummaryItem = EndSessionSummaryItem(
                                data: summary,
                                sessionID: sessionId,
                                campaignMapSnapshot: preservedCampaignSnapshot
                            )
                        }
                    }
                }
            }
            sessionManager.pendingSessionSummary = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionEnded)) { _ in
            // Fallback if @Published wasn't observed (e.g. tab not in hierarchy when session ended)
            if endSessionSummaryItem == nil, let data = SessionManager.lastEndedSummary {
                endSessionSummaryItem = EndSessionSummaryItem(
                    data: data,
                    sessionID: SessionManager.lastEndedSessionId,
                    campaignMapSnapshot: SessionManager.lastEndedSummaryMapSnapshot
                )
                if let sessionId = SessionManager.lastEndedSessionId {
                    Task {
                        if let persisted = try? await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionId) {
                            await MainActor.run {
                                let preservedSegments = endSessionSummaryItem?.data.renderedPathSegments
                                let preservedHomeCoordinates = endSessionSummaryItem?.data.completedHomeCoordinates ?? []
                                let preservedDemo = endSessionSummaryItem?.data.isDemoSession ?? false
                                let preservedCampaignSnapshot = endSessionSummaryItem?.campaignMapSnapshot
                                let summary = persisted.toSummaryData()
                                    .withRenderedPathSegments(preservedSegments)
                                    .withCompletedHomeCoordinates(preservedHomeCoordinates)
                                    .withIsDemoSession(preservedDemo)
                                endSessionSummaryItem = EndSessionSummaryItem(
                                    data: summary,
                                    sessionID: sessionId,
                                    campaignMapSnapshot: preservedCampaignSnapshot
                                )
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $endSessionSummaryItem) { item in
            ShareActivityGateView(
                data: item.data,
                sessionID: item.sessionID,
                campaignMapSnapshot: item.campaignMapSnapshot
            ) {
                endSessionSummaryItem = nil
                sessionManager.pendingSessionSummary = nil
                sessionManager.pendingSessionSummarySessionId = nil
                uiState.clearMapSelection()
            }
        }
    }
}
