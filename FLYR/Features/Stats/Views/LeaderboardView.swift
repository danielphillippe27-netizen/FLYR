import SwiftUI
private let accentRed = Color(hex: "#FF4F4F")

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
                List {
                    Section {
                        ForEach(vm.users) { user in
                            rowContent(for: user)
                        }
                    } header: {
                        LeaderboardTableHeaderView(selectedMetric: $vm.metric, selectedPeriod: $vm.timeRange)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(Color.primary.opacity(0.12))
                    .listRowBackground(Color.bg)

                    // Show "You" when current user is not in the leaderboard (no activity in this period)
                    if let currentUser = auth.user, !vm.users.contains(where: { $0.id == currentUser.id.uuidString }) {
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
        .background(Color.bg.ignoresSafeArea())
        .task(id: "\(vm.metric.rawValue)-\(vm.timeRange.rawValue)") {
            await vm.fetchLeaderboard()
        }
        .refreshable {
            await vm.fetchLeaderboard()
            HapticManager.rigid()
        }
    }

    @ViewBuilder
    private func rowContent(for user: LeaderboardUser) -> some View {
        let isCurrentUser = auth.user?.id.uuidString == user.id
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

// MARK: - Sticky table header (# | Name | Period ▼ | Metric ▼) — period before metric

struct LeaderboardTableHeaderView: View {
    @Binding var selectedMetric: MetricType
    @Binding var selectedPeriod: TimeRange

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

            // Time period (All Time / Monthly / etc.) before metric
            Menu {
                ForEach(TimeRange.allCases, id: \.rawValue) { range in
                    Button(range.displayName) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedPeriod = range
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedPeriod.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentRed)
            }
            .buttonStyle(.plain)
            .frame(minWidth: 80, alignment: .trailing)

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
