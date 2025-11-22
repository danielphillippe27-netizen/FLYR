import SwiftUI
import Auth

struct LeaderboardView: View {
    @StateObject private var vm = LeaderboardViewModel()
    @StateObject private var auth = AuthManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and period
            LeaderboardHeaderView(selectedPeriod: $vm.timeRange)
                .padding(.top, 8)
            
            // Period selector
            LeaderboardTimeSelector(selected: $vm.timeRange)
                .padding(.top, 8)
            
            // Metric selector
            LeaderboardMetricSelector(selected: Binding(
                get: { vm.metric.rawValue },
                set: { newValue in
                    if let newMetric = MetricType(rawValue: newValue) {
                        vm.metric = newMetric
                    }
                }
            ))
            .padding(.top, 4)
            
            // Content
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 24)
            } else if let errorMessage = vm.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.muted)
                    Text(errorMessage)
                        .font(.system(size: 15))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task {
                            await vm.fetchLeaderboard()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if vm.users.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "trophy")
                        .font(.largeTitle)
                        .foregroundColor(.muted)
                    Text("No leaderboard entries yet")
                        .font(.system(size: 15))
                        .foregroundColor(.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Card container for leaderboard
                        VStack(spacing: 12) {
                            // Header row
                            LeaderboardHeaderRow(selectedMetric: $vm.metric)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                            
                            // Leaderboard rows
                            ForEach(vm.users) { user in
                                LeaderboardRowView(
                                    user: user,
                                    metric: vm.metric.rawValue,
                                    timeframe: vm.timeRange.rawValue,
                                    isCurrentUser: auth.user?.id.uuidString == user.id
                                )
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.bottom, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.bg)
                                .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .onAppear {
            Task {
                await vm.fetchLeaderboard()
            }
        }
        .onChange(of: vm.metric) { _, _ in
            Task {
                await vm.fetchLeaderboard()
            }
        }
        .onChange(of: vm.timeRange) { _, _ in
            Task {
                await vm.fetchLeaderboard()
            }
        }
        .refreshable {
            await vm.fetchLeaderboard()
        }
    }
}

// Header row component with clickable metric
struct LeaderboardHeaderRow: View {
    @Binding var selectedMetric: MetricType
    
    private var isFlyers: Bool {
        selectedMetric == .flyers
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("Rank")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.muted)
                .frame(width: 40, alignment: .leading)
            
            // Name
            Text("Name")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.muted)
                .lineLimit(1)
            
            Spacer()
            
            // Metric (clickable)
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedMetric = selectedMetric.next()
                }
            }) {
                Text(selectedMetric.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isFlyers ? Color(hex: "#FF5A4E") : .text)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.bg)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
    }
}

// Helper view to break up complex expressions for type-checking
private struct LeaderboardRowView: View {
    let user: LeaderboardUser
    let metric: String
    let timeframe: String
    let isCurrentUser: Bool
    
    private var userValue: Double {
        user.value(for: metric, timeframe: timeframe)
    }
    
    var body: some View {
        LeaderboardRow(
            rank: user.rank,
            name: user.name,
            value: userValue,
            isCurrentUser: isCurrentUser
        )
    }
}

#Preview {
    NavigationStack {
        LeaderboardView()
    }
}
