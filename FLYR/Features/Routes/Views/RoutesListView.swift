import SwiftUI

private enum AssignmentTab: String, CaseIterable {
    case active = "Active"
    case completed = "Completed"
}

private struct RouteAssignmentDetailSheetItem: Identifiable {
    let id: UUID
}

/// Route assignments from `GET /api/routes/assignments` with web-style search and Active / Completed tabs.
struct RoutesListView: View {
    @ObservedObject private var workspace = WorkspaceContext.shared
    @EnvironmentObject private var uiState: AppUIState

    @State private var allAssignments: [RouteAssignmentSummary] = []
    @State private var searchText = ""
    @State private var selectedTab: AssignmentTab = .active
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var routeDetailAssignmentSheetItem: RouteAssignmentDetailSheetItem?
    @State private var openingRouteAssignmentId: UUID?
    @State private var routeOpenErrorMessage: String?
    @State private var showRoutesInfo = false

    private var filteredBySearch: [RouteAssignmentSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return allAssignments }
        return allAssignments.filter { $0.name.lowercased().contains(q) }
    }

    private var tabbed: [RouteAssignmentSummary] {
        filteredBySearch.filter { row in
            let s = row.status.lowercased()
            switch selectedTab {
            case .active:
                if s == "completed" { return false }
                return true
            case .completed:
                return s == "completed"
            }
        }
    }

    private var activeCount: Int {
        filteredBySearch.filter { $0.status.lowercased() != "completed" }.count
    }

    private var completedCount: Int {
        filteredBySearch.filter { $0.status.lowercased() == "completed" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Active (\(activeCount))").tag(AssignmentTab.active)
                Text("Completed (\(completedCount))").tag(AssignmentTab.completed)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            SearchField(text: $searchText, placeholder: "Search routes")
                .padding(.horizontal)
                .padding(.vertical, 10)

            Group {
                if isLoading && allAssignments.isEmpty {
                    ProgressView("Loading routes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, allAssignments.isEmpty {
                    contentError(message: errorMessage)
                } else if allAssignments.isEmpty {
                    contentEmpty
                } else if tabbed.isEmpty {
                    contentNoMatches
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(tabbed) { route in
                                Button {
                                    Task { await openRoute(route) }
                                } label: {
                                    RouteAssignmentRowCard(
                                        route: route,
                                        isOpening: openingRouteAssignmentId == route.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(openingRouteAssignmentId != nil)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRoutesInfo = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: workspace.workspaceId) {
            await loadRoutes()
        }
        .refreshable {
            await loadRoutes()
        }
        .sheet(item: $routeDetailAssignmentSheetItem) { item in
            NavigationStack {
                RouteAssignmentDetailView(assignmentId: item.id)
            }
        }
        .alert("About Routes", isPresented: $showRoutesInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Routes are generated on desktop. Their primary use case is for team owners to assign work across multiple agents. For most individual owners, the main workflow is to create a campaign and work within that.")
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

    @ViewBuilder
    private func contentError(message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn’t load routes")
                .font(.flyrHeadline)
            Text(message)
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentEmpty: some View {
        VStack(spacing: 14) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Select a route")
                .font(.flyrHeadline)
            Text("You don’t have any assignments yet. Open a campaign and assign a route plan from the web, or ask an admin.")
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentNoMatches: some View {
        VStack(spacing: 10) {
            Text("No routes match")
                .font(.flyrHeadline)
            Text(selectedTab == .completed ? "Completed routes will appear here." : "Try another search or check the Completed tab.")
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadRoutes() async {
        guard let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: workspace.workspaceId) else {
            allAssignments = []
            errorMessage = "No workspace selected."
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await RouteAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceId)
            allAssignments = result.assignments
            errorMessage = nil
        } catch {
            do {
                let legacy = try await RoutePlansAPI.shared.fetchMyAssignedRoutes(workspaceId: workspaceId)
                allAssignments = legacy
                errorMessage = nil
            } catch {
                allAssignments = []
                errorMessage = error.localizedDescription
            }
        }
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
            return
        }

        if let campaignId {
            uiState.selectCampaign(id: campaignId, name: routeName)
            uiState.selectedTabIndex = 1
            return
        }

        routeDetailAssignmentSheetItem = RouteAssignmentDetailSheetItem(id: fallbackAssignmentId)
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }
}

// MARK: - Row

private struct RouteAssignmentRowCard: View {
    let route: RouteAssignmentSummary
    var isOpening: Bool = false

    private var statusColor: Color {
        switch route.status.lowercased() {
        case "completed":
            return .green
        case "in_progress":
            return .orange
        case "cancelled", "declined":
            return .gray
        default:
            return .blue
        }
    }

    private var progressLine: String {
        "\(route.completedStops)/\(max(route.totalStops, 0)) complete"
    }

    private var secondaryStatusBadge: Bool {
        let s = route.status.lowercased()
        return s == "declined" || s == "cancelled"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RouteCardEmblem()

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Text(route.name)
                        .font(.flyrHeadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(route.statusLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(statusColor.opacity(0.14))
                            .clipShape(Capsule())
                        if secondaryStatusBadge {
                            Text("Shown under Active")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        if isOpening {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                HStack(spacing: 12) {
                    RouteMetaPill(text: "\(route.totalStops) stops", icon: "mappin.and.ellipse")
                    if let estMinutes = route.estMinutes {
                        RouteMetaPill(text: "\(estMinutes) min", icon: "clock")
                    }
                    if let distanceMeters = route.distanceMeters {
                        RouteMetaPill(text: formatDistance(distanceMeters), icon: "point.topleft.down.curvedto.point.bottomright.up")
                    }
                }

                if let assignee = route.assigneeDisplayName {
                    Text("Assignee: \(assignee)")
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                } else if let by = route.assignedByName {
                    Text("Assigned by \(by)")
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: route.progressFraction)
                    .tint(.red)
                Text(progressLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters)m"
    }
}

private struct RouteMetaPill: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }
}

private struct RouteCardEmblem: View {
    /// Tailwind `red-600` — same family as FLYR-PRO route actions (`bg-red-600` + white icon).
    private static let routeAccent = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Self.routeAccent)
                .frame(width: 44, height: 44)

            RoutesGlyph(color: .white, lineWidth: 2.2)
                .frame(width: 24, height: 20)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        RoutesListView()
    }
    .environmentObject(AppUIState())
}
