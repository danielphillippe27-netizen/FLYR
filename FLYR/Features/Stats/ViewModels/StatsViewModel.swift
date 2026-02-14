import SwiftUI
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var stats: UserStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab = "Week" // "Week" or "All Time"
    @Published var weeklyRank: Int?
    @Published var allTimeRank: Int?

    private let statsService = StatsService.shared
    private let leaderboardService = LeaderboardService.shared

    func loadStats(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            stats = try await statsService.fetchUserStats(userID: userID)
            await loadRanks(for: userID)
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
            print("❌ Error loading stats: \(error)")
        }
    }

    func loadRanks(for userID: UUID) async {
        let userIDString = userID.uuidString
        do {
            let weekly = try await leaderboardService.fetchLeaderboard(metric: "flyers", timeframe: "weekly")
            let allTime = try await leaderboardService.fetchLeaderboard(metric: "flyers", timeframe: "all_time")
            weeklyRank = weekly.firstIndex(where: { $0.id == userIDString }).map { $0 + 1 }
            allTimeRank = allTime.firstIndex(where: { $0.id == userIDString }).map { $0 + 1 }
        } catch {
            weeklyRank = nil
            allTimeRank = nil
        }
    }

    func refreshStats(for userID: UUID) async {
        await loadStats(for: userID)
    }
}

