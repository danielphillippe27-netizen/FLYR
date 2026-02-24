import SwiftUI

struct ActivityView: View {
    @StateObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var selectedFilter: ActivityFeedFilter = .activity
    @State private var items: [ActivityFeedItem] = []
    @State private var includeMembers = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            filterTabs
            if canIncludeMembers {
                includeMembersToggle
            }
            Group {
                if isLoading {
                    loadingView
                } else if let message = errorMessage {
                    errorView(message: message)
                } else if items.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadItems()
        }
        .task {
            await loadItems()
        }
        .onChange(of: selectedFilter) { _, _ in
            Task { await loadItems() }
        }
        .onChange(of: includeMembers) { _, _ in
            Task { await loadItems() }
        }
    }

    private var canIncludeMembers: Bool {
        guard let role = workspace.role?.lowercased() else { return false }
        return role == "owner" || role == "admin" || role == "team_lead" || role == "lead"
    }

    private var includeMembersEnabled: Bool {
        canIncludeMembers && includeMembers
    }

    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityFeedFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selectedFilter == filter ? .white : .muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selectedFilter == filter ? Color.white.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var includeMembersToggle: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $includeMembers)
                .labelsHidden()
            Image(systemName: "person.2")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
            Text("Include other members' activity")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.text)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(selectedFilter.rawValue.lowercased())...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName(for: selectedFilter))
                .font(.system(size: 42))
                .foregroundColor(.secondary)
            Text(emptyMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(items) { item in
                    activityRow(item)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func activityRow(_ item: ActivityFeedItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tintColor(for: item.kind).opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: symbolName(for: item.kind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tintColor(for: item.kind))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(item.timestamp, style: .relative)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary.opacity(0.75))
        )
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .activity:
            return "No activity yet"
        case .appointments:
            return "No appointments found"
        case .followUp:
            return "No follow-ups pending"
        }
    }

    private func iconName(for filter: ActivityFeedFilter) -> String {
        switch filter {
        case .activity:
            return "figure.walk"
        case .appointments:
            return "calendar"
        case .followUp:
            return "arrow.uturn.left.circle"
        }
    }

    private func symbolName(for kind: ActivityFeedKind) -> String {
        switch kind {
        case .session:
            return "figure.walk"
        case .appointment:
            return "calendar.badge.clock"
        case .followUp:
            return "arrow.uturn.left.circle.fill"
        }
    }

    private func tintColor(for kind: ActivityFeedKind) -> Color {
        switch kind {
        case .session:
            return .flyrPrimary
        case .appointment:
            return .purple
        case .followUp:
            return .orange
        }
    }

    private func loadItems() async {
        guard let userId = auth.user?.id else {
            errorMessage = "Please sign in to view activity"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            items = try await ActivityFeedService.shared.fetchItems(
                userId: userId,
                workspaceId: workspace.workspaceId,
                includeMembers: includeMembersEnabled,
                filter: selectedFilter,
                limit: 150
            )
        } catch {
            errorMessage = "Failed to load \(selectedFilter.rawValue.lowercased())"
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
