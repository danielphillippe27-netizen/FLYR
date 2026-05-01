import Foundation
import Supabase

// #region agent log
#if DEBUG
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
private func _debugLogDoorsAPI(location: String, message: String, data: [String: Any], hypothesisId: String) {}
#endif
// #endregion

/// API service for fetching and mutating user sessions
@MainActor
final class SessionsAPI {
    static let shared = SessionsAPI()
    private let client = SupabaseManager.shared.client

    private struct SessionCampaignWorkspaceRow: Decodable {
        let workspaceId: UUID?

        enum CodingKeys: String, CodingKey {
            case workspaceId = "workspace_id"
        }
    }

    private init() {}

    private func isMissingRouteAssignmentColumn(_ error: Error) -> Bool {
        if let postgrestError = error as? PostgrestError {
            let message = postgrestError.message.lowercased()
            if postgrestError.code == "PGRST204" && message.contains("route_assignment_id") {
                return true
            }
            if message.contains("route_assignment_id")
                && (message.contains("schema cache") || message.contains("could not find the")) {
                return true
            }
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("route_assignment_id")
            && (message.contains("schema cache") || message.contains("could not find the"))
    }

    private func isMissingFarmExecutionColumn(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("farm_id")
            || message.contains("farm_touch_id")
            || message.contains("cycle_number")
    }

    /// Prefer the campaign's workspace to avoid leaking the caller's current workspace into
    /// cross-workspace collaboration sessions.
    func resolveWorkspaceId(
        forCampaignId campaignId: UUID?,
        preferredWorkspaceId: UUID?
    ) async -> UUID? {
        guard let campaignId else { return preferredWorkspaceId }

        do {
            let response: PostgrestResponse<SessionCampaignWorkspaceRow> = try await client
                .from("campaigns")
                .select("workspace_id")
                .eq("id", value: campaignId.uuidString)
                .single()
                .execute()
            return response.value.workspaceId ?? preferredWorkspaceId
        } catch {
            print("⚠️ [SessionsAPI] Failed to resolve campaign workspace for session insert: \(error)")
            return preferredWorkspaceId
        }
    }

    /// Fetch user sessions ordered by start time (most recent first)
    /// - Parameters:
    ///   - userId: The user ID to fetch sessions for
    ///   - limit: Maximum number of sessions to return (default: 20)
    /// - Returns: Array of session records
    func fetchUserSessions(userId: UUID, limit: Int = 20) async throws -> [SessionRecord] {
        let response = try await client
            .from("session_analytics")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("start_time", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder.supabaseDates
        let sessions = try decoder.decode([SessionRecord].self, from: response.data)
        return sessions
    }

    /// Fetch sessions for a campaign.
    /// When a workspace is provided, fetch workspace-visible campaign activity.
    /// Otherwise fall back to the current user's activity.
    /// - Parameters:
    ///   - campaignId: The campaign ID to filter by
    ///   - userId: The user ID to filter by when no workspace is available
    ///   - workspaceId: Optional workspace scope for shared campaign activity
    ///   - limit: Maximum number of sessions to return (default: 20)
    /// - Returns: Array of session records ordered by start_time descending
    func fetchSessionsForCampaign(
        campaignId: UUID,
        userId: UUID? = nil,
        workspaceId: UUID? = nil,
        limit: Int = 20
    ) async throws -> [SessionRecord] {
        var query = client
            .from("session_analytics")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)

        if let workspaceId {
            query = query.eq("workspace_id", value: workspaceId.uuidString)
        } else if let userId {
            query = query.eq("user_id", value: userId.uuidString)
        } else {
            return []
        }

        let response = try await query
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
        campaignId: UUID?,
        targetBuildingIds: [String],
        autoCompleteEnabled: Bool,
        thresholdMeters: Double,
        dwellSeconds: Int,
        notes: String? = nil,
        workspaceId: UUID? = nil,
        goalType: GoalType = .knocks,
        goalAmount: Int? = nil,
        sessionMode: SessionMode = .doorKnocking,
        routeAssignmentId: UUID? = nil,
        farmExecutionContext: FarmExecutionContext? = nil,
        startedAt: Date? = nil
    ) async throws {
        let emptyPath = "{\"type\":\"LineString\",\"coordinates\":[]}"
        let resolvedWorkspaceId = await resolveWorkspaceId(
            forCampaignId: campaignId,
            preferredWorkspaceId: workspaceId
        )
        let boundedGoalAmount: Int = {
            if let goalAmount, goalAmount <= 0 {
                return 0
            }
            let resolvedGoalAmount = goalAmount ?? goalType.defaultAmount(for: sessionMode, targetCount: targetBuildingIds.count)
            return goalType.normalizedAmount(
                resolvedGoalAmount,
                for: sessionMode,
                targetCount: targetBuildingIds.count
            )
        }()
        var data: [String: AnyCodable] = [
            "id": AnyCodable(id.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "start_time": AnyCodable(ISO8601DateFormatter().string(from: startedAt ?? Date())),
            "doors_hit": AnyCodable(0),
            "distance_meters": AnyCodable(0),
            "session_mode": AnyCodable(sessionMode.rawValue),
            "goal_type": AnyCodable(goalType.rawValue),
            "goal_amount": AnyCodable(boundedGoalAmount),
            "path_geojson": AnyCodable(emptyPath),
            "target_building_ids": AnyCodable(targetBuildingIds),
            "completed_count": AnyCodable(0),
            "flyers_delivered": AnyCodable(0),
            "conversations": AnyCodable(0),
            "leads_created": AnyCodable(0),
            "auto_complete_enabled": AnyCodable(autoCompleteEnabled),
            "auto_complete_threshold_m": AnyCodable(thresholdMeters),
            "auto_complete_dwell_seconds": AnyCodable(dwellSeconds),
        ]
        if let campaignId {
            data["campaign_id"] = AnyCodable(campaignId.uuidString)
        }
        if let workspaceId = resolvedWorkspaceId {
            data["workspace_id"] = AnyCodable(workspaceId.uuidString)
        }
        if let notes = notes, !notes.isEmpty {
            data["notes"] = AnyCodable(notes)
        }
        if let routeAssignmentId {
            data["route_assignment_id"] = AnyCodable(routeAssignmentId.uuidString)
        }
        if let farmExecutionContext {
            data["farm_id"] = AnyCodable(farmExecutionContext.farmId.uuidString)
            data["farm_touch_id"] = AnyCodable(farmExecutionContext.touchId.uuidString)
        }

        do {
            // end_time left null for active session
            _ = try await client
                .from("sessions")
                .upsert(data, onConflict: "id")
                .execute()
        } catch {
            if routeAssignmentId != nil, isMissingRouteAssignmentColumn(error) {
                print("⚠️ [SessionsAPI] sessions.route_assignment_id missing on backend; retrying session insert without route assignment linkage")
                data.removeValue(forKey: "route_assignment_id")
                _ = try await client
                    .from("sessions")
                    .upsert(data, onConflict: "id")
                    .execute()
                return
            }

            guard farmExecutionContext != nil, isMissingFarmExecutionColumn(error) else {
                throw error
            }

            print("⚠️ [SessionsAPI] farm execution columns missing on backend; retrying session insert without farm linkage")
            data.removeValue(forKey: "farm_id")
            data.removeValue(forKey: "farm_touch_id")
            _ = try await client
                .from("sessions")
                .upsert(data, onConflict: "id")
                .execute()
        }
    }

    /// Update an existing session (path, completed count, end time, flyers_delivered, etc.)
    /// flyers_delivered and conversations are used by the leaderboard; include them when ending a building session.
    func updateSession(
        id: UUID,
        completedCount: Int? = nil,
        distanceM: Double? = nil,
        activeSeconds: Int? = nil,
        pathGeoJSON: String? = nil,
        pathGeoJSONNormalized: String? = nil,
        flyersDelivered: Int? = nil,
        conversations: Int? = nil,
        leadsCreated: Int? = nil,
        appointmentsCount: Int? = nil,
        doorsHit: Int? = nil,
        autoCompleteEnabled: Bool? = nil,
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
        if let pathGeoJSONNormalized = pathGeoJSONNormalized {
            data["path_geojson_normalized"] = AnyCodable(pathGeoJSONNormalized)
        }
        if let flyersDelivered = flyersDelivered {
            data["flyers_delivered"] = AnyCodable(flyersDelivered)
        }
        if let conversations = conversations {
            data["conversations"] = AnyCodable(conversations)
        }
        if let leadsCreated = leadsCreated {
            data["leads_created"] = AnyCodable(leadsCreated)
        }
        // `appointments_count` is derived in analytics/user-stats paths and is not
        // part of the canonical `public.sessions` table contract.
        _ = appointmentsCount
        if let doorsHit = doorsHit ?? flyersDelivered ?? completedCount {
            data["doors_hit"] = AnyCodable(doorsHit)
        }
        if let autoCompleteEnabled = autoCompleteEnabled {
            data["auto_complete_enabled"] = AnyCodable(autoCompleteEnabled)
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
