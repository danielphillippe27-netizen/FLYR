import SwiftUI
import Combine

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var stats: UserStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab = "Week" // "Week" or "All Time"
    
    private let statsService = StatsService.shared
    
    func loadStats(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            stats = try await statsService.fetchUserStats(userID: userID)
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
            print("❌ Error loading stats: \(error)")
        }
    }
    
    func refreshStats(for userID: UUID) async {
        await loadStats(for: userID)
    }
}

