import SwiftUI

struct MainTabView: View {
    @State private var campaignContext = CampaignContext()
    @EnvironmentObject var uiState: AppUIState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var sessionManager = SessionManager.shared
    @StateObject private var storeV2 = CampaignV2Store.shared
    @StateObject private var provisionMonitor = CampaignProvisionMonitor.shared
    @State private var showingNewCampaign = false
    @State private var resumedCreatingCampaignId: UUID?
    /// Item-driven so cover only shows when we have data; no empty state.
    @State private var endSessionSummaryItem: EndSessionSummaryItem?
    private struct MainReplayRequest {
        let campaign: CampaignV2
        let sessionID: UUID
    }
    @State private var pendingMainReplay: MainReplayRequest?
    @State private var pendingMainReplayLaunch: DemoSessionLaunchConfiguration?
    @State private var activeMainReplay: DemoSessionLaunchConfiguration?
    @State private var pendingMainReplaySummary: EndSessionSummaryItem?
    @State private var showMainReplaySettings = false
    @State private var preparingMainReplay = false
    @State private var mainReplayError: String?


    private enum Tab: Int {
        case home = 0, record = 1, leads = 2, more = 3, settings = 4
    }

    private var recordHighlight: Bool {
        uiState.selectedMapCampaignId != nil
    }

    private var shouldShowTabBar: Bool {
        uiState.showTabBar
    }

    private var resumedCreatingCampaignBinding: Binding<Bool> {
        Binding(
            get: { resumedCreatingCampaignId != nil },
            set: { isPresented in
                if !isPresented {
                    resumedCreatingCampaignId = nil
                }
            }
        )
    }

    @MainActor
    private func syncTrackedCampaignCreationPresentation() {
        let externalCampaignCreationFlowIsPresented =
            uiState.isCampaignCreationFlowPresented && !showingNewCampaign && resumedCreatingCampaignId == nil
        guard !externalCampaignCreationFlowIsPresented else {
            return
        }

        guard !showingNewCampaign else {
            return
        }

        guard let tracked = provisionMonitor.tracked else {
            resumedCreatingCampaignId = nil
            return
        }

        if tracked.isRunning {
            resumedCreatingCampaignId = tracked.campaignId
            return
        }

        if resumedCreatingCampaignId == tracked.campaignId, tracked.state == .ready {
            return
        }

        if resumedCreatingCampaignId == tracked.campaignId {
            resumedCreatingCampaignId = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch uiState.selectedTabIndex {
                case Tab.home.rawValue:
                    // Each Home destination owns its navigation stack.
                    WolfyHomeView()
                case Tab.record.rawValue:
                    NavigationStack { RecordHomeView() }
                case Tab.leads.rawValue:
                    // ContactsHubView owns NavigationStack + lead destination.
                    ContactsHubView()
                case Tab.more.rawValue:
                    HomeView()
                case Tab.settings.rawValue:
                    // SettingsView owns NavigationStack around its form.
                    SettingsView()
                default:
                    WolfyHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if shouldShowTabBar {
                UberStyleTabBar(
                    selectedIndex: uiState.selectedTabIndex,
                    onSelect: { index in
                        HapticManager.tabSwitch()
                        uiState.selectedTabIndex = index
                    },
                    onCreate: {
                        HapticManager.light()
                        showingNewCampaign = true
                    },
                    recordHighlight: recordHighlight,
                    accentColor: campaignContext.accentColor,
                    mode: .standard
                )
            }
        }
        .background(Color.bg)
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
            // Keep the selected campaign while a session is starting so RecordHomeView
            // does not briefly lose its map context. The selection is cleared after
            // the end-session summary is dismissed.
        }
        .onAppear {
            CampaignNotificationRouter.shared.configure(uiState: uiState)
            normalizeSelectedTab()
            let inSession = sessionManager.isActive || sessionManager.sessionId != nil
            if inSession, !sessionManager.sessionRestoredThisLaunch {
                uiState.showTabBar = false
            } else {
                uiState.showTabBar = true
            }
        }
        .task {
            await sessionManager.restoreActiveSessionIfNeeded()
            await provisionMonitor.refreshLatest()
            syncTrackedCampaignCreationPresentation()
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
        .fullScreenCover(isPresented: resumedCreatingCampaignBinding) {
            if let resumedCreatingCampaignId {
                NavigationStack {
                    NewCampaignScreen(
                        store: storeV2,
                        resumedCampaignId: resumedCreatingCampaignId
                    )
                }
            }
        }
        .sheet(item: $uiState.pendingBusinessCardActivity) { route in
            BusinessCardPushActivityView(route: route)
        }
        .task(id: resumedCreatingCampaignId) {
            guard resumedCreatingCampaignId != nil else { return }
            while !Task.isCancelled, resumedCreatingCampaignId != nil {
                await provisionMonitor.refreshLatest()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .onChange(of: provisionMonitor.tracked) { _, _ in
            syncTrackedCampaignCreationPresentation()
        }
        .onChange(of: showingNewCampaign) { _, _ in
            syncTrackedCampaignCreationPresentation()
        }
        .fullScreenCover(isPresented: $sessionManager.staleActiveSessionNeedsResolution) {
            StaleActiveSessionResolutionView(sessionManager: sessionManager)
                .interactiveDismissDisabled(true)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await sessionManager.appDidBecomeActive()
                    await provisionMonitor.refreshLatest()
                    syncTrackedCampaignCreationPresentation()
                    CampaignNotificationRouter.shared.applyPendingRouteIfPossible()
                    await PushRegistrationService.shared.uploadPendingTokenIfPossible()
                }
            case .inactive, .background:
                Task { await sessionManager.appDidEnterBackground() }
            @unknown default:
                break
            }
        }
        .onChange(of: sessionManager.pendingSessionSummary) { _, newValue in
            guard let data = newValue else { return }
            if activeMainReplay != nil || pendingMainReplaySummary != nil {
                if pendingMainReplaySummary == nil {
                    pendingMainReplaySummary = EndSessionSummaryItem(data: data, sessionID: sessionManager.pendingSessionSummarySessionId, campaignMapSnapshot: SessionManager.lastEndedSummaryMapSnapshot)
                }
                activeMainReplay = nil
                sessionManager.pendingSessionSummary = nil
                sessionManager.pendingSessionSummarySessionId = nil
                return
            }
            endSessionSummaryItem = EndSessionSummaryItem(
                data: data,
                sessionID: sessionManager.pendingSessionSummarySessionId,
                campaignMapSnapshot: SessionManager.lastEndedSummaryMapSnapshot
            )
            if let sessionId = sessionManager.pendingSessionSummarySessionId {
                Task {
                    if let persisted = try? await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionId) {
                        await MainActor.run {
                            guard endSessionSummaryItem?.sessionID == sessionId else { return }
                            let preservedSegments = endSessionSummaryItem?.data.renderedPathSegments
                            let preservedHomeCoordinates = endSessionSummaryItem?.data.completedHomeCoordinates ?? []
                            let preservedNetworking = endSessionSummaryItem?.data.isNetworkingSession ?? false
                            let preservedDemo = endSessionSummaryItem?.data.isDemoSession ?? false
                            let preservedCampaignSnapshot = endSessionSummaryItem?.campaignMapSnapshot
                            let summary = persisted.toSummaryData()
                                .withRenderedPathSegments(preservedSegments)
                                .withCompletedHomeCoordinates(preservedHomeCoordinates)
                                .withIsNetworkingSession(preservedNetworking)
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
            if activeMainReplay != nil || pendingMainReplaySummary != nil {
                if pendingMainReplaySummary == nil, let data = SessionManager.lastEndedSummary {
                    pendingMainReplaySummary = EndSessionSummaryItem(data: data, sessionID: SessionManager.lastEndedSessionId, campaignMapSnapshot: SessionManager.lastEndedSummaryMapSnapshot)
                    activeMainReplay = nil
                }
                return
            }
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
                                guard endSessionSummaryItem?.sessionID == sessionId else { return }
                                let preservedSegments = endSessionSummaryItem?.data.renderedPathSegments
                                let preservedHomeCoordinates = endSessionSummaryItem?.data.completedHomeCoordinates ?? []
                                let preservedNetworking = endSessionSummaryItem?.data.isNetworkingSession ?? false
                                let preservedDemo = endSessionSummaryItem?.data.isDemoSession ?? false
                                let preservedCampaignSnapshot = endSessionSummaryItem?.campaignMapSnapshot
                                let summary = persisted.toSummaryData()
                                    .withRenderedPathSegments(preservedSegments)
                                    .withCompletedHomeCoordinates(preservedHomeCoordinates)
                                    .withIsNetworkingSession(preservedNetworking)
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
        .fullScreenCover(item: $endSessionSummaryItem, onDismiss: {
            if pendingMainReplay != nil { showMainReplaySettings = true }
        }) { item in
            ShareActivityGateView(
                data: item.data,
                sessionID: item.sessionID,
                campaignMapSnapshot: item.campaignMapSnapshot,
                onCreateReplay: item.sessionID == nil || item.data.isDemoSession || item.data.isNetworkingSession || preparingMainReplay || sessionManager.isEndingSession ? nil : {
                    guard let sessionID = item.sessionID else { return }
                    Task { await prepareMainReplay(sessionID: sessionID) }
                },
                onDismiss: {
                    endSessionSummaryItem = nil
                    sessionManager.pendingSessionSummary = nil
                    sessionManager.pendingSessionSummarySessionId = nil
                    uiState.clearMapSelection()
                }
            )
            .alert("Replay unavailable", isPresented: Binding(
                get: { mainReplayError != nil }, set: { if !$0 { mainReplayError = nil } }
            )) {
                Button("OK", role: .cancel) { mainReplayError = nil }
            } message: {
                Text(mainReplayError ?? "")
            }
        }
        .sheet(isPresented: $showMainReplaySettings, onDismiss: {
            guard let configuration = pendingMainReplayLaunch else {
                pendingMainReplay = nil
                return
            }
            pendingMainReplayLaunch = nil
            pendingMainReplay = nil
            activeMainReplay = configuration
        }) {
            if let request = pendingMainReplay {
                DemoSessionConfigSheet(campaigns: [request.campaign], defaultCampaignID: request.campaign.id,
                    saveVideo: true, recordedSessionID: request.sessionID) { configuration in
                    pendingMainReplayLaunch = configuration
                    showMainReplaySettings = false
                }
            }
        }
        .fullScreenCover(item: $activeMainReplay, onDismiss: {
            guard let summary = pendingMainReplaySummary else { return }
            pendingMainReplaySummary = nil
            endSessionSummaryItem = summary
        }) { configuration in
            CampaignMapView(campaignId: configuration.campaign.id.uuidString,
                showPreSessionStartButton: false, demoLaunchConfiguration: configuration,
                onDismissFromMap: { activeMainReplay = nil })
        }
    }

    @MainActor
    private func prepareMainReplay(sessionID: UUID) async {
        guard !preparingMainReplay, sessionManager.sessionId == nil, !sessionManager.isEndingSession else { return }
        preparingMainReplay = true
        defer { preparingMainReplay = false }
        do {
            guard let session = try await ActivityFeedService.shared.fetchSessionRecord(sessionId: sessionID),
                  let campaignID = session.campaign_id else {
                throw NSError(domain: "RecordedReplay", code: 1, userInfo: [NSLocalizedDescriptionKey: "This activity is not linked to a campaign."])
            }
            let campaign: CampaignV2
            if let cached = storeV2.campaign(id: campaignID) {
                campaign = cached
            } else {
                campaign = try await sharedV2API.fetchCampaign(id: campaignID)
            }
            guard endSessionSummaryItem?.sessionID == sessionID else { return }
            pendingMainReplay = MainReplayRequest(campaign: campaign, sessionID: sessionID)
            endSessionSummaryItem = nil
        } catch {
            mainReplayError = error.localizedDescription
        }
    }

    private func normalizeSelectedTab() {
        if !(Tab.home.rawValue...Tab.settings.rawValue).contains(uiState.selectedTabIndex) {
            uiState.selectedTabIndex = 0
        }
    }
}
