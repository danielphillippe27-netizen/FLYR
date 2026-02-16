import SwiftUI
import Supabase
import Combine

/// Debug view for troubleshooting leaderboard and stats issues
/// Shows raw data from database to verify stats are being tracked correctly
struct LeaderboardDebugView: View {
    @StateObject private var vm = LeaderboardDebugViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Current User Stats
                    debugSection(title: "Current User Stats") {
                        if let stats = vm.userStats {
                            debugRow("User ID", stats.userId)
                            debugRow("Doors", "\(stats.flyers)")
                            debugRow("Conversations", "\(stats.conversations)")
                            debugRow("Distance", String(format: "%.2f km", stats.distance))
                            debugRow("Time", "\(stats.timeMinutes) min")
                            debugRow("Updated", formattedDate(stats.updatedAt))
                        } else if vm.isLoading {
                            ProgressView()
                        } else {
                            Text("No stats found")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Recent Sessions
                    debugSection(title: "Recent Sessions (Last 5)") {
                        if vm.recentSessions.isEmpty && !vm.isLoading {
                            Text("No sessions found")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(vm.recentSessions) { session in
                                VStack(alignment: .leading, spacing: 4) {
                                    debugRow("Started", formattedDate(session.startTime))
                                    debugRow("Doors", "\(session.flyersDelivered)")
                                    debugRow("Conversations", "\(session.conversations)")
                                    debugRow("Distance", String(format: "%.2f m", session.distanceMeters))
                                }
                                .padding(.vertical, 8)
                                
                                if session.id != vm.recentSessions.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    // Leaderboard Raw Data
                    debugSection(title: "Leaderboard (Top 5)") {
                        if vm.leaderboardEntries.isEmpty && !vm.isLoading {
                            Text("No leaderboard entries")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(vm.leaderboardEntries.prefix(5)) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    debugRow("Rank", "#\(entry.rank)")
                                    debugRow("Name", entry.name)
                                    debugRow("Doors", "\(entry.flyers)")
                                    debugRow("Conversations", "\(entry.conversations)")
                                }
                                .padding(.vertical, 8)
                                
                                if entry.id != vm.leaderboardEntries.prefix(5).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    // Error Display
                    if let error = vm.errorMessage {
                        debugSection(title: "Error") {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.system(size: 13, design: .monospaced))
                        }
                    }
                    
                    // Refresh Button
                    Button(action: {
                        Task {
                            await vm.refresh()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh All Data")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(vm.isLoading)
                }
                .padding()
            }
            .navigationTitle("Debug: Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.refresh()
            }
        }
    }
    
    private func debugSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func debugRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - View Model

@MainActor
class LeaderboardDebugViewModel: ObservableObject {
    @Published var userStats: DebugUserStats?
    @Published var recentSessions: [DebugSession] = []
    @Published var leaderboardEntries: [DebugLeaderboardEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        async let statsTask = fetchUserStats()
        async let sessionsTask = fetchRecentSessions()
        async let leaderboardTask = fetchLeaderboard()
        
        do {
            let (stats, sessions, leaderboard) = try await (statsTask, sessionsTask, leaderboardTask)
            self.userStats = stats
            self.recentSessions = sessions
            self.leaderboardEntries = leaderboard
        } catch {
            errorMessage = error.localizedDescription
            print("❌ [LeaderboardDebug] Error refreshing: \(error)")
        }
    }
    
    private func fetchUserStats() async throws -> DebugUserStats? {
        guard let userId = AuthManager.shared.user?.id else {
            return nil
        }
        
        struct Response: Decodable {
            let user_id: String
            let flyers: Int
            let conversations: Int
            let distance_walked: Double
            let time_tracked: Int
            let updated_at: String
        }
        
        let response: [Response] = try await SupabaseManager.shared.client
            .from("user_stats")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        
        guard let first = response.first else { return nil }
        
        let dateFormatter = ISO8601DateFormatter()
        let updatedAt = dateFormatter.date(from: first.updated_at) ?? Date()
        
        return DebugUserStats(
            userId: first.user_id,
            flyers: first.flyers,
            conversations: first.conversations,
            distance: first.distance_walked,
            timeMinutes: first.time_tracked,
            updatedAt: updatedAt
        )
    }
    
    private func fetchRecentSessions() async throws -> [DebugSession] {
        guard let userId = AuthManager.shared.user?.id else {
            return []
        }
        
        struct Response: Decodable {
            let id: String
            let start_time: String
            let flyers_delivered: Int
            let conversations: Int
            let distance_meters: Double
        }
        
        let response: [Response] = try await SupabaseManager.shared.client
            .from("sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("start_time", ascending: false)
            .limit(5)
            .execute()
            .value
        
        let dateFormatter = ISO8601DateFormatter()
        
        return response.compactMap { item in
            guard let startTime = dateFormatter.date(from: item.start_time) else {
                return nil
            }
            return DebugSession(
                id: item.id,
                startTime: startTime,
                flyersDelivered: item.flyers_delivered,
                conversations: item.conversations,
                distanceMeters: item.distance_meters
            )
        }
    }
    
    private func fetchLeaderboard() async throws -> [DebugLeaderboardEntry] {
        struct Response: Decodable {
            let id: String
            let name: String
            let rank: Int
            let flyers: Int
            let conversations: Int
        }
        
        let response: [Response] = try await SupabaseManager.shared.client
            .rpc("get_leaderboard", params: [
                "p_metric": AnyCodable("flyers"),
                "p_timeframe": AnyCodable("weekly")
            ])
            .execute()
            .value
        
        return response.map { item in
            DebugLeaderboardEntry(
                id: item.id,
                name: item.name,
                rank: item.rank,
                flyers: item.flyers,
                conversations: item.conversations
            )
        }
    }
}

// MARK: - Models

struct DebugUserStats {
    let userId: String
    let flyers: Int
    let conversations: Int
    let distance: Double
    let timeMinutes: Int
    let updatedAt: Date
}

struct DebugSession: Identifiable {
    let id: String
    let startTime: Date
    let flyersDelivered: Int
    let conversations: Int
    let distanceMeters: Double
}

struct DebugLeaderboardEntry: Identifiable {
    let id: String
    let name: String
    let rank: Int
    let flyers: Int
    let conversations: Int
}

#Preview {
    LeaderboardDebugView()
}
