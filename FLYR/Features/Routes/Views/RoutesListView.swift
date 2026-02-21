import SwiftUI

struct RoutesListView: View {
    @ObservedObject private var workspace = WorkspaceContext.shared

    @State private var routes: [RouteAssignmentSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && routes.isEmpty {
                ProgressView("Loading routes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, routes.isEmpty {
                contentError(message: errorMessage)
            } else if routes.isEmpty {
                contentEmpty
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(routes) { route in
                            NavigationLink {
                                RoutePlanDetailView(routePlanId: route.routePlanId, assignment: route)
                            } label: {
                                RouteAssignmentCard(route: route)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workspace.workspaceId) {
            await loadRoutes()
        }
        .refreshable {
            await loadRoutes()
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
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No assigned routes")
                .font(.flyrHeadline)
            Text("Ask your team owner to assign a Route Plan.")
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadRoutes() async {
        guard let workspaceId = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: workspace.workspaceId) else {
            routes = []
            errorMessage = "No workspace selected."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            routes = try await RoutePlansAPI.shared.fetchMyAssignedRoutes(workspaceId: workspaceId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RouteAssignmentCard: View {
    let route: RouteAssignmentSummary

    private var statusColor: Color {
        switch route.status.lowercased() {
        case "completed":
            return .green
        case "in_progress":
            return .orange
        case "cancelled":
            return .gray
        default:
            return .blue
        }
    }

    private var progressLine: String {
        "\(route.completedStops)/\(max(route.totalStops, 0)) complete"
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
                    Text(route.statusLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.14))
                        .clipShape(Capsule())
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

                Text(route.assignedByName.map { "Assigned by \($0)" } ?? "Assigned route")
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)

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
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.9))
                .frame(width: 44, height: 44)

            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        RoutesListView()
    }
}
