import SwiftUI
private let accentRed = Color(hex: "#FF4F4F")

/// Global filter: show all users or filter to current team/workspace (when backend supports it).
enum LeaderboardScope: String, CaseIterable {
    case all = "all"
    case team = "team"

    var displayName: String {
        switch self {
        case .all: return "Global"
        case .team: return "My team"
        }
    }
}

struct LeaderboardView: View {
    @StateObject private var vm = LeaderboardViewModel()
    @StateObject private var auth = AuthManager.shared
    @Environment(\.toastManager) private var toastManager

    var body: some View {
        VStack(spacing: 0) {
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 24)
            } else if let errorMessage = vm.errorMessage {
                errorView(message: errorMessage)
            } else if vm.users.isEmpty && auth.user == nil {
                emptyView
            } else {
                VStack(spacing: 0) {
                    LeaderboardTableHeaderView(selectedMetric: $vm.metric)
                    List {
                        Section {
                            ForEach(vm.users) { user in
                                rowContent(for: user)
                            }
                        }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(Color.primary.opacity(0.12))
                    .listRowBackground(Color.bg)

                    // Show "You" only when current user is not in the leaderboard (no activity in this period).
                    // Compare by UUID so we match even if API returns id with/without dashes.
                    if let currentUser = auth.user, !currentUserIsInLeaderboard(currentUser: currentUser) {
                        Section {
                            youRow(currentUser: currentUser)
                        } footer: {
                            if !vm.users.isEmpty {
                                Text("If you see your name above with activity, you may be signed in with a different account. Sign in with that account to see your stats and set up your profile.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(Color.primary.opacity(0.12))
                        .listRowBackground(Color.bg)
                    }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LeaderboardHeaderFilters(scope: $vm.scope, timeRange: $vm.timeRange)
            }
        }
        .task(id: "\(vm.metric.rawValue)-\(vm.timeRange.rawValue)-\(vm.scope.rawValue)") {
            await vm.fetchLeaderboard()
        }
        .refreshable {
            await vm.fetchLeaderboard()
            HapticManager.rigid()
        }
    }

    @ViewBuilder
    private func rowContent(for user: LeaderboardUser) -> some View {
        let isCurrentUser = isCurrentAuthUser(leaderboardUserId: user.id)
        let value = user.value(for: vm.metric.rawValue, timeframe: vm.timeRange.rawValue)

        Button {
            HapticManager.light()
            toastManager.show(
                message: "\(user.name) · Rank #\(user.rank)",
                type: .info,
                duration: 2.0
            )
        } label: {
            LeaderboardRow(
                rank: user.rank,
                avatarUrl: user.avatarUrl,
                name: user.name,
                subtitle: nil,
                value: value,
                isCurrentUser: isCurrentUser,
                isActiveMetric: true
            )
        }
        .buttonStyle(.plain)
    }

    /// Row shown when the current user is not in the leaderboard (no sessions in selected period).
    /// Uses profile name (from profiles table) or auth display name — never email.
    private func youRow(currentUser: AppUser) -> some View {
        let displayName = displayNameForCurrentUser(currentUser: currentUser)
        return Button {
            HapticManager.light()
            toastManager.show(
                message: "No activity for \(vm.timeRange.displayName) yet",
                type: .info,
                duration: 2.0
            )
        } label: {
            LeaderboardRow(
                rank: 0,
                avatarUrl: vm.currentUserProfileImageURL ?? vm.currentUserProfile?.avatarURL ?? currentUser.photoURL?.absoluteString,
                name: displayName,
                subtitle: "No activity this period",
                value: 0,
                valueDisplay: "—",
                isCurrentUser: true,
                isActiveMetric: true
            )
        }
        .buttonStyle(.plain)
    }

    /// True if the current user appears in the leaderboard list (so we don't show a duplicate "You" row).
    private func currentUserIsInLeaderboard(currentUser: AppUser) -> Bool {
        vm.users.contains { isCurrentAuthUser(leaderboardUserId: $0.id) }
    }

    /// True if the given leaderboard user id is the signed-in user (handles UUID string with or without dashes).
    private func isCurrentAuthUser(leaderboardUserId: String) -> Bool {
        guard let current = auth.user else { return false }
        if let userUUID = UUID(uuidString: leaderboardUserId) { return userUUID == current.id }
        let normalized = leaderboardUserId.lowercased().replacingOccurrences(of: "-", with: "")
        return normalized == current.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// Prefer profile name (first + last or full_name), then auth display name; never show email.
    private func displayNameForCurrentUser(currentUser: AppUser) -> String {
        if let profile = vm.currentUserProfile {
            let first = profile.firstName ?? ""
            let last = profile.lastName ?? ""
            let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            if !full.isEmpty { return full }
            if let fn = profile.fullName, !fn.isEmpty { return fn }
        }
        if let authName = currentUser.displayName, !authName.isEmpty { return authName }
        return "You"
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy")
                .font(.flyrLargeTitle)
                .foregroundColor(.muted)
            Text("No leaderboard entries yet")
                .font(.system(size: 15))
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 24)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.flyrLargeTitle)
                .foregroundColor(.muted)
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await vm.fetchLeaderboard() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Header filters (Global + Monthly) — in nav bar beside "Leaderboard" title

struct LeaderboardHeaderFilters: View {
    @Binding var scope: LeaderboardScope
    @Binding var timeRange: TimeRange
    @ObservedObject private var workspace = WorkspaceContext.shared

    var body: some View {
        HStack(spacing: 12) {
            // Scope: Global | My team [workspace name]
            Menu {
                Button("Global") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { scope = .all }
                }
                if let name = workspace.workspaceName, !name.isEmpty {
                    Button(name) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { scope = .team }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(scopeDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentRed)
            }
            .buttonStyle(.plain)

            // Time period (Daily / Weekly / Monthly / All Time)
            Menu {
                ForEach(TimeRange.allCases, id: \.rawValue) { range in
                    Button(range.displayName) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            timeRange = range
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(timeRange.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentRed)
            }
            .buttonStyle(.plain)
        }
    }

    private var scopeDisplayName: String {
        if scope == .team, let name = workspace.workspaceName, !name.isEmpty {
            return name
        }
        return scope.displayName
    }
}

// MARK: - Sticky table header (# | Name | Metric ▼) — metric only; period is in global filter

struct LeaderboardTableHeaderView: View {
    @Binding var selectedMetric: MetricType

    var body: some View {
        HStack(spacing: 12) {
            Text("#")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.muted)
                .frame(width: 36, alignment: .leading)

            Text("Name")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Metric (Doors / Conversations / Distance)
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedMetric = selectedMetric.next()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedMetric.displayName)
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentRed)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: selectedMetric)
            .frame(minWidth: 100, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.bg)
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
    }
}
