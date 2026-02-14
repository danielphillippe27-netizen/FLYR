import Foundation
import Supabase

actor LeaderboardService {
    static let shared = LeaderboardService()
    
    private let client: SupabaseClient
    private var realtimeChannel: RealtimeChannelV2?
    private var pollingTask: Task<Void, Never>?
    
    private init() {
        // Store client reference - SupabaseManager.shared is thread-safe for reading
        // We'll access it properly in async context
        self.client = SupabaseManager.shared.client
    }
    
    // MARK: - Fetch Leaderboard
    
    func fetchLeaderboard(
        sortBy: LeaderboardSortBy = .flyers,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> [LeaderboardEntry] {
        let params: [String: AnyCodable] = [
            "sort_by": AnyCodable(sortBy.rawValue),
            "limit_count": AnyCodable(limit),
            "offset_count": AnyCodable(offset)
        ]
        
        print("📊 [LeaderboardService] Fetching leaderboard with params: sortBy=\(sortBy.rawValue), limit=\(limit), offset=\(offset)")
        
        do {
            let response: [LeaderboardEntry] = try await client
                .rpc("get_leaderboard", params: params)
                .execute()
                .value
            
            print("✅ [LeaderboardService] Successfully fetched \(response.count) entries")
            return response
        } catch {
            print("❌ [LeaderboardService] RPC call failed:")
            print("   Function: get_leaderboard")
            print("   Params: \(params)")
            print("   Error: \(error)")
            print("   Error type: \(type(of: error))")
            
            // Re-throw with more context
            throw error
        }
    }
    
    // MARK: - Real-time Subscription (Pro Mode)
    // Using polling approach for reliability until real-time API is confirmed
    
    func subscribeToLeaderboardUpdates(
        sortBy: LeaderboardSortBy = .flyers,
        onUpdate: @escaping ([LeaderboardEntry]) -> Void
    ) async throws {
        // Stop any existing polling
        await unsubscribeFromLeaderboard()
        
        // Start polling every 5 seconds for updates
        pollingTask = Task {
            while !Task.isCancelled {
                do {
                    let entries = try await fetchLeaderboard(sortBy: sortBy)
                    await MainActor.run {
                        onUpdate(entries)
                    }
                } catch {
                    print("❌ Error fetching updated leaderboard: \(error)")
                }
                
                // Wait 5 seconds before next poll
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    
    func unsubscribeFromLeaderboard() async {
        pollingTask?.cancel()
        pollingTask = nil
        
        if let channel = realtimeChannel {
            await client.realtimeV2.removeChannel(channel)
            realtimeChannel = nil
        }
    }
    
    // MARK: - Get User Rank
    
    func getUserRank(userID: UUID, sortBy: LeaderboardSortBy = .flyers) async throws -> Int? {
        let entries = try await fetchLeaderboard(sortBy: sortBy, limit: 1000, offset: 0)
        return entries.firstIndex(where: { $0.user_id == userID }).map { $0 + 1 }
    }
    
    // MARK: - Fetch Leaderboard with Timeframe (New API)
    
    func fetchLeaderboard(
        metric: String,
        timeframe: String
    ) async throws -> [LeaderboardUser] {
        // Must match DB function param names: get_leaderboard(p_metric, p_timeframe)
        let params: [String: AnyCodable] = [
            "p_metric": AnyCodable(metric),
            "p_timeframe": AnyCodable(timeframe)
        ]
        
        print("📊 [LeaderboardService] Fetching leaderboard with params: metric=\(metric), timeframe=\(timeframe)")
        
        do {
            let response = try await client
                .rpc("get_leaderboard", params: params)
                .execute()
            
            // Decode the JSON response
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            // Handle the nested JSONB fields for metric snapshots
            let data = response.data
            
            // First, decode as array of dictionaries to handle JSONB properly
            if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let users = try jsonArray.map { dict -> LeaderboardUser in
                    // Extract and decode JSONB fields manually
                    let dailyDict = dict["daily"] as? [String: Any] ?? [:]
                    let weeklyDict = dict["weekly"] as? [String: Any] ?? [:]
                    let allTimeDict = dict["all_time"] as? [String: Any] ?? [:]
                    
                    let daily = MetricSnapshot(
                        flyers: dailyDict["flyers"] as? Int ?? 0,
                        leads: dailyDict["leads"] as? Int ?? 0,
                        conversations: dailyDict["conversations"] as? Int ?? 0,
                        distance: dailyDict["distance"] as? Double ?? 0.0,
                        doorknocks: dailyDict["doorknocks"] as? Int ?? 0
                    )
                    
                    let weekly = MetricSnapshot(
                        flyers: weeklyDict["flyers"] as? Int ?? 0,
                        leads: weeklyDict["leads"] as? Int ?? 0,
                        conversations: weeklyDict["conversations"] as? Int ?? 0,
                        distance: weeklyDict["distance"] as? Double ?? 0.0,
                        doorknocks: weeklyDict["doorknocks"] as? Int ?? 0
                    )
                    
                    let allTime = MetricSnapshot(
                        flyers: allTimeDict["flyers"] as? Int ?? 0,
                        leads: allTimeDict["leads"] as? Int ?? 0,
                        conversations: allTimeDict["conversations"] as? Int ?? 0,
                        distance: allTimeDict["distance"] as? Double ?? 0.0,
                        doorknocks: allTimeDict["doorknocks"] as? Int ?? 0
                    )
                    
                    // Create LeaderboardUser manually to handle JSONB fields
                    return LeaderboardUser(
                        id: dict["id"] as? String ?? "",
                        name: dict["name"] as? String ?? "User",
                        avatarUrl: dict["avatar_url"] as? String,
                        rank: dict["rank"] as? Int ?? 0,
                        flyers: dict["flyers"] as? Int ?? 0,
                        leads: dict["leads"] as? Int ?? 0,
                        conversations: dict["conversations"] as? Int ?? 0,
                        distance: dict["distance"] as? Double ?? 0.0,
                        daily: daily,
                        weekly: weekly,
                        allTime: allTime
                    )
                }
                
                print("✅ [LeaderboardService] Successfully fetched \(users.count) users")
                return users
            } else {
                // Fallback to standard decoding
                let users = try decoder.decode([LeaderboardUser].self, from: data)
                print("✅ [LeaderboardService] Successfully fetched \(users.count) users")
                return users
            }
        } catch {
            print("❌ [LeaderboardService] RPC call failed:")
            print("   Function: get_leaderboard")
            print("   Params: \(params)")
            print("   Error: \(error)")
            print("   Error type: \(type(of: error))")
            
            // Re-throw with more context
            throw error
        }
    }
}

