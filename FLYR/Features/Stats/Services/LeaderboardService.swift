import Foundation
import Supabase

// #region agent log
#if DEBUG
private func _debugLogLeaderboard(location: String, message: String, data: [String: Any], hypothesisId: String) {
    let payload: [String: Any] = [
        "id": "log_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(8))",
        "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        "location": location,
        "message": message,
        "data": data,
        "hypothesisId": hypothesisId
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          let line = String(data: json, encoding: .utf8) else { return }
    let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let path = baseURL.appendingPathComponent("flyr_debug.log").path
    let lineWithNewline = line + "\n"
    guard let dataToWrite = lineWithNewline.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: path), let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(dataToWrite)
        try? handle.close()
    } else {
        try? dataToWrite.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
#else
private func _debugLogLeaderboard(location: String, message: String, data: [String: Any], hypothesisId: String) {}
#endif
// #endregion

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

    private func intValue(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let double as Double:
            return double
        case let float as Float:
            return Double(float)
        case let int as Int:
            return Double(int)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func snapshot(
        from value: Any?,
        fallback: MetricSnapshot
    ) -> MetricSnapshot {
        guard let dict = value as? [String: Any], !dict.isEmpty else {
            return fallback
        }

        let doorknocks = intValue(from: dict["doorknocks"])
            ?? intValue(from: dict["flyers"])
            ?? fallback.doorknocks

        return MetricSnapshot(
            flyers: intValue(from: dict["flyers"]) ?? doorknocks,
            leads: intValue(from: dict["leads"]) ?? fallback.leads,
            conversations: intValue(from: dict["conversations"]) ?? fallback.conversations,
            distance: doubleValue(from: dict["distance"]) ?? fallback.distance,
            doorknocks: doorknocks
        )
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
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                print("❌ [LeaderboardService] RPC call failed:")
                print("   Function: get_leaderboard")
                print("   Params: \(params)")
                print("   Error: \(error)")
                print("   Error type: \(type(of: error))")
            }
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
    
    /// When workspaceId is non-nil, restricts leaderboard to that workspace (My team).
    func fetchLeaderboard(
        metric: String,
        timeframe: String,
        workspaceId: UUID? = nil
    ) async throws -> [LeaderboardUser] {
        var params: [String: AnyCodable] = [
            "p_metric": AnyCodable(metric),
            "p_timeframe": AnyCodable(timeframe)
        ]
        if let workspaceId = workspaceId {
            params["p_workspace_id"] = AnyCodable(workspaceId.uuidString)
        }
        
        print("📊 [LeaderboardService] Fetching leaderboard with params: metric=\(metric), timeframe=\(timeframe), workspaceId=\(workspaceId?.uuidString ?? "nil")")
        
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
                let users = jsonArray.map { dict -> LeaderboardUser in
                    let topLevelDoorknocks = intValue(from: dict["doorknocks"])
                        ?? intValue(from: dict["flyers"])
                        ?? 0
                    let topLevelConversations = intValue(from: dict["conversations"]) ?? 0
                    let topLevelLeads = intValue(from: dict["leads"]) ?? 0
                    let topLevelDistance = doubleValue(from: dict["distance"]) ?? 0.0
                    let topLevelSnapshot = MetricSnapshot(
                        flyers: intValue(from: dict["flyers"]) ?? topLevelDoorknocks,
                        leads: topLevelLeads,
                        conversations: topLevelConversations,
                        distance: topLevelDistance,
                        doorknocks: topLevelDoorknocks
                    )

                    // Older RPC variants omitted `monthly` and `doorknocks`, but still returned
                    // the current period in the top-level fields. Fall back to that shape.
                    let dailyFallback = timeframe == "daily" ? topLevelSnapshot : MetricSnapshot()
                    let weeklyFallback = timeframe == "weekly" ? topLevelSnapshot : MetricSnapshot()
                    let monthlyFallback = timeframe == "monthly" ? topLevelSnapshot : MetricSnapshot()
                    let allTimeFallback = timeframe == "all_time" ? topLevelSnapshot : MetricSnapshot()

                    let daily = snapshot(from: dict["daily"], fallback: dailyFallback)
                    let weekly = snapshot(from: dict["weekly"], fallback: weeklyFallback)
                    let monthly = snapshot(from: dict["monthly"], fallback: monthlyFallback)
                    let allTime = snapshot(from: dict["all_time"], fallback: allTimeFallback)
                    
                    // Create LeaderboardUser manually to handle JSONB fields
                    return LeaderboardUser(
                        id: dict["id"] as? String ?? "",
                        name: dict["name"] as? String ?? "User",
                        avatarUrl: dict["avatar_url"] as? String,
                        brokerage: dict["brokerage"] as? String,
                        rank: intValue(from: dict["rank"]) ?? 0,
                        doorknocks: topLevelDoorknocks,
                        flyers: intValue(from: dict["flyers"]) ?? topLevelDoorknocks,
                        leads: topLevelLeads,
                        conversations: topLevelConversations,
                        distance: topLevelDistance,
                        daily: daily,
                        weekly: weekly,
                        monthly: monthly,
                        allTime: allTime
                    )
                }
                // #region agent log
                _debugLogLeaderboard(location: "LeaderboardService.fetchLeaderboard", message: "leaderboard result", data: ["userCount": users.count, "timeframe": timeframe, "metric": metric, "userIds": Array(users.prefix(15).map(\.id)), "doorknocksList": Array(users.prefix(15).map(\.doorknocks))], hypothesisId: "H4")
                // #endregion
                print("✅ [LeaderboardService] Successfully fetched \(users.count) users")
                return users
            } else {
                // Fallback to standard decoding
                let users = try decoder.decode([LeaderboardUser].self, from: data)
                print("✅ [LeaderboardService] Successfully fetched \(users.count) users")
                return users
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
                print("❌ [LeaderboardService] RPC call failed:")
                print("   Function: get_leaderboard")
                print("   Params: \(params)")
                print("   Error: \(error)")
                print("   Error type: \(type(of: error))")
            }
            throw error
        }
    }
}
