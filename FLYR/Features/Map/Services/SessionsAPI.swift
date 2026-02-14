import Foundation
import Supabase

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

    /// Create a new building-tracking session (session recording feature)
    func createSession(
        id: UUID,
        userId: UUID,
        campaignId: UUID,
        targetBuildingIds: [String],
        autoCompleteEnabled: Bool,
        thresholdMeters: Double,
        dwellSeconds: Int,
        notes: String? = nil
    ) async throws {
        let emptyPath = "{\"type\":\"LineString\",\"coordinates\":[]}"
        var data: [String: AnyCodable] = [
            "id": AnyCodable(id.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "campaign_id": AnyCodable(campaignId.uuidString),
            "start_time": AnyCodable(ISO8601DateFormatter().string(from: Date())),
            "distance_meters": AnyCodable(0),
            "goal_type": AnyCodable("knocks"),
            "goal_amount": AnyCodable(targetBuildingIds.count),
            "path_geojson": AnyCodable(emptyPath),
            "target_building_ids": AnyCodable(targetBuildingIds),
            "completed_count": AnyCodable(0),
            "auto_complete_enabled": AnyCodable(autoCompleteEnabled),
            "auto_complete_threshold_m": AnyCodable(thresholdMeters),
            "auto_complete_dwell_seconds": AnyCodable(dwellSeconds),
        ]
        if let notes = notes, !notes.isEmpty {
            data["notes"] = AnyCodable(notes)
        }
        // end_time left null for active session
        _ = try await client
            .from("sessions")
            .insert(data)
            .execute()
    }

    /// Update an existing session (path, completed count, end time, etc.)
    func updateSession(
        id: UUID,
        completedCount: Int? = nil,
        distanceM: Double? = nil,
        activeSeconds: Int? = nil,
        pathGeoJSON: String? = nil,
        isPaused: Bool? = nil,
        endTime: Date? = nil
    ) async throws {
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
            .is("end_time", value: true)  // IS NULL for active sessions
            .order("start_time", ascending: false)
            .limit(1)
            .execute()
        let decoder = JSONDecoder.supabaseDates
        let sessions = try decoder.decode([SessionRecord].self, from: response.data)
        return sessions.first
    }
}

