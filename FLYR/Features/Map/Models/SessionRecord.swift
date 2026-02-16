import Foundation
import CoreLocation

/// Session record model for Supabase storage
struct SessionRecord: Codable {
    let id: UUID?
    let user_id: UUID
    let start_time: Date
    let end_time: Date?  // null when session is still active
    let distance_meters: Double?
    let goal_type: String?
    let goal_amount: Int?
    let path_geojson: String?
    let created_at: Date?
    let updated_at: Date?
    let campaign_id: UUID?
    let target_building_ids: [String]?
    let completed_count: Int?
    let flyers_delivered: Int?
    let is_paused: Bool?
    let auto_complete_enabled: Bool?
    let notes: String?

    /// Doors count for display: prefer flyers_delivered (set when ending session) then completed_count.
    var doorsCount: Int {
        (flyers_delivered ?? completed_count ?? 0)
    }

    /// Duration in seconds (from start to end, or 0 if no end).
    var durationSeconds: TimeInterval {
        let end = end_time ?? start_time
        return end.timeIntervalSince(start_time)
    }

    /// Build summary data for share card / end-session UI. Path and conversations are not stored on record so omitted.
    func toSummaryData() -> SessionSummaryData {
        let goal = GoalType(rawValue: goal_type ?? GoalType.flyers.rawValue) ?? .flyers
        return SessionSummaryData(
            distance: distance_meters ?? 0,
            time: durationSeconds,
            goalType: goal,
            goalAmount: goal_amount ?? 0,
            pathCoordinates: [],
            completedCount: doorsCount,
            conversationsCount: nil,
            startTime: start_time
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case start_time
        case end_time
        case distance_meters
        case goal_type
        case goal_amount
        case path_geojson
        case created_at
        case updated_at
        case campaign_id
        case target_building_ids
        case completed_count
        case flyers_delivered
        case is_paused
        case auto_complete_enabled
        case notes
    }
}

/// Helper data structure for session summary display (Strava-style end session)
struct SessionSummaryData: Equatable {
    let distance: Double
    let time: TimeInterval
    let goalType: GoalType
    let goalAmount: Int
    let pathCoordinates: [CLLocationCoordinate2D]
    /// For building sessions: doors completed (captured before manager clears)
    let completedCount: Int?
    /// Conversations had this session (from SessionManager.conversationsHad).
    let conversationsCount: Int?
    let startTime: Date?

    // MARK: - Strava-style share formatting

    /// Doors = count of completed door attempts this session. TODO: derive from SessionEvent/Visit (status != skipped or didAttempt) when available.
    var doorsCount: Int { completedCount ?? 0 }

    /// Conversations count for share card.
    var conversations: Int { conversationsCount ?? 0 }

    /// Distance string e.g. "14.00 km"
    var formattedDistance: String { String(format: "%.2f km", distance / 1000.0) }

    /// Time string e.g. "1h 11m" or "23m 0s"
    var formattedTimeStrava: String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        }
        return String(format: "%ds", seconds)
    }
}

/// Identifiable wrapper so we can drive fullScreenCover(item:) from a single optional (bulletproof presentation).
/// Stable id from data so the same summary never gets two identities (fixes cover dismissing when both onChange and onReceive fire).
struct EndSessionSummaryItem: Identifiable {
    var id: String { "\(data.distance)-\(data.time)-\(data.doorsCount)-\(data.conversations)" }
    let data: SessionSummaryData
}

