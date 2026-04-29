import SwiftUI

private struct SessionRouteAssignmentDetailSheetItem: Identifiable {
    let id: UUID
}

struct SessionStartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @EnvironmentObject private var uiState: AppUIState
    @StateObject private var authManager = AuthManager.shared
    @ObservedObject private var workspaceContext = WorkspaceContext.shared

    /// When false, Cancel button is hidden (e.g. when used as Record tab root).
    var showCancelButton: Bool = true

    /// When set (e.g. from campaigns list play button), open this campaign map on appear.
    var preselectedCampaign: CampaignV2?

    // Data loading
    @State private var campaigns: [CampaignV2] = []
    @State private var farms: [Farm] = []
    @State private var routeAssignments: [RouteAssignmentSummary] = []
    @State private var isLoadingData: Bool = false
    @State private var isFetchingData: Bool = false
    @State private var lastFetchTime: Date?

    /// Show at most this many items before "More" menu
    private let maxVisibleItems = 3

    /// Campaign chosen to open directly in map.
    @State private var mapCampaign: CampaignV2?
    @State private var showCampaignMap: Bool = false
    @State private var showQuickCampaign: Bool = false
    @State private var showNetworkingSession: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showJoinSessionCodeSheet: Bool = false

    @State private var routeDetailAssignmentSheetItem: SessionRouteAssignmentDetailSheetItem?
    @State private var openingRouteAssignmentId: UUID?
    @State private var routeOpenErrorMessage: String?
    @State private var plannerFarm: Farm?

    var body: some View {
        NavigationStack {
            sessionStartContent
        }
    }

    private var sessionStartContent: some View {
        scrollContent
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { sessionToolbar }
            .task(id: "sessionStartData") {
                await loadData()
                if let pre = preselectedCampaign {
                    let campaign = campaigns.first { $0.id == pre.id } ?? pre
                    openCampaign(campaign)
                }
            }
            .navigationDestination(isPresented: $showCampaignMap) {
                campaignMapDestination
            }
            .navigationDestination(isPresented: $showQuickCampaign) {
                QuickStartMapView()
            }
            .navigationDestination(isPresented: $showNetworkingSession) {
                NetworkingSessionView()
            }
            .navigationDestination(item: $plannerFarm) { farm in
                FarmTouchPlannerView(
                    farmId: farm.id,
                    onStartSession: { context in
                        uiState.beginPlannedFarmExecution(context)
                    }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showJoinSessionCodeSheet) {
                JoinSessionCodeSheet()
                    .environmentObject(uiState)
            }
            .sheet(item: $routeDetailAssignmentSheetItem) { item in
                NavigationStack {
                    RouteAssignmentDetailView(assignmentId: item.id)
                }
            }
            .alert("Couldn’t open route", isPresented: Binding(
                get: { routeOpenErrorMessage != nil },
                set: { if !$0 { routeOpenErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    routeOpenErrorMessage = nil
                }
            } message: {
                Text(routeOpenErrorMessage ?? "")
            }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sessionActionButtons
                campaignList
                if !isLoadingData {
                    farmsList
                }
                if !isLoadingData {
                    routesList
                }
                Spacer()
            }
            .padding(.vertical)
        }
    }

    @ToolbarContentBuilder
    private var sessionToolbar: some ToolbarContent {
        if showCancelButton {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    HapticManager.light()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var campaignMapDestination: some View {
        if let campaign = mapCampaign {
            CampaignMapView(campaignId: campaign.id.uuidString)
        }
    }

    // MARK: - Campaign List

    private var sessionActionButtons: some View {
        HStack(spacing: 12) {
            quickActionButton(
                title: "Quick Start",
                systemImage: "bolt.fill",
                backgroundColor: .yellow
            ) {
                HapticManager.light()
                if entitlementsService.canUsePro {
                    showQuickCampaign = true
                } else {
                    showPaywall = true
                }
            }

            quickActionButton(
                title: "Networking",
                systemImage: "person.2.circle",
                backgroundColor: .info
            ) {
                HapticManager.light()
                showNetworkingSession = true
            }

            quickActionButton(
                title: "Join Session",
                systemImage: "person.2.fill",
                backgroundColor: .success
            ) {
                HapticManager.light()
                showJoinSessionCodeSheet = true
            }
        }
        .padding(.horizontal)
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        backgroundColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.black)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
    }

    private var campaignList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAMPAIGNS")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)

            if isLoadingData {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if campaigns.isEmpty {
                Text("No campaigns available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let visible = Array(campaigns.prefix(maxVisibleItems))
                let remaining = Array(campaigns.dropFirst(maxVisibleItems))

                ForEach(visible) { campaign in
                    Button {
                        openCampaign(campaign)
                    } label: {
                        campaignRow(campaign)
                    }
                    .buttonStyle(.plain)
                }

                if !remaining.isEmpty {
                    Menu {
                        ForEach(remaining) { campaign in
                            Button(campaign.name) {
                                openCampaign(campaign)
                            }
                        }
                    } label: {
                        HStack {
                            Text("More (\(remaining.count) more)")
                                .font(.flyrHeadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.flyrCaption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    /// Assignments suitable for starting or continuing work (matches Routes “Active” tab).
    private var routesForStartSession: [RouteAssignmentSummary] {
        routeAssignments.filter { $0.status.lowercased() != "completed" }
    }

    private var farmsForStartSession: [Farm] {
        farms
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var farmsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FARMS")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)

            if farmsForStartSession.isEmpty {
                Text("No active farms available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let visible = Array(farmsForStartSession.prefix(maxVisibleItems))
                let remaining = Array(farmsForStartSession.dropFirst(maxVisibleItems))

                ForEach(visible) { farm in
                    Button {
                        openFarm(farm)
                    } label: {
                        farmRow(farm)
                    }
                    .buttonStyle(.plain)
                }

                if !remaining.isEmpty {
                    Menu {
                        ForEach(remaining) { farm in
                            Button(farm.name) {
                                openFarm(farm)
                            }
                        }
                    } label: {
                        HStack {
                            Text("More (\(remaining.count) more)")
                                .font(.flyrHeadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.flyrCaption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private var routesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTES")
                .font(.flyrHeadline)
                .foregroundColor(.secondary)

            if routesForStartSession.isEmpty {
                Text("No routes assigned")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let visible = Array(routesForStartSession.prefix(maxVisibleItems))
                let remaining = Array(routesForStartSession.dropFirst(maxVisibleItems))

                ForEach(visible) { route in
                    Button {
                        Task { await openRoute(route) }
                    } label: {
                        routeRow(route)
                    }
                    .buttonStyle(.plain)
                    .disabled(openingRouteAssignmentId != nil)
                }

                if !remaining.isEmpty {
                    Menu {
                        ForEach(remaining) { route in
                            Button(route.name) {
                                Task { await openRoute(route) }
                            }
                        }
                    } label: {
                        HStack {
                            Text("More (\(remaining.count) more)")
                                .font(.flyrHeadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.flyrCaption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }

    private func routeRow(_ route: RouteAssignmentSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.flyrHeadline)

                HStack(spacing: 12) {
                    Label("\(route.totalStops) stops", systemImage: "mappin.and.ellipse")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)

                    if route.status.lowercased() != "assigned" {
                        Text(route.statusLabel)
                            .font(.flyrCaption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(routeStatusAccent(route.status).opacity(0.2))
                            .foregroundColor(routeStatusAccent(route.status))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            if openingRouteAssignmentId == route.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func campaignRow(_ campaign: CampaignV2) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(campaign.name)
                    .font(.flyrHeadline)

                HStack(spacing: 12) {
                    Label("\(campaign.totalFlyers)", systemImage: "house.fill")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)

                    if campaign.status != .draft {
                        Text(campaign.status.rawValue.capitalized)
                            .font(.flyrCaption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor(campaign.status).opacity(0.2))
                            .foregroundColor(statusColor(campaign.status))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.flyrCaption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func farmRow(_ farm: Farm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(farm.name)
                    .font(.flyrHeadline)

                HStack(spacing: 12) {
                    Label("\(farm.addressCount ?? 0)", systemImage: "house.fill")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)

                    Text("Active")
                        .font(.flyrCaption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.flyrCaption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Helpers

    private func openCampaign(_ campaign: CampaignV2) {
        HapticManager.light()
        mapCampaign = campaign
        showCampaignMap = true
    }

    private func openFarm(_ farm: Farm) {
        HapticManager.light()
        plannerFarm = farm
    }

    private func openRoute(_ route: RouteAssignmentSummary) async {
        HapticManager.light()
        openingRouteAssignmentId = route.id
        defer { openingRouteAssignmentId = nil }

        do {
            let detail = try await RouteAssignmentsAPI.shared.fetchAssignmentDetail(assignmentId: route.id)
            await openResolvedRoute(
                context: RouteWorkContext(detail: detail),
                campaignId: detail.campaignId,
                routeName: detail.displayPlanName,
                fallbackAssignmentId: route.id
            )
        } catch {
            let originalError = error
            do {
                let planDetail = try await RoutePlansAPI.shared.fetchRoutePlanDetail(routePlanId: route.routePlanId)
                await openResolvedRoute(
                    context: RouteWorkContext(assignment: route, planDetail: planDetail),
                    campaignId: planDetail.campaignId,
                    routeName: RouteAssignmentSummary.displayName(fromRoutePlanName: planDetail.name),
                    fallbackAssignmentId: route.id
                )
            } catch {
                await MainActor.run {
                    routeOpenErrorMessage = originalError.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func openResolvedRoute(
        context: RouteWorkContext?,
        campaignId: UUID?,
        routeName: String,
        fallbackAssignmentId: UUID
    ) {
        if let context {
            uiState.selectRoute(context)
            uiState.selectedTabIndex = 1
            dismiss()
            return
        }

        if let campaignId {
            uiState.selectCampaign(id: campaignId, name: routeName)
            uiState.selectedTabIndex = 1
            dismiss()
            return
        }

        routeDetailAssignmentSheetItem = SessionRouteAssignmentDetailSheetItem(id: fallbackAssignmentId)
    }

    private func routeStatusAccent(_ status: String) -> Color {
        switch status.lowercased() {
        case "in_progress", "in progress":
            return .orange
        case "cancelled", "declined":
            return .gray
        default:
            return .blue
        }
    }

    private func statusColor(_ status: CampaignStatus) -> Color {
        switch status {
        case .draft: return .blue
        case .active: return .green
        case .completed: return .gray
        case .paused: return .flyrPrimary
        case .archived: return .gray
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard !isFetchingData else { return }
        if let last = lastFetchTime, Date().timeIntervalSince(last) < 3 { return }
        isFetchingData = true
        lastFetchTime = Date()
        isLoadingData = true
        defer {
            isFetchingData = false
            isLoadingData = false
        }

        async let campaignsDone: Void = loadCampaigns()
        async let farmsDone: Void = loadFarms()
        async let routesDone: Void = loadRoutes()
        _ = await (campaignsDone, farmsDone, routesDone)
    }

    private func loadCampaigns() async {
        do {
            campaigns = try await CampaignsAPI.shared.fetchCampaignsV2(workspaceId: WorkspaceContext.shared.workspaceId)
            print("✅ Loaded \(campaigns.count) campaigns")
        } catch {
            // CRITICAL: Don't treat cancellation as failure - prevents infinite retry loop
            if (error as NSError).code == NSURLErrorCancelled {
                print("Fetch cancelled (view disposed) - not retrying")
                return
            }
            print("❌ Failed to load campaigns: \(error)")
            campaigns = []
        }
    }

    private func loadRoutes() async {
        guard let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: WorkspaceContext.shared.workspaceId) else {
            routeAssignments = []
            return
        }

        do {
            let result = try await RouteAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceId)
            routeAssignments = result.assignments
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            do {
                routeAssignments = try await RoutePlansAPI.shared.fetchMyAssignedRoutes(workspaceId: workspaceId)
            } catch {
                routeAssignments = []
            }
        }
    }

    private func loadFarms() async {
        guard let userId = await MainActor.run(body: { authManager.user?.id }) else {
            farms = []
            return
        }

        do {
            farms = try await FarmService.shared.fetchFarms(userID: userId)
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                return
            }
            print("❌ Failed to load farms: \(error)")
            farms = []
        }
    }

}

private struct JoinSessionCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiState: AppUIState

    @FocusState private var isCodeFieldFocused: Bool
    @State private var sessionCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    private let requiredCodeLength = 6

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Join a teammate's live session", systemImage: "person.2.fill")
                        .font(.flyrHeadline)
                        .foregroundStyle(.primary)
                    Text("Enter the \(requiredCodeLength)-character team code. This joins the session only and does not merge workspaces.")
                        .font(.flyrSubheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("ABC123", text: sessionCodeBinding)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(6)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 18)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.bgSecondary)
                    )
                    .focused($isCodeFieldFocused)
                    .submitLabel(.go)
                    .onSubmit {
                        Task { await joinSession() }
                    }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.error)
                }

                Button {
                    Task { await joinSession() }
                } label: {
                    HStack {
                        if isJoining {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "person.2.fill")
                        }

                        Text(isJoining ? "Joining..." : "Join Session")
                            .font(.flyrHeadline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canJoin ? Color.success : Color.gray.opacity(0.35))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canJoin || isJoining)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Join Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isCodeFieldFocused = true
        }
    }

    private var canJoin: Bool {
        sanitizedCode.count == requiredCodeLength
    }

    private var sanitizedCode: String {
        sessionCode.uppercased().replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    }

    private var sessionCodeBinding: Binding<String> {
        Binding(
            get: { sessionCode },
            set: { newValue in
                sessionCode = String(
                    newValue
                        .uppercased()
                        .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
                        .prefix(requiredCodeLength)
                )
                errorMessage = nil
            }
        )
    }

    private func joinSession() async {
        guard !isJoining else { return }
        guard canJoin else {
            errorMessage = "Enter the \(requiredCodeLength)-character code from your teammate."
            return
        }

        isJoining = true
        errorMessage = nil

        defer { isJoining = false }

        do {
            let response = try await InviteService.shared.joinLiveSession(code: sanitizedCode)
            guard let campaignIdString = response.campaignId,
                  let campaignId = UUID(uuidString: campaignIdString),
                  let sessionIdString = response.sessionId,
                  let sessionId = UUID(uuidString: sessionIdString) else {
                errorMessage = "The session opened, but the response was missing campaign details."
                return
            }

            HapticManager.success()
            uiState.beginLiveInviteHandoff(
                campaignId: campaignId,
                name: response.campaignTitle,
                sourceSessionId: sessionId
            )
            dismiss()
        } catch {
            HapticManager.error()
            errorMessage = error.localizedDescription
        }
    }
}
