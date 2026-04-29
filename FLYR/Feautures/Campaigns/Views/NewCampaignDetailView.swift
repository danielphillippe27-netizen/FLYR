import SwiftUI
import CoreLocation

/// Navigation payload for Support from campaign feedback (draft + same suggestions as Support UI).
private struct CampaignSupportFeedbackRoute: Hashable {
    let draft: String
    let hiddenAttachmentPayload: String
}

/// Detail view for CampaignV2
struct NewCampaignDetailView: View {
    let campaignID: UUID
    @ObservedObject var store: CampaignV2Store
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var uiState: AppUIState
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var offlineSyncCoordinator: OfflineSyncCoordinator
    @EnvironmentObject private var campaignDownloadService: CampaignDownloadService
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var sessionManager = SessionManager.shared
    @StateObject private var hook = UseCampaignV2()
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var isMapFullscreen = false
    @State private var addressStatuses: [String: AddressStatus] = [:]
    @State private var showShareCardView = false
    @State private var selectedAddressId: String? = nil
    @State private var selectedAddressLabel: String = ""
    @State private var isStatusSheetPresented = false
    @State private var isAddressesExpanded = false
    @State private var showFullAddressesSheet = false
    @State private var isLeadsExpanded = false
    @State private var campaignLeadsCount: Int = 0
    @State private var campaignLeads: [FieldLead] = []
    @State private var selectedLead: FieldLead?
    @State private var leadsLoaded = false
    @State private var isActivityExpanded = false
    @State private var campaignActivities: [SessionRecord] = []
    @State private var activityCount: Int = 0
    @State private var activitiesLoaded = false
    /// When set, share card is shown for this specific activity (tapped from Activity list).
    @State private var selectedSessionForShare: SessionRecord? = nil
    @State private var supportFeedbackRoute: CampaignSupportFeedbackRoute?
    @State private var showDemoConfigSheet = false
    @State private var activeDemoLaunchConfiguration: DemoSessionLaunchConfiguration?
    @State private var awaitingDemoSummary = false
    @State private var demoSummaryItem: EndSessionSummaryItem?
    @Namespace private var mapNamespace

    private static let campaignFeedbackQuickSuggestions: [String] = [
        "Bad data quality",
        "Houses not showing",
        "Houses not saving",
        "Polygon/bbox mismatch"
    ]

    private var presentation: CampaignDetailPresentation? {
        guard let campaign = hook.item else { return nil }
        return CampaignDetailPresentation(
            campaign: campaign,
            sessions: campaignActivities,
            fieldLeads: campaignLeads,
            addressStatuses: addressStatuses
        )
    }

    private var effectiveProgressValue: Double {
        presentation?.progressValue ?? hook.item?.progress ?? 0
    }

    private var effectiveProgressLabel: Int {
        Int((effectiveProgressValue * 100).rounded())
    }

    private var effectiveCampaignLeads: [FieldLead] {
        if !campaignLeads.isEmpty {
            return campaignLeads
        }
        return presentation?.syntheticLeads ?? []
    }

    private var effectiveCampaignLeadsCount: Int {
        if campaignLeadsCount > 0 {
            return campaignLeadsCount
        }
        return effectiveCampaignLeads.count
    }

    private var shouldShowFullDemoStatsCard: Bool {
        presentation?.isJustListedMearnsDemo == true
    }

    private var isFounderDemoEnabled: Bool {
        DemoFounderAccess.isAllowed(user: authManager.user)
    }

    private var demoCampaignOptions: [CampaignV2] {
        let combined = store.campaigns + (hook.item.map { [$0] } ?? [])
        var seen = Set<UUID>()
        return combined.filter { seen.insert($0.id).inserted }
    }

    // Pro Mode: Campaign markers for map
    private var campaignMarkers: [MapMarker] {
        guard let campaign = hook.item else { return [] }
        
        var markers: [MapMarker] = []
        
        if let mapCenter {
            markers.append(MapMarker(
                coordinate: mapCenter,
                title: campaign.name,
                color: "red"
            ))
        }
        
        // Add address markers
        for (index, address) in campaign.addresses.prefix(5).enumerated() {
            if let coordinate = address.coordinate {
                markers.append(MapMarker(
                    coordinate: coordinate,
                    title: "Address \(index + 1)",
                    color: "blue"
                ))
            }
        }
        
        return markers
    }

    /// Placeholder for share card when no session has ended yet (e.g. opened from Campaign Details).
    private var placeholderShareCardData: SessionSummaryData {
        SessionSummaryData(
            distance: 0,
            time: 0,
            goalType: .knocks,
            goalAmount: 0,
            pathCoordinates: [],
            renderedPathSegments: nil,
            completedCount: 0,
            conversationsCount: 0,
            startTime: nil
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(hook.item?.name ?? "Loading...")
                            .font(.heading)
                            .foregroundColor(.text)
                            .onTapGesture(count: 3) {
                                guard isFounderDemoEnabled, hook.item != nil else { return }
                                HapticManager.medium()
                                showDemoConfigSheet = true
                            }
                        
                        Spacer()

                        if hook.item != nil {
                            Button {
                                HapticManager.light()
                                guard let campaign = hook.item else { return }
                                let leads = campaignLeadsCount
                                let sessions = activityCount
                                Task { @MainActor in
                                    let feedbackRoute = await Self.buildCampaignFeedbackDiagnosticsMessage(
                                        campaign: campaign,
                                        leadsCount: leads,
                                        activitySessionsCount: sessions
                                    )
                                    supportFeedbackRoute = feedbackRoute
                                }
                            } label: {
                                Text("Feedback")
                                    .font(.label)
                                    .fontWeight(.medium)
                                    .foregroundColor(.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.bgSecondary)
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                Color.accent.opacity(colorScheme == .dark ? 0.6 : 0.35),
                                                lineWidth: 1
                                            )
                                    )
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if let campaign = hook.item {
                        Text("Created \(campaign.createdAt, formatter: dateFormatter)")
                            .font(.flyrCaption)
                            .foregroundColor(.muted)
                    }
                }
                
                // Progress Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Progress")
                            .font(.subheading)
                            .foregroundColor(.text)
                        
                        Spacer()
                        
                        if hook.item != nil {
                            Text("\(effectiveProgressLabel)% completed")
                                .font(.label)
                                .fontWeight(.medium)
                                .foregroundColor(.text)
                        }
                    }
                    
                    if hook.item != nil {
                        ProgressBar(value: effectiveProgressValue)
                    }
                }
                .padding(16)
                .background(Color.bgSecondary)
                .cornerRadius(12)

                // Map Section - 3D Campaign Map (MapFeaturesService + MapLayerManager)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Campaign Area")
                        .font(.subheading)
                        .foregroundColor(.text)
                    
                    ZStack {
                        CampaignMapView(
                            campaignId: campaignID.uuidString,
                            initialCenter: mapCenter,
                            showPreSessionStartButton: false
                        )
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .matchedGeometryEffect(id: "map", in: mapNamespace, isSource: !isMapFullscreen)
                        
                        // Fullscreen trigger
                        Button(action: {
                            HapticManager.medium()
                            isMapFullscreen = true
                        }) {
                            Color.clear
                                .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.flyrCaption)
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(8)
                        }
                    }
                }
                .fullScreenCover(isPresented: $isMapFullscreen) {
                    FullscreenMapView(
                        campaignID: campaignID,
                        namespace: mapNamespace,
                        isSource: true,
                        onClose: { isMapFullscreen = false }
                    )
                }
                
                // Analytics Section
                if hook.item != nil {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Analytics")
                            .font(.subheading)
                            .foregroundColor(.text)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            if !activitiesLoaded {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else if let presentation, presentation.hasAnalytics {
                                if shouldShowFullDemoStatsCard {
                                    DemoCampaignFullStatsCard(presentation: presentation)
                                } else {
                                    StatGrid(stats: presentation.analyticsStats, columns: 2)
                                }
                            } else if campaignActivities.isEmpty {
                                Text("No session activity yet")
                                    .font(.body)
                                    .foregroundColor(.muted)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(16)
                        .background(Color.bgSecondary)
                        .cornerRadius(12)
                    }
                }

                offlineAvailabilitySection
                
                // Leads Section (collapsible, same style as Addresses)
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLeadsExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "tray.full.fill")
                                .font(.subheadline)
                                .foregroundColor(.accent)
                            Text("Leads")
                                .font(.subheading)
                                .foregroundColor(.text)
                            Spacer()
                            Text("\(effectiveCampaignLeadsCount) total")
                                .font(.label)
                                .foregroundColor(.muted)
                            Image(systemName: isLeadsExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.muted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onChange(of: isLeadsExpanded) { _, expanded in
                        if expanded && !leadsLoaded && networkMonitor.isOnline, let userId = AuthManager.shared.user?.id {
                            Task {
                                do {
                                    let leads = try await FieldLeadsService.shared.fetchLeads(userId: userId, workspaceId: WorkspaceContext.shared.workspaceId, campaignId: campaignID)
                                    await MainActor.run {
                                        campaignLeads = leads
                                        campaignLeadsCount = leads.count
                                        leadsLoaded = true
                                    }
                                } catch {
                                    await MainActor.run {
                                        campaignLeads = []
                                        leadsLoaded = true
                                    }
                                }
                            }
                        } else if expanded && !leadsLoaded && !networkMonitor.isOnline {
                            leadsLoaded = true
                        }
                    }

                    if isLeadsExpanded {
                        if !effectiveCampaignLeads.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(effectiveCampaignLeads.prefix(5).enumerated()), id: \.element.id) { index, lead in
                                    Button {
                                        HapticManager.light()
                                        selectedLead = lead
                                    } label: {
                                        HStack {
                                            Text("\(index + 1).")
                                                .font(.flyrCaption)
                                                .foregroundColor(.muted)
                                                .frame(width: 20, alignment: .leading)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(lead.address)
                                                    .font(.body)
                                                    .foregroundColor(.text)
                                                if let name = lead.name, !name.isEmpty {
                                                    Text(name)
                                                        .font(.flyrCaption)
                                                        .foregroundColor(.muted)
                                                }
                                            }
                                            Spacer()
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .buttonStyle(.plain)
                                }
                                if effectiveCampaignLeads.count > 5 {
                                    Button("See all \(effectiveCampaignLeads.count) leads") {
                                        // TODO: Show full leads list
                                    }
                                    .font(.label)
                                    .foregroundColor(.accent)
                                }
                            }
                            .padding(12)
                            .background(Color.bgTertiary)
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        } else if leadsLoaded {
                            Text("No leads yet")
                                .font(.body)
                                .foregroundColor(.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
                .background(Color.bgSecondary)
                .cornerRadius(12)

                // Addresses Section (collapsible, at bottom, hidden by default)
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAddressesExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "house.fill")
                                .font(.subheadline)
                                .foregroundColor(.accent)
                            Text("Addresses")
                                .font(.subheading)
                                .foregroundColor(.text)
                            Spacer()
                            if let campaign = hook.item {
                                Text("\(campaign.addresses.count) total")
                                    .font(.label)
                                    .foregroundColor(.muted)
                            }
                            Image(systemName: isAddressesExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.muted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isAddressesExpanded {
                        if let campaign = hook.item, !campaign.addresses.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(campaign.addresses.prefix(5).enumerated()), id: \.offset) { index, address in
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.flyrCaption)
                                            .foregroundColor(.muted)
                                            .frame(width: 20, alignment: .leading)
                                        Text(address.address)
                                            .font(.body)
                                            .foregroundColor(.text)
                                        Spacer()
                                    }
                                }
                                if campaign.addresses.count > 5 {
                                    Button("See all \(campaign.addresses.count) addresses") {
                                        HapticManager.light()
                                        showFullAddressesSheet = true
                                    }
                                    .font(.label)
                                    .foregroundColor(.accent)
                                }
                            }
                            .padding(12)
                            .background(Color.bgTertiary)
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        } else {
                            Text("No addresses added yet")
                                .font(.body)
                                .foregroundColor(.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
                .background(Color.bgSecondary)
                .cornerRadius(12)

                // Activity Section (collapsible, below Addresses)
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: {
                        HapticManager.light()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isActivityExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "figure.walk")
                                .font(.subheadline)
                                .foregroundColor(.accent)
                            Text("Activity")
                                .font(.subheading)
                                .foregroundColor(.text)
                            Spacer()
                            Text("\(activityCount) total")
                                .font(.label)
                                .foregroundColor(.muted)
                            Image(systemName: isActivityExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.muted)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onChange(of: isActivityExpanded) { _, expanded in
                        if expanded && !activitiesLoaded {
                            Task {
                                await refreshCampaignActivities()
                            }
                        }
                    }

                    if isActivityExpanded {
                        if !campaignActivities.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(campaignActivities.prefix(5).enumerated()), id: \.offset) { index, session in
                                    Button(action: {
                                        HapticManager.light()
                                        selectedSessionForShare = session
                                    }) {
                                        CampaignActivityRow(session: session, index: index + 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                                if campaignActivities.count > 5 {
                                    Button("See all \(campaignActivities.count) sessions") {
                                        // TODO: Show full sessions list
                                    }
                                    .font(.label)
                                    .foregroundColor(.accent)
                                }
                            }
                            .padding(12)
                            .background(Color.bgTertiary)
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                        } else if activitiesLoaded {
                            Text("No activity yet")
                                .font(.body)
                                .foregroundColor(.muted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(Color.bgTertiary)
                                .cornerRadius(8)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                }
                .background(Color.bgSecondary)
                .cornerRadius(12)

                // Session Share Card (underneath Addresses)
                Button(action: { showShareCardView = true }) {
                    Label("Session Share Card", systemImage: "square.and.arrow.up")
                        .font(.label)
                        .fontWeight(.medium)
                        .foregroundColor(.flyrPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.bgSecondary)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                
                Spacer(minLength: 100) // Space for button
            }
            .padding()
        }
        .navigationTitle("Campaign Details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button(action: {
                    HapticManager.medium()
                    uiState.selectCampaign(
                        id: campaignID,
                        name: hook.item?.name,
                        boundaryCoordinates: mapCenter.map { [$0] } ?? []
                    )
                    uiState.selectedTabIndex = 1
                }) {
                    Text("Start Session")
                        .font(.label)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.accent)
                        .cornerRadius(12)
                }
                .padding()
            }
            .background(Color.bg)
        }
        .fullScreenCover(isPresented: Binding(
            get: { showShareCardView || selectedSessionForShare != nil },
            set: { if !$0 { showShareCardView = false; selectedSessionForShare = nil } }
        )) {
            ShareActivityGateView(
                data: effectiveShareCardData(selectedSession: selectedSessionForShare),
                sessionID: selectedSessionForShare?.id,
                campaignMapSnapshot: nil,
                onDismiss: {
                    showShareCardView = false
                    selectedSessionForShare = nil
                }
            )
        }
        .sheet(isPresented: $showFullAddressesSheet) {
            if let campaign = hook.item {
                FullAddressesSheet(addresses: campaign.addresses)
            }
        }
        .sheet(isPresented: $showDemoConfigSheet) {
            DemoSessionConfigSheet(
                campaigns: demoCampaignOptions,
                defaultCampaignID: hook.item?.id ?? campaignID,
                onStart: { configuration in
                    awaitingDemoSummary = true
                    activeDemoLaunchConfiguration = configuration
                }
            )
        }
        .fullScreenCover(item: $activeDemoLaunchConfiguration) { configuration in
            CampaignMapView(
                campaignId: configuration.campaign.id.uuidString,
                showPreSessionStartButton: false,
                demoLaunchConfiguration: configuration,
                onDismissFromMap: { activeDemoLaunchConfiguration = nil }
            )
        }
        .fullScreenCover(item: $demoSummaryItem) { item in
            ShareActivityGateView(
                data: item.data,
                sessionID: item.sessionID,
                campaignMapSnapshot: item.campaignMapSnapshot
            ) {
                demoSummaryItem = nil
                awaitingDemoSummary = false
                sessionManager.pendingSessionSummary = nil
                sessionManager.pendingSessionSummarySessionId = nil
            }
        }
        .sheet(isPresented: $isStatusSheetPresented) {
            if let addressId = selectedAddressId {
                StatusPickerSheet(
                    addressLabel: selectedAddressLabel,
                    currentStatus: addressStatuses[addressId] ?? .none,
                    onSelect: { status in
                        handleStatusSelected(addressId: addressId, newStatus: status)
                    }
                )
            }
        }
        .onAppear {
            print("📱 [DETAIL DEBUG] NewCampaignDetailView appeared for campaign ID: \(campaignID)")
            hook.load(id: campaignID, store: store)
            Task {
                await campaignDownloadService.refreshState(campaignId: campaignID.uuidString)
                await campaignDownloadService.prefetchIfNeeded(campaignId: campaignID.uuidString)
                await refreshCampaignDetailData()
            }
        }
        .onChange(of: hook.item) { _, campaign in
            if let campaign = campaign {
                print("📱 [DETAIL DEBUG] Campaign loaded: '\(campaign.name)'")
                print("📱 [DETAIL DEBUG] Campaign progress: \(Int(campaign.progress * 100))%")
                print("📱 [DETAIL DEBUG] Campaign addresses: \(campaign.addresses.count)")
                updateMapCenter(for: campaign)
                Task {
                    await campaignDownloadService.refreshState(campaignId: campaignID.uuidString)
                    await campaignDownloadService.prefetchIfNeeded(campaignId: campaignID.uuidString)
                    await refreshCampaignDetailData()
                }
            }
        }
        .onChange(of: sessionManager.pendingSessionSummary) { _, summary in
            guard awaitingDemoSummary, let summary else { return }
            let sessionID = sessionManager.pendingSessionSummarySessionId
            activeDemoLaunchConfiguration = nil
            demoSummaryItem = EndSessionSummaryItem(
                data: summary,
                sessionID: sessionID,
                campaignMapSnapshot: SessionManager.lastEndedSummaryMapSnapshot
            )
            sessionManager.pendingSessionSummary = nil
            sessionManager.pendingSessionSummarySessionId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionEnded)) { _ in
            Task { await refreshCampaignDetailData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leadSavedFromSession)) { _ in
            Task { await refreshCampaignDetailData() }
        }
        .navigationDestination(item: $supportFeedbackRoute) { route in
            SupportChatView(
                initialDraftMessage: route.draft,
                quickSuggestions: Self.campaignFeedbackQuickSuggestions,
                hiddenAttachmentPayload: route.hiddenAttachmentPayload
            )
        }
        .navigationDestination(item: $selectedLead) { lead in
            LeadDetailView(
                lead: lead,
                onConnectCRM: {},
                onLeadUpdated: { updated in
                    handleLeadUpdated(updated)
                }
            )
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(label):")
                .font(.label)
                .foregroundColor(.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.label)
                .fontWeight(.medium)
                .foregroundColor(.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var offlineAvailabilitySection: some View {
        let campaignIdString = campaignID.uuidString
        let downloadState = campaignDownloadService.state(for: campaignIdString)
        let readiness = campaignDownloadService.readiness(for: campaignIdString)
        let isOfflineAvailable = downloadState?.isAvailableOffline == true
        let isDownloading = downloadState?.status == "downloading"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                offlinePill(
                    title: "LOCAL DATA",
                    systemImage: isOfflineAvailable ? "checkmark.circle.fill" : "xmark.circle.fill",
                    background: isOfflineAvailable ? Color.green.opacity(0.14) : Color.red.opacity(0.16),
                    foreground: isOfflineAvailable ? Color.green : Color.red
                )
                Spacer(minLength: 0)
            }

            Text(localDataSummary(readiness: readiness, isReady: isOfflineAvailable))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.muted)

            if let downloadState, isDownloading {
                ProgressView(value: downloadState.progress)
                    .progressViewStyle(.linear)
            }

            Button(isOfflineAvailable ? "Refresh Local Data" : "Download Local Data") {
                Task {
                    await campaignDownloadService.makeAvailableOffline(campaignId: campaignIdString)
                    await campaignDownloadService.refreshState(campaignId: campaignIdString)
                }
            }
            .font(.label)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.accent)
            .cornerRadius(10)
            .buttonStyle(.plain)
            .disabled(isDownloading)
            .opacity(isDownloading ? 0.6 : 1)
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
    }

    private func localDataSummary(readiness: CampaignOfflineReadiness?, isReady: Bool) -> String {
        if let readiness {
            return readiness.summary
        }
        if isReady {
            return "This campaign is stored on your device for field use. Session activity still saves locally first and syncs in the background."
        }
        return "FLYR prepares campaign data automatically when you open or start a session. You can also refresh the local cache here."
    }

    private func offlinePill(title: String, systemImage: String, background: Color, foreground: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.label)
            .foregroundColor(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background)
            .clipShape(Capsule())
    }
    
    private func updateMapCenter(for campaign: CampaignV2) {
        // Use the first address in the list to center the map
        if let firstAddress = campaign.addresses.first {
            if let coord = firstAddress.coordinate {
                mapCenter = coord
                print("🗺️ [MAP] Centering map on first address: \(firstAddress.address) at \(coord)")
            } else {
                // If first address doesn't have coordinates, try to find any address with coordinates
                if let firstAddressWithCoords = campaign.addresses.first(where: { $0.coordinate != nil }) {
                    mapCenter = firstAddressWithCoords.coordinate!
                    print("🗺️ [MAP] First address has no coordinates, using first available: \(firstAddressWithCoords.coordinate!)")
                } else {
                    mapCenter = nil
                    print("🗺️ [MAP] No addresses with coordinates; waiting for campaign map data")
                }
            }
        } else {
            mapCenter = nil
            print("🗺️ [MAP] Campaign has no addresses; waiting for campaign map data")
        }
    }

    private func refreshCampaignDetailData() async {
        await refreshAddressStatuses()
        guard networkMonitor.isOnline else {
            await MainActor.run {
                leadsLoaded = true
                activitiesLoaded = true
            }
            return
        }
        await refreshCampaignLeads()
        await refreshCampaignActivities()
    }

    private func refreshAddressStatuses() async {
        do {
            let statusRows = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignID)
            let dict = Dictionary(uniqueKeysWithValues: statusRows.map { ($0.key.uuidString, $0.value.status) })
            await MainActor.run {
                addressStatuses = dict
            }
        } catch {
            print("⚠️ [DETAIL] Failed to fetch address statuses: \(error)")
        }
    }

    private func refreshCampaignLeads() async {
        guard networkMonitor.isOnline else {
            await MainActor.run {
                leadsLoaded = true
            }
            return
        }

        guard let userId = AuthManager.shared.user?.id else {
            await MainActor.run {
                campaignLeads = []
                campaignLeadsCount = 0
                leadsLoaded = true
            }
            return
        }

        do {
            let leads = try await FieldLeadsService.shared.fetchLeads(
                userId: userId,
                workspaceId: WorkspaceContext.shared.workspaceId,
                campaignId: campaignID
            )
            await MainActor.run {
                campaignLeads = leads
                campaignLeadsCount = leads.count
                leadsLoaded = true
            }
        } catch {
            await MainActor.run {
                leadsLoaded = true
            }
        }
    }

    private func refreshCampaignActivities() async {
        let cachedSessions = await SessionRepository.shared.fetchSessionsForCampaign(
            campaignId: campaignID,
            limit: 500
        )

        guard networkMonitor.isOnline else {
            await MainActor.run {
                if !cachedSessions.isEmpty {
                    campaignActivities = cachedSessions
                    activityCount = cachedSessions.count
                }
                activitiesLoaded = true
            }
            return
        }

        let userId = AuthManager.shared.user?.id
        let workspaceId = WorkspaceContext.shared.workspaceId

        guard workspaceId != nil || userId != nil else {
            await MainActor.run {
                if !cachedSessions.isEmpty {
                    campaignActivities = cachedSessions
                    activityCount = cachedSessions.count
                } else {
                    campaignActivities = []
                    activityCount = 0
                }
                activitiesLoaded = true
            }
            return
        }

        do {
            let sessions = try await SessionsAPI.shared.fetchSessionsForCampaign(
                campaignId: campaignID,
                userId: userId,
                workspaceId: workspaceId,
                limit: 500
            )
            await MainActor.run {
                campaignActivities = sessions
                activityCount = sessions.count
                activitiesLoaded = true
            }
        } catch {
            await MainActor.run {
                if !cachedSessions.isEmpty {
                    campaignActivities = cachedSessions
                    activityCount = cachedSessions.count
                }
                activitiesLoaded = true
            }
        }
    }
    
    // MARK: - Status Picker Handlers
    
    private func handleAddressTapped(addressId: String) {
        if let address = hook.item?.addresses.first(where: { $0.id.uuidString == addressId }) {
            selectedAddressId = addressId
            selectedAddressLabel = address.address
            isStatusSheetPresented = true
            print("📋 [STATUS] Address tapped: \(address.address) (ID: \(addressId))")
        } else {
            print("⚠️ [STATUS] Address not found: \(addressId)")
        }
    }
    
    private func handleStatusSelected(addressId: String, newStatus: AddressStatus) {
        guard let addressUUID = UUID(uuidString: addressId) else {
            print("❌ [STATUS] Invalid address ID: \(addressId)")
            return
        }
        
        Task {
            do {
                try await VisitsAPI.shared.updateStatus(
                    addressId: addressUUID,
                    campaignId: campaignID,
                    status: newStatus,
                    notes: nil
                )
                await MainActor.run {
                    addressStatuses[addressId] = newStatus
                }
                print("✅ [STATUS] Status updated: \(addressId) -> \(newStatus.rawValue)")
            } catch {
                print("❌ [STATUS] Error updating status: \(error)")
            }
        }
    }

    private func handleLeadUpdated(_ updatedLead: FieldLead) {
        if let index = campaignLeads.firstIndex(where: { $0.id == updatedLead.id }) {
            campaignLeads[index] = updatedLead
        }
        selectedLead = updatedLead
    }

    private func effectiveShareCardData(selectedSession: SessionRecord?) -> SessionSummaryData {
        if let selectedSession, let presentation {
            return presentation.shareCardData(for: selectedSession)
        }
        if let presentation {
            return presentation.defaultShareCardData
        }
        return placeholderShareCardData
    }
    
    // MARK: - Analytics Helpers
    
    private func generalAnalyticsStats(sessions: [SessionRecord] = []) -> [StatPill] {
        let totalDoors = sessions.reduce(0) { $0 + $1.doorsCount }
        let totalSeconds = sessions.reduce(0.0) { $0 + $1.durationSeconds }
        let totalDistanceMeters = sessions.reduce(0.0) { $0 + max(0, $1.distance_meters ?? 0) }
        let totalConversations = sessions.reduce(0) { $0 + max(0, $1.conversations ?? 0) }
        let doorsPerHour = totalSeconds > 0 ? Double(totalDoors) / (totalSeconds / 3600.0) : 0.0
        let conversationsPerHour = totalSeconds > 0 ? Double(totalConversations) / (totalSeconds / 3600.0) : 0.0
        let timeString = formatAnalyticsDuration(totalSeconds)
        let distanceKm = totalDistanceMeters / 1000.0
        let completionsPerKm = distanceKm > 0 ? Double(totalDoors) / distanceKm : 0.0

        return [
            StatPill(
                value: "\(totalDoors)",
                label: "Doors"
            ),
            StatPill(
                value: String(format: "%.1f", doorsPerHour),
                label: "Doors/Hour"
            ),
            StatPill(
                value: String(format: "%.1f", conversationsPerHour),
                label: "Convos/Hour"
            ),
            StatPill(
                value: String(format: "%.1f", completionsPerKm),
                label: "Comp/KM"
            ),
            StatPill(
                value: timeString,
                label: "Time"
            ),
            StatPill(
                value: String(format: "%.1f", distanceKm),
                label: "KM Traveled"
            )
        ]
    }
    
    private func doorknockAnalyticsStats(sessions: [SessionRecord], leadsCount: Int) -> [StatPill] {
        let conversations = sessions.reduce(0) { $0 + max(0, $1.conversations ?? 0) }
        let appointments = sessions.reduce(0) { $0 + $1.appointmentsCount }
        let convoToLeadRate = conversations > 0
            ? Double(leadsCount) / Double(conversations) * 100.0
            : 0.0
        let appointmentsPerConversation = conversations > 0
            ? Double(appointments) / Double(conversations)
            : 0.0
        
        return [
            StatPill(
                value: "\(conversations)",
                label: "Conversations"
            ),
            StatPill(
                value: "\(appointments)",
                label: "Appointments"
            ),
            StatPill(
                value: String(format: "%.2f", appointmentsPerConversation),
                label: "Appts/Convo"
            ),
            StatPill(
                value: "\(leadsCount)",
                label: "Leads"
            ),
            StatPill(
                value: String(format: "%.1f%%", convoToLeadRate),
                label: "Convo → Lead"
            )
        ]
    }

    private func formatAnalyticsDuration(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, Int(seconds.rounded()))
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    // MARK: - Campaign feedback diagnostics (Support)

    private static func buildCampaignFeedbackDiagnosticsMessage(
        campaign: CampaignV2,
        leadsCount: Int,
        activitySessionsCount: Int
    ) async -> CampaignSupportFeedbackRoute {
        let territoryRing = await CampaignsAPI.shared.fetchTerritoryBoundary(campaignId: campaign.id)
        var coords: [CLLocationCoordinate2D] = []
        for address in campaign.addresses {
            if let c = address.coordinate {
                coords.append(c)
            }
        }
        if let ring = territoryRing {
            coords.append(contentsOf: ring)
        }

        let bboxLine: String
        if coords.isEmpty {
            bboxLine = "bbox: (no coordinates from addresses or territory)"
        } else {
            let lats = coords.map(\.latitude)
            let lons = coords.map(\.longitude)
            let minLat = lats.min() ?? 0
            let maxLat = lats.max() ?? 0
            let minLon = lons.min() ?? 0
            let maxLon = lons.max() ?? 0
            bboxLine = String(
                format: "bbox: minLat=%.6f, maxLat=%.6f, minLon=%.6f, maxLon=%.6f",
                minLat, maxLat, minLon, maxLon
            )
        }

        let polygonCount = territoryRing?.count ?? 0
        let polygonPreview: String
        if let ring = territoryRing, !ring.isEmpty {
            let sample = ring.prefix(3).map { p in
                String(format: "[%.6f,%.6f]", p.longitude, p.latitude)
            }
            polygonPreview = sample.joined(separator: ", ")
        } else {
            polygonPreview = "(none)"
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let workspaceId = await MainActor.run { WorkspaceContext.shared.workspaceId }
        let workspaceLine: String
        if let wid = workspaceId {
            workspaceLine = "workspaceId: \(wid.uuidString)"
        } else {
            workspaceLine = "workspaceId: (none)"
        }

        let seedLine: String
        if let seed = campaign.seedQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !seed.isEmpty {
            seedLine = "seedQuery: \(seed)"
        } else {
            seedLine = "seedQuery: (none)"
        }

        let visibleDraft = """
        I found a campaign data issue.
        Diagnostics are attached for support review.

        What happened?
        """

        let attachmentPayload = """
        --- Campaign ---
        \(workspaceLine)
        campaignId: \(campaign.id.uuidString)
        name: \(campaign.name)
        type: \(campaign.type.dbValue)
        addressSource: \(campaign.addressSource.rawValue)
        createdAt: \(iso.string(from: campaign.createdAt))
        status: \(campaign.status.rawValue)
        progressPct: \(campaign.progressPct)

        --- Counts ---
        addressesCount: \(campaign.addresses.count)
        leadsCount: \(leadsCount)
        activitySessionsCount: \(activitySessionsCount)
        scans: \(campaign.scans)
        conversions: \(campaign.conversions)
        totalFlyers: \(campaign.totalFlyers)

        --- D (diagnostics) ---
        \(seedLine)
        \(bboxLine)
        territory_polygon_point_count: \(polygonCount)
        territory_polygon_preview_lng_lat: \(polygonPreview)
        """

        return CampaignSupportFeedbackRoute(
            draft: visibleDraft,
            hiddenAttachmentPayload: attachmentPayload
        )
    }

    // Pro Mode: No need for building outlines rendering - using static map API
}

private struct DemoCampaignFullStatsCard: View {
    let presentation: CampaignDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just Listed Mearns")
                        .font(.label)
                        .fontWeight(.semibold)
                        .foregroundColor(.text)
                    Text("Demo Performance Snapshot")
                        .font(.flyrCaption)
                        .foregroundColor(.muted)
                }
                Spacer()
                Text("\(presentation.progressPercent)%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.accent)
            }

            ProgressBar(value: presentation.progressValue)

            StatGrid(
                stats: [
                    StatPill(value: "\(presentation.totalDoors)", label: "Total Doors"),
                    StatPill(value: "\(presentation.doorsHit)", label: "Doors Hit", hasAccentHighlight: true),
                    StatPill(value: "\(presentation.conversations)", label: "Conversations"),
                    StatPill(value: "\(presentation.leads)", label: "Leads"),
                    StatPill(value: "\(presentation.appointments)", label: "Appointments"),
                    StatPill(value: "\(presentation.sessionsCount)", label: "Sessions")
                ],
                columns: 2
            )

            Rectangle()
                .fill(Color.muted.opacity(0.2))
                .frame(height: 1)

            StatGrid(
                stats: [
                    StatPill(value: String(format: "%.1f%%", presentation.conversationPerDoorRate), label: "Convo / Door"),
                    StatPill(value: String(format: "%.1f%%", presentation.leadPerConversationRate), label: "Lead / Convo"),
                    StatPill(value: presentation.timeLabel, label: "Time"),
                    StatPill(value: String(format: "%.1f km", presentation.distanceKm), label: "Distance")
                ],
                columns: 2
            )
        }
        .padding(16)
        .background(Color.bgTertiary)
        .cornerRadius(12)
    }
}

struct CampaignDetailPresentation {
    let progressValue: Double
    let analyticsStats: [StatPill]
    let defaultShareCardData: SessionSummaryData
    let syntheticLeads: [FieldLead]
    let hasAnalytics: Bool
    let isJustListedMearnsDemo: Bool
    let totalDoors: Int
    let doorsHit: Int
    let conversations: Int
    let leads: Int
    let appointments: Int
    let sessionsCount: Int
    let progressPercent: Int
    let conversationPerDoorRate: Double
    let leadPerConversationRate: Double
    let timeLabel: String
    let distanceKm: Double

    private let campaign: CampaignV2
    private let sessions: [SessionRecord]
    private let routePoints: [CLLocationCoordinate2D]

    init(
        campaign: CampaignV2,
        sessions: [SessionRecord],
        fieldLeads: [FieldLead],
        addressStatuses: [String: AddressStatus]
    ) {
        self.campaign = campaign
        self.sessions = sessions

        let isMearnsDemoCampaign = Self.isMearnsDemoCampaign(campaign.name)
        isJustListedMearnsDemo = Self.isJustListedMearnsCampaign(campaign.name)
        let totalAddresses = max(campaign.addresses.count, campaign.totalFlyers)
        let realDoors = sessions.reduce(0) { $0 + $1.doorsCount }
        let realSeconds = sessions.reduce(0.0) { $0 + $1.durationSeconds }
        let realDistanceMeters = sessions.reduce(0.0) { $0 + max(0, $1.distance_meters ?? 0) }
        let realConversations = sessions.reduce(0) { $0 + max(0, $1.conversations ?? 0) }
        let realAppointments = sessions.reduce(0) { $0 + $1.appointmentsCount }

        let statusCounts = Dictionary(grouping: addressStatuses.values, by: { $0 }).mapValues(\.count)
        let visitedStatusCount = Self.count(for: Self.visitedStatuses, in: statusCounts)
        let conversationStatusCount = Self.count(for: Self.conversationStatuses, in: statusCounts)
        let leadStatusCount = Self.count(for: Self.leadStatuses, in: statusCounts)
        let appointmentStatusCount = statusCounts[.appointment] ?? 0

        let leadCount = fieldLeads.count
        let clampedSessionDoors = min(totalAddresses, max(0, realDoors))
        var derivedDoors = max(clampedSessionDoors, visitedStatusCount)
        var derivedConversations = max(realConversations, conversationStatusCount)
        if derivedDoors > 0 {
            derivedConversations = min(derivedConversations, derivedDoors)
        }
        let derivedAppointments = min(
            derivedConversations,
            max(realAppointments, appointmentStatusCount)
        )
        let derivedLeadCount = max(leadCount, leadStatusCount, derivedAppointments)

        if isMearnsDemoCampaign {
            let demoDoorsFloor = max(derivedDoors, max(0, totalAddresses - 20))
            derivedDoors = min(totalAddresses, demoDoorsFloor)
            let demoConversationFloor = max(derivedConversations, max(12, Int((Double(derivedDoors) * 0.1).rounded())))
            derivedConversations = min(derivedDoors, demoConversationFloor)
        }
        if isJustListedMearnsDemo {
            let targetDoors = totalAddresses > 0 ? min(totalAddresses, 322) : 322
            derivedDoors = targetDoors
            derivedConversations = min(targetDoors, 74)
        }

        let fallbackCoordinates = Self.routePoints(
            from: campaign.addresses,
            using: addressStatuses
        )
        let realRoutePoints = sessions.flatMap(\.pathCoordinates)
        routePoints = realRoutePoints.count >= 2 ? realRoutePoints : fallbackCoordinates

        var fallbackDistanceMeters = max(Self.pathDistance(for: routePoints) * 1.12, Double(max(derivedDoors, 1)) * 14.0)
        if isMearnsDemoCampaign {
            fallbackDistanceMeters = max(fallbackDistanceMeters, 4_200)
        }
        let totalDistanceMeters: Double
        if isJustListedMearnsDemo {
            totalDistanceMeters = 4_800
        } else {
            totalDistanceMeters = realDistanceMeters > 0 ? realDistanceMeters : fallbackDistanceMeters
        }

        let perDoorSeconds = campaign.type == .doorKnock ? 55.0 : 35.0
        var fallbackSeconds = (Double(derivedDoors) * perDoorSeconds)
            + (Double(derivedConversations) * 110.0)
            + (Double(derivedAppointments) * 240.0)
        if isMearnsDemoCampaign {
            fallbackSeconds = max(fallbackSeconds, 4 * 3600)
        }
        let totalSeconds: Double
        if isJustListedMearnsDemo {
            totalSeconds = 6_180 // 1h 43m
        } else {
            totalSeconds = realSeconds > 0 ? realSeconds : fallbackSeconds
        }

        let derivedProgress = totalAddresses > 0 ? min(1.0, Double(derivedDoors) / Double(totalAddresses)) : 0
        let resolvedProgressValue = derivedProgress > 0 ? derivedProgress : campaign.progress
        let resolvedProgressPercent = Int((resolvedProgressValue * 100).rounded())
        progressValue = resolvedProgressValue
        progressPercent = resolvedProgressPercent

        let normalizedDistanceKm = totalDistanceMeters / 1000.0
        let convoPerDoor = derivedDoors > 0
            ? Double(derivedConversations) / Double(derivedDoors) * 100.0
            : 0
        let leadPerConversation = derivedConversations > 0
            ? Double(derivedLeadCount) / Double(derivedConversations) * 100.0
            : 0
        timeLabel = Self.formatDuration(totalSeconds)
        distanceKm = normalizedDistanceKm
        totalDoors = totalAddresses
        doorsHit = derivedDoors
        conversations = derivedConversations
        leads = derivedLeadCount
        appointments = derivedAppointments
        sessionsCount = sessions.count
        conversationPerDoorRate = convoPerDoor
        leadPerConversationRate = leadPerConversation

        analyticsStats = [
            StatPill(value: "\(totalAddresses)", label: "Total Doors"),
            StatPill(value: "\(derivedDoors)", label: "Doors Hit"),
            StatPill(value: "\(derivedConversations)", label: "Convo's"),
            StatPill(value: "\(derivedLeadCount)", label: "Leads"),
            StatPill(value: String(format: "%.1f%%", convoPerDoor), label: "Convo / Door"),
            StatPill(value: String(format: "%.1f%%", leadPerConversation), label: "Lead / Convo"),
            StatPill(value: timeLabel, label: "Time"),
            StatPill(value: String(format: "%.1f", normalizedDistanceKm), label: "Km")
        ]

        defaultShareCardData = SessionSummaryData(
            distance: totalDistanceMeters,
            time: totalSeconds,
            goalType: campaign.type == .doorKnock ? .knocks : .flyers,
            goalAmount: totalAddresses,
            pathCoordinates: routePoints,
            renderedPathSegments: nil,
            completedCount: derivedDoors,
            conversationsCount: derivedConversations,
            startTime: sessions.last?.start_time ?? campaign.createdAt
        )

        syntheticLeads = fieldLeads.isEmpty
            ? Self.makeSyntheticLeads(
                campaign: campaign,
                addressStatuses: addressStatuses,
                desiredCount: derivedLeadCount
            )
            : []

        hasAnalytics = totalAddresses > 0 || derivedDoors > 0 || totalDistanceMeters > 0 || totalSeconds > 0 || derivedConversations > 0
    }

    func shareCardData(for session: SessionRecord) -> SessionSummaryData {
        if isJustListedMearnsDemo {
            // Keep demo share card stable even when individual session data exists.
            return defaultShareCardData
        }
        let summary = session.toSummaryData()
        if Self.isMeaningful(summary) {
            return summary
        }
        return defaultShareCardData
    }

    private static let visitedStatuses: Set<AddressStatus> = [
        .noAnswer, .delivered, .talked, .appointment, .doNotKnock, .futureSeller, .hotLead
    ]

    private static let conversationStatuses: Set<AddressStatus> = [
        .talked, .appointment, .futureSeller, .hotLead
    ]

    private static let leadStatuses: Set<AddressStatus> = [
        .futureSeller, .appointment, .hotLead
    ]

    private static func count(for statuses: Set<AddressStatus>, in counts: [AddressStatus: Int]) -> Int {
        statuses.reduce(0) { partialResult, status in
            partialResult + (counts[status] ?? 0)
        }
    }

    private static func isMeaningful(_ summary: SessionSummaryData) -> Bool {
        summary.distance >= 150
            || summary.time >= 5 * 60
            || summary.doorsCount >= 8
            || summary.conversations >= 2
            || summary.pathCoordinates.count >= 2
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(0, Int(seconds.rounded()))
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private static func routePoints(
        from addresses: [CampaignAddress],
        using addressStatuses: [String: AddressStatus]
    ) -> [CLLocationCoordinate2D] {
        let visitedAddressIDs: Set<UUID> = Set(
            addressStatuses.compactMap { key, status in
                guard visitedStatuses.contains(status), let uuid = UUID(uuidString: key) else { return nil }
                return uuid
            }
        )

        let prioritized = addresses.filter { visitedAddressIDs.contains($0.id) && $0.coordinate != nil }
        let fallback = addresses.filter { $0.coordinate != nil }
        let source = prioritized.count >= 4 ? prioritized : fallback
        let coordinates = source.compactMap { $0.coordinate }
        guard coordinates.count >= 2 else { return coordinates }

        let sorted = coordinates.sorted {
            if abs($0.latitude - $1.latitude) < 0.00005 {
                return $0.longitude < $1.longitude
            }
            return $0.latitude < $1.latitude
        }

        let chunkSize = max(3, Int(Double(sorted.count).squareRoot().rounded()))
        var route: [CLLocationCoordinate2D] = []
        var row = 0
        for start in stride(from: 0, to: sorted.count, by: chunkSize) {
            let end = min(start + chunkSize, sorted.count)
            let slice = Array(sorted[start..<end])
            route.append(contentsOf: row.isMultiple(of: 2) ? slice : slice.reversed())
            row += 1
        }
        return route
    }

    private static func pathDistance(for coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        return zip(coordinates, coordinates.dropFirst()).reduce(0) { partialResult, pair in
            let start = CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
            let end = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return partialResult + start.distance(from: end)
        }
    }

    private static func makeSyntheticLeads(
        campaign: CampaignV2,
        addressStatuses: [String: AddressStatus],
        desiredCount: Int
    ) -> [FieldLead] {
        guard desiredCount > 0 else { return [] }

        let preferredAddresses = campaign.addresses.filter { address in
            guard let status = addressStatuses[address.id.uuidString] else { return false }
            return leadStatuses.contains(status)
        }
        let sourceAddresses = (preferredAddresses.isEmpty ? campaign.addresses : preferredAddresses).prefix(max(3, desiredCount))
        let names = [
            "Sarah Thompson",
            "Chris Bennett",
            "Maya Singh",
            "Ethan Parker",
            "Olivia Chen"
        ]
        let notes = [
            "Asked for a market update next week.",
            "Interested in recent solds nearby.",
            "Wants a follow-up call about timing.",
            "Mentioned they may list this summer.",
            "Requested a home value estimate."
        ]

        return Array(sourceAddresses.enumerated()).map { index, address in
            FieldLead(
                userId: campaign.id,
                address: address.address,
                name: names[index % names.count],
                status: .interested,
                notes: notes[index % notes.count],
                campaignId: campaign.id,
                createdAt: Date().addingTimeInterval(Double(-(index + 1) * 3600)),
                updatedAt: Date().addingTimeInterval(Double(-(index + 1) * 1800))
            )
        }
    }

    private static func isMearnsDemoCampaign(_ campaignName: String) -> Bool {
        let normalized = campaignName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("mearns")
    }

    private static func isJustListedMearnsCampaign(_ campaignName: String) -> Bool {
        let normalized = campaignName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("mearns") && normalized.contains("just listed")
    }
}

// MARK: - Campaign Activity Row

private struct CampaignActivityRow: View {
    let session: SessionRecord
    let index: Int

    private static let shortDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var countLabel: String {
        return "\(session.doorsCount) doors"
    }

    private var distanceLabel: String? {
        guard let m = session.distance_meters, m > 0 else { return nil }
        return String(format: "%.1f km", m / 1000.0)
    }

    private var summaryText: String {
        var parts = [Self.shortDateTimeFormatter.string(from: session.start_time), countLabel]
        if let d = distanceLabel { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack {
            Text("\(index).")
                .font(.flyrCaption)
                .foregroundColor(.muted)
                .frame(width: 20, alignment: .leading)
            Text(summaryText)
                .font(.body)
                .foregroundColor(.text)
            Spacer()
        }
    }
}

// MARK: - Full Addresses Sheet

private struct FullAddressesSheet: View {
    let addresses: [CampaignAddress]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(addresses.enumerated()), id: \.element.id) { index, address in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.flyrCaption)
                            .foregroundColor(.muted)
                            .frame(width: 24, alignment: .leading)
                        Text(address.address)
                            .font(.body)
                            .foregroundColor(.text)
                        Spacer(minLength: 0)
                    }
                    .listRowBackground(Color.bgTertiary)
                    .listRowSeparatorTint(.muted.opacity(0.3))
                }
            }
            .listStyle(.plain)
            .background(Color.bg)
            .navigationTitle("\(addresses.count) Addresses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.light()
                        dismiss()
                    }
                    .font(.label)
                    .foregroundColor(.accent)
                }
            }
        }
    }
}

// MARK: - Fullscreen Map View

struct FullscreenMapView: View {
    let campaignID: UUID
    let namespace: Namespace.ID
    /// When true, this view is the geometry source for the matched effect (inline map uses isSource: false when fullscreen).
    let isSource: Bool
    let onClose: () -> Void
    @ObservedObject private var sessionManager = SessionManager.shared

    var body: some View {
        CampaignMapView(
            campaignId: campaignID.uuidString,
            onDismissFromMap: sessionManager.sessionId == nil
                ? {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onClose()
                }
                : nil
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .matchedGeometryEffect(id: "map", in: namespace, isSource: isSource)
        .onReceive(NotificationCenter.default.publisher(for: .sessionEnded)) { _ in
            // If a session ends while this fullscreen map is presented, dismiss it so
            // MainTabView can present the global Share Activity full-screen cover.
            onClose()
        }
    }
}

// MARK: - Preview

#Preview {
    let store = CampaignV2Store.shared
    let mockCampaign = CampaignV2.mockCampaigns[0]
    store.append(mockCampaign)
    
    return NavigationStack {
        NewCampaignDetailView(campaignID: mockCampaign.id, store: store)
    }
}
