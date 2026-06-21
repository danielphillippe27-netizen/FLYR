import SwiftUI

struct MainTabView: View {
    @State private var campaignContext = CampaignContext()
    @EnvironmentObject var uiState: AppUIState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var sessionManager = SessionManager.shared
    @StateObject private var workspaceContext = WorkspaceContext.shared
    @StateObject private var storeV2 = CampaignV2Store.shared
    @StateObject private var provisionMonitor = CampaignProvisionMonitor.shared
    @State private var showingNewCampaign = false
    @State private var resumedCreatingCampaignId: UUID?
    /// Item-driven so cover only shows when we have data; no empty state.
    @State private var endSessionSummaryItem: EndSessionSummaryItem?

    private enum Tab: Int {
        case home = 0, record = 1, leads = 2, calendar = 3, settings = 4
    }

    private enum SalespersonTab: Int {
        case home = 0, dialler = 1, leads = 2, inbox = 3, task = 4
    }

    private var isSalespersonMode: Bool {
        workspaceContext.isSalespersonDashboardEnabled
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
                if isSalespersonMode {
                    switch uiState.selectedTabIndex {
                    case SalespersonTab.home.rawValue:
                        SalespersonHomeView()
                    case SalespersonTab.dialler.rawValue:
                        SalespersonDiallerView()
                    case SalespersonTab.leads.rawValue:
                        SalespersonLeadsView()
                    case SalespersonTab.inbox.rawValue:
                        SalespersonInboxView()
                    case SalespersonTab.task.rawValue:
                        SalespersonTasksView()
                    default:
                        SalespersonHomeView()
                    }
                } else {
                    switch uiState.selectedTabIndex {
                    case Tab.home.rawValue:
                        // HomeView owns NavigationStack(path:) + destinations; an outer stack causes path type mismatch crashes.
                        HomeView()
                    case Tab.record.rawValue:
                        NavigationStack { RecordHomeView() }
                    case Tab.leads.rawValue:
                        // ContactsHubView owns NavigationStack + lead destination.
                        ContactsHubView()
                    case Tab.calendar.rawValue:
                        NavigationStack { CalendarTabView() }
                    case Tab.settings.rawValue:
                        // SettingsView owns NavigationStack around its form.
                        SettingsView()
                    default:
                        HomeView()
                    }
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
                    mode: isSalespersonMode ? .salesperson : .standard
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
            normalizeSelectedTabForCurrentMode()
            if isSalespersonMode {
                Task { await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded() }
            }
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
        .onChange(of: isSalespersonMode) { _, _ in
            normalizeSelectedTabForCurrentMode()
            if isSalespersonMode {
                Task { await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded(force: true) }
            }
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
                    if isSalespersonMode {
                        await SalespersonVoiceCallService.shared.refreshRegistrationIfNeeded()
                    }
                }
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

    private func normalizeSelectedTabForCurrentMode() {
        let maxIndex = isSalespersonMode ? SalespersonTab.task.rawValue : Tab.calendar.rawValue
        if uiState.selectedTabIndex > maxIndex {
            uiState.selectedTabIndex = 0
        }
    }
}
