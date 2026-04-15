import SwiftUI

/// Assignment-centric detail loaded from `GET /api/routes/assignments/{id}`.
struct RouteAssignmentDetailView: View {
    let assignmentId: UUID

    @EnvironmentObject private var uiState: AppUIState
    @State private var detail: RouteAssignmentDetailPayload?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isPosting = false
    @State private var showMap = false
    @State private var mapMode: RouteAssignmentMapDisplayMode = .buildings
    @State private var showDeclineSheet = false
    @State private var declineReasonDraft = ""

    private static let dueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Loading route...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, detail == nil {
                errorState(message: errorMessage)
            } else if let detail {
                content(detail)
            } else {
                ProgressView("Loading route...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(detail?.displayPlanName ?? "Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMap = true
                } label: {
                    Image(systemName: "map")
                }
                .disabled(detail?.stops.isEmpty ?? true)
            }
        }
        .sheet(isPresented: $showMap) {
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("Mode", selection: $mapMode) {
                        ForEach(RouteAssignmentMapDisplayMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    RouteAssignmentMapRepresentable(
                        campaignId: detail?.campaignId,
                        stops: detail?.stops ?? [],
                        mode: mapMode
                    )
                    .ignoresSafeArea(edges: .bottom)
                }
                .navigationTitle("Route map")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showMap = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showDeclineSheet) {
            NavigationStack {
                Form {
                    Section("Decline (optional)") {
                        TextField("Reason", text: $declineReasonDraft, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                .navigationTitle("Decline route")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showDeclineSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Decline") {
                            showDeclineSheet = false
                            Task { await perform(.decline, declineReason: declineReasonDraft) }
                        }
                    }
                }
            }
        }
        .task(id: assignmentId) {
            await load()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text("Route not found")
                .font(.flyrHeadline)
            Text(message)
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ detail: RouteAssignmentDetailPayload) -> some View {
        let eligible = eligibleActions(for: detail)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection(detail)

                if !eligible.isEmpty {
                    workflowSection(detail, eligible: eligible)
                }

                if let cid = detail.campaignId {
                    Button {
                        openRoute(detail, campaignId: cid)
                    } label: {
                        Label(detail.stops.isEmpty ? "Open campaign" : "Work route", systemImage: "map.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                if !detail.stops.isEmpty {
                    Text("STOPS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(detail.stops) { stop in
                        stopRow(stop)
                    }
                }
            }
            .padding()
        }
    }

    private func summarySection(_ detail: RouteAssignmentDetailPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.displayPlanName)
                .font(.flyrHeadline)

            HStack(spacing: 10) {
                statusBadge(detail.status)
                if let p = detail.priority, !p.isEmpty {
                    Text("Priority \(p)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                meta(icon: "mappin.and.ellipse", text: "\(detail.totalStops) stops")
                if let m = detail.estMinutes {
                    meta(icon: "clock", text: "\(m) min")
                }
                if let d = detail.distanceMeters {
                    meta(icon: "figure.walk", text: formatDistance(d))
                }
            }

            if let due = detail.dueAt {
                Label("Due \(Self.dueFormatter.string(from: due))", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let name = detail.assigneeDisplayName {
                Text("Assignee: \(name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let name = detail.assignedByDisplayName {
                Text("Assigned by \(name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let reason = detail.declineReason, !reason.isEmpty, detail.status.lowercased() == "declined" {
                Text("Decline reason: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
    }

    private func workflowSection(_ detail: RouteAssignmentDetailPayload, eligible: Set<RouteAssignmentWorkflowAction>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIONS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if eligible.contains(.accept) {
                    actionButton("Accept", systemImage: "checkmark.circle.fill", role: nil) {
                        Task { await perform(.accept, declineReason: nil) }
                    }
                }
                if eligible.contains(.decline) {
                    actionButton("Decline", systemImage: "xmark.circle.fill", role: .destructive) {
                        declineReasonDraft = ""
                        showDeclineSheet = true
                    }
                }
                if eligible.contains(.start) {
                    actionButton("Start", systemImage: "play.circle.fill", role: nil) {
                        Task { await perform(.start, declineReason: nil) }
                    }
                }
                if eligible.contains(.complete) {
                    actionButton("Complete", systemImage: "flag.checkered", role: nil) {
                        Task { await perform(.complete, declineReason: nil) }
                    }
                }
                if eligible.contains(.cancel) {
                    actionButton("Cancel", systemImage: "slash.circle.fill", role: .destructive) {
                        Task { await perform(.cancel, declineReason: nil) }
                    }
                }
            }

            if isPosting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .disabled(isPosting)
    }

    private func stopRow(_ stop: RoutePlanStop) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(stop.stopOrder)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.red)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.displayAddress)
                    .font(.system(size: 14, weight: .medium))
                if let lat = stop.latitude, let lon = stop.longitude {
                    Text(String(format: "%.5f, %.5f", lat, lon))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let aid = stop.addressId {
                        Text("address \(shortUUID(aid))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let bid = stop.buildingId {
                        Text("building \(shortUUID(bid))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let g = stop.gersId, !g.isEmpty {
                        Text("gers \(g)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let visited = stop.visited {
                        Text(visited ? "Visited" : "Not visited")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(visited ? .green : .secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
    }

    private func shortUUID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }

    private func meta(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters)m"
    }

    private func isAssignee(detail: RouteAssignmentDetailPayload) -> Bool {
        guard let uid = AuthManager.shared.user?.id,
              let assignee = detail.assignedToUserId else { return false }
        return uid == assignee
    }

    private func eligibleActions(for detail: RouteAssignmentDetailPayload) -> Set<RouteAssignmentWorkflowAction> {
        RouteTransitionEligibility.eligibleActions(
            status: detail.status,
            isAssignee: isAssignee(detail: detail),
            canManageRoutes: detail.canManageRoutes
        )
    }

    private func openRoute(_ detail: RouteAssignmentDetailPayload, campaignId: UUID) {
        if let context = RouteWorkContext(detail: detail) {
            uiState.selectRoute(context)
            uiState.selectedTabIndex = 1
            return
        }

        uiState.selectCampaign(id: campaignId, name: detail.displayPlanName)
        uiState.selectedTabIndex = 1
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await RouteAssignmentsAPI.shared.fetchAssignmentDetail(assignmentId: assignmentId)
            errorMessage = nil
        } catch let e as RouteAssignmentsAPIError {
            errorMessage = e.localizedDescription
            detail = nil
        } catch {
            errorMessage = error.localizedDescription
            detail = nil
        }
    }

    private func perform(_ action: RouteAssignmentWorkflowAction, declineReason: String?) async {
        isPosting = true
        defer { isPosting = false }
        do {
            try await RouteAssignmentsAPI.shared.postAssignmentStatus(
                assignmentId: assignmentId,
                action: action,
                declineReason: declineReason
            )
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
