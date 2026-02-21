import Foundation
import Supabase

// #region agent log
private func _debugLogDoorsAPI(location: String, message: String, data: [String: Any], hypothesisId: String) {
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
    let path = "/Users/danielphillippe/Desktop/FLYR IOS/.cursor/debug.log"
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
// #endregion

/// API service for fetching and mutating user sessions
@MainActor
final class SessionsAPI {
    static let shared = SessionsAPI()
    private let client = SupabaseManager.shared.client

    private init() {}

    /// Fetch user sessions ordered by start time (most recent first)
    /// - Parameters:
    ///   - userId: The user ID to fetch sessions for
    ///   - limit: Maximum number of sessions to return (default: 20)
    /// - Returns: Array of session records
    func fetchUserSessions(userId: UUID, limit: Int = 20) async throws -> [SessionRecord] {
        let response = try await client
            .from("sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("start_time", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder.supabaseDates
        let sessions = try decoder.decode([SessionRecord].self, from: response.data)
        return sessions
    }

    /// Fetch sessions for a campaign (current user's activity in that campaign)
    /// - Parameters:
    ///   - campaignId: The campaign ID to filter by
    ///   - userId: The user ID to filter by
    ///   - limit: Maximum number of sessions to return (default: 20)
    /// - Returns: Array of session records ordered by start_time descending
    func fetchSessionsForCampaign(campaignId: UUID, userId: UUID, limit: Int = 20) async throws -> [SessionRecord] {
        let response = try await client
            .from("sessions")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .order("start_time", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder.supabaseDates
        let sessions = try decoder.decode([SessionRecord].self, from: response.data)
        return sessions
    }

    /// Create a new building-tracking session (session recording feature)
    func createSession(
        id: UUID,
        userId: UUID,
        campaignId: UUID,
        targetBuildingIds: [String],
        autoCompleteEnabled: Bool,
        thresholdMeters: Double,
        dwellSeconds: Int,
        notes: String? = nil,
        workspaceId: UUID? = nil,
        goalType: GoalType = .knocks
    ) async throws {
        let emptyPath = "{\"type\":\"LineString\",\"coordinates\":[]}"
        var data: [String: AnyCodable] = [
            "id": AnyCodable(id.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "campaign_id": AnyCodable(campaignId.uuidString),
            "start_time": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "doors_hit": AnyCodable(0),
            "distance_meters": AnyCodable(0),
            "goal_type": AnyCodable(goalType.rawValue),
            "goal_amount": AnyCodable(targetBuildingIds.count),
            "path_geojson": AnyCodable(emptyPath),
            "target_building_ids": AnyCodable(targetBuildingIds),
            "completed_count": AnyCodable(0),
            "flyers_delivered": AnyCodable(0),
            "conversations": AnyCodable(0),
            "auto_complete_enabled": AnyCodable(autoCompleteEnabled),
            "auto_complete_threshold_m": AnyCodable(thresholdMeters),
            "auto_complete_dwell_seconds": AnyCodable(dwellSeconds),
        ]
        if let workspaceId = workspaceId {
            data["workspace_id"] = AnyCodable(workspaceId.uuidString)
        }
        if let notes = notes, !notes.isEmpty {
            data["notes"] = AnyCodable(notes)
        }
        // end_time left null for active session
        _ = try await client
            .from("sessions")
            .insert(data)
            .execute()
    }

    /// Update an existing session (path, completed count, end time, flyers_delivered, etc.)
    /// flyers_delivered and conversations are used by the leaderboard; include them when ending a building session.
    func updateSession(
        id: UUID,
        completedCount: Int? = nil,
        distanceM: Double? = nil,
        activeSeconds: Int? = nil,
        pathGeoJSON: String? = nil,
        flyersDelivered: Int? = nil,
        conversations: Int? = nil,
        doorsHit: Int? = nil,
        isPaused: Bool? = nil,
        endTime: Date? = nil
    ) async throws {
        // #region agent log
        _debugLogDoorsAPI(location: "SessionsAPI.updateSession", message: "params", data: ["id": id.uuidString, "flyersDelivered": flyersDelivered as Any, "conversations": conversations as Any, "endTime": endTime != nil], hypothesisId: "H3")
        // #endregion
        var data: [String: AnyCodable] = [:]
        if let completedCount = completedCount {
            data["completed_count"] = AnyCodable(completedCount)
        }
        if let distanceM = distanceM {
            data["distance_meters"] = AnyCodable(distanceM)
        }
        if let activeSeconds = activeSeconds {
            data["active_seconds"] = AnyCodable(activeSeconds)
        }
        if let pathGeoJSON = pathGeoJSON {
            data["path_geojson"] = AnyCodable(pathGeoJSON)
        }
        if let flyersDelivered = flyersDelivered {
            data["flyers_delivered"] = AnyCodable(flyersDelivered)
        }
        if let conversations = conversations {
            data["conversations"] = AnyCodable(conversations)
        }
        if let doorsHit = doorsHit ?? flyersDelivered ?? completedCount {
            data["doors_hit"] = AnyCodable(doorsHit)
        }
        if let isPaused = isPaused {
            data["is_paused"] = AnyCodable(isPaused)
        }
        if let endTime = endTime {
            data["end_time"] = AnyCodable(ISO8601DateFormatter().string(from: endTime))
        }
        guard !data.isEmpty else { return }
        _ = try await client
            .from("sessions")
            .update(data)
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Fetch active (unended) session for current user for restore-after-kill
    func fetchActiveSession(userId: UUID) async throws -> SessionRecord? {
        let response = try await client
            .from("sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .is("end_time", value: nil)  // IS NULL for active sessions
            .order("start_time", ascending: false)
            .limit(1)
            .execute()
        let decoder = JSONDecoder.supabaseDates
        let sessions = try decoder.decode([SessionRecord].self, from: response.data)
        return sessions.first
    }
}
