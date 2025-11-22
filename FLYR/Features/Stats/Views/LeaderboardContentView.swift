import SwiftUI
import Supabase
import Auth

struct LeaderboardContentView: View {
    @StateObject private var viewModel = LeaderboardViewModel()
    @StateObject private var auth = AuthManager.shared
    @State private var showStatsSettings = false
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Metric Picker
                MetricPickerView(selectedSort: $viewModel.selectedSort)
                    .onChange(of: viewModel.selectedSort) { oldValue, newSort in
                        Task {
                            await viewModel.changeSort(newSort)
                        }
                    }
                
                // Content
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let _ = viewModel.errorMessage {
                    LeaderboardErrorView {
                        Task {
                            await viewModel.loadLeaderboard()
                        }
                    }
                } else if viewModel.entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trophy")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No leaderboard entries yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Leaderboard Card Container
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Material.regular)
                                .overlay(
                                    VStack(spacing: 0) {
                                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                                            LeaderboardRowCard(
                                                entry: entry,
                                                selectedSort: viewModel.selectedSort,
                                                currentUserID: auth.user?.id
                                            )
                                            
                                            if index < viewModel.entries.count - 1 {
                                                Divider()
                                                    .padding(.vertical, 8)
                                            }
                                        }
                                    }
                                    .padding(20)
                                )
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            
                            // Stats Settings Row
                            NavigationLink {
                                StatsSettingsView(viewModel: viewModel)
                            } label: {
                                HStack {
                                    Text("Stats Settings")
                                        .font(.system(.body))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(.caption))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                            }
                            .padding(.top, 24)
                            
                            Spacer(minLength: 40)
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadLeaderboard()
        }
        .refreshable {
            await viewModel.loadLeaderboard()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
}

#Preview {
    NavigationStack {
        LeaderboardContentView()
    }
}

