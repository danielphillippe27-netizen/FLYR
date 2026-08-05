import Foundation
import CoreLocation
import UIKit

/// Session record model for Supabase storage
struct SessionRecord: Codable {
    let id: UUID?
    let user_id: UUID
    let start_time: Date
    let end_time: Date?  // null when session is still active
    let doors_hit: Int?
    let distance_meters: Double?
    let conversations: Int?
    let session_mode: String?
    let goal_type: String?
    let goal_amount: Int?
    let path_geojson: String?
    let path_geojson_normalized: String?
    let active_seconds: Int?
    let created_at: Date?
    let updated_at: Date?
    let campaign_id: UUID?
    let farm_id: UUID?
    let farm_touch_id: UUID?
    /// Present when the session was started from a route assignment (Record tab / route scope).
    let route_assignment_id: UUID?
    let target_building_ids: [String]?
    let completed_count: Int?
    let flyers_delivered: Int?
    let is_paused: Bool?
    let auto_complete_enabled: Bool?
    let notes: String?
    let doors_per_hour: Double?
    let conversations_per_hour: Double?
    let completions_per_km: Double?
    let appointments_count: Int?
    let appointments_per_conversation: Double?
    let leads_created: Int?
    let conversations_per_door: Double?
    let leads_per_conversation: Double?

    /// Doors count for display: prefer flyers_delivered (set when ending session) then completed_count.
    var doorsCount: Int {
        (doors_hit ?? flyers_delivered ?? completed_count ?? 0)
    }

    /// Duration in seconds (from start to end, or 0 if no end).
    var durationSeconds: TimeInterval {
        if let active_seconds, active_seconds > 0 {
            return TimeInterval(active_seconds)
        }
        let end = end_time ?? start_time
        return end.timeIntervalSince(start_time)
    }

    var doorsPerHour: Double {
        if let doors_per_hour {
            return doors_per_hour
        }
        guard durationSeconds > 0 else { return 0 }
        return Double(doorsCount) / (durationSeconds / 3600.0)
    }

    var conversationsPerHour: Double {
        if let conversations_per_hour {
            return conversations_per_hour
        }
        let conversationsCount = max(0, conversations ?? 0)
        guard durationSeconds > 0 else { return 0 }
        return Double(conversationsCount) / (durationSeconds / 3600.0)
    }

    var completionsPerKm: Double {
        if let completions_per_km {
            return completions_per_km
        }
        let distanceKm = max(0, distance_meters ?? 0) / 1000.0
        guard distanceKm > 0 else { return 0 }
        return Double(doorsCount) / distanceKm
    }

    var appointmentsCount: Int {
        max(0, appointments_count ?? 0)
    }

    var appointmentsPerConversation: Double {
        if let appointments_per_conversation {
            return appointments_per_conversation
        }
        let conversationCount = max(0, conversations ?? 0)
        guard conversationCount > 0 else { return 0 }
        return Double(appointmentsCount) / Double(conversationCount)
    }

    var leadsCreated: Int {
        max(0, leads_created ?? 0)
    }

    var conversationsPerDoor: Double {
        if let conversations_per_door {
            return conversations_per_door
        }
        let doors = doorsCount
        guard doors > 0 else { return 0 }
        return Double(max(0, conversations ?? 0)) / Double(doors)
    }

    var leadsPerConversation: Double {
        if let leads_per_conversation {
            return leads_per_conversation
        }
        let conversationCount = max(0, conversations ?? 0)
        guard conversationCount > 0 else { return 0 }
        return Double(leadsCreated) / Double(conversationCount)
    }

    var goalTypeValue: GoalType {
        GoalType(rawValue: goal_type ?? GoalType.knocks.rawValue) ?? .knocks
    }

    var sessionModeValue: SessionMode {
        if let session_mode, let mode = SessionMode(rawValue: session_mode) {
            return mode
        }
        return goalTypeValue == .flyers ? .flyer : .doorKnocking
    }

    var isNetworkingSession: Bool {
        campaign_id == nil && (target_building_ids?.isEmpty ?? true) && goalTypeValue == .time
    }

    /// Build summary data for share card / end-session UI.
    func toSummaryData() -> SessionSummaryData {
        return SessionSummaryData(
            distance: distance_meters ?? 0,
            time: durationSeconds,
            goalType: goalTypeValue,
            goalAmount: goal_amount ?? 0,
            pathCoordinates: decodedPathCoordinates(),
            renderedPathSegments: nil,
            completedCount: doorsCount,
            conversationsCount: conversations,
            leadsCreatedCount: leadsCreated,
            startTime: start_time,
            isNetworkingSession: isNetworkingSession,
            isDemoSession: false
        )
    }

    /// Decoded breadcrumb path from stored GeoJSON. Prefers normalized path when present (Pro GPS).
    var pathCoordinates: [CLLocationCoordinate2D] {
        decodedPathCoordinates()
    }

    private func decodedPathCoordinates() -> [CLLocationCoordinate2D] {
        if let coords = decodePathGeoJSON(path_geojson_normalized), !coords.isEmpty {
            return coords
        }
        return decodePathGeoJSON(path_geojson) ?? []
    }

    private func decodePathGeoJSON(_ json: String?) -> [CLLocationCoordinate2D]? {
        guard let path_geojson = json,
              let data = path_geojson.data(using: .utf8),
              let line = try? JSONDecoder().decode(PathGeoJSON.self, from: data),
              line.type.lowercased() == "linestring" else {
            return nil
        }
        return line.coordinates.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case start_time
        case end_time
        case doors_hit
        case distance_meters
        case conversations
        case session_mode
        case goal_type
        case goal_amount
        case path_geojson
        case path_geojson_normalized
        case active_seconds
        case created_at
        case updated_at
        case campaign_id
        case farm_id
        case farm_touch_id
        case route_assignment_id
        case target_building_ids
        case completed_count
        case flyers_delivered
        case is_paused
        case auto_complete_enabled
        case notes
        case doors_per_hour
        case conversations_per_hour
        case completions_per_km
        case appointments_count
        case appointments_per_conversation
        case leads_created
        case conversations_per_door
        case leads_per_conversation
    }
}

private struct PathGeoJSON: Decodable {
    let type: String
    let coordinates: [[Double]]
}

/// Helper data structure for session summary display (Strava-style end session)
struct SessionSummaryData: Equatable {
    let distance: Double
    let time: TimeInterval
    let goalType: GoalType
    let goalAmount: Int
    let pathCoordinates: [CLLocationCoordinate2D]
    let renderedPathSegments: [[CLLocationCoordinate2D]]?
    let completedHomeCoordinates: [CLLocationCoordinate2D]
    /// For building sessions: doors completed (captured before manager clears)
    let completedCount: Int?
    /// Conversations had this session (from SessionManager.conversationsHad).
    let conversationsCount: Int?
    /// Leads created this session.
    let leadsCreatedCount: Int?
    let startTime: Date?
    let isNetworkingSession: Bool
    /// When true (demo session), share-card map omits route/home vector overlays.
    let isDemoSession: Bool

    init(
        distance: Double,
        time: TimeInterval,
        goalType: GoalType,
        goalAmount: Int,
        pathCoordinates: [CLLocationCoordinate2D],
        renderedPathSegments: [[CLLocationCoordinate2D]]?,
        completedHomeCoordinates: [CLLocationCoordinate2D] = [],
        completedCount: Int?,
        conversationsCount: Int?,
        leadsCreatedCount: Int? = nil,
        startTime: Date?,
        isNetworkingSession: Bool = false,
        isDemoSession: Bool = false
    ) {
        self.distance = distance
        self.time = time
        self.goalType = goalType
        self.goalAmount = goalAmount
        self.pathCoordinates = pathCoordinates
        self.renderedPathSegments = renderedPathSegments
        self.completedHomeCoordinates = completedHomeCoordinates
        self.completedCount = completedCount
        self.conversationsCount = conversationsCount
        self.leadsCreatedCount = leadsCreatedCount
        self.startTime = startTime
        self.isNetworkingSession = isNetworkingSession
        self.isDemoSession = isDemoSession
    }

    // MARK: - Strava-style share formatting

    /// Doors = count of completed door attempts this session. TODO: derive from SessionEvent/Visit (status != skipped or didAttempt) when available.
    var doorsCount: Int { completedCount ?? 0 }

    /// Conversations count for share card.
    var conversations: Int { conversationsCount ?? 0 }

    var leadsCreated: Int { leadsCreatedCount ?? 0 }

    var displayRouteSegments: [[CLLocationCoordinate2D]] {
        let rendered = (renderedPathSegments ?? []).filter { $0.count >= 2 }
        if !rendered.isEmpty {
            return rendered
        }
        return pathCoordinates.count >= 2 ? [pathCoordinates] : []
    }

    /// Whether the full-bleed homes + route share card should be shown (map line and/or home pins).
    var includesHomesRouteShareCard: Bool {
        !displayRouteSegments.isEmpty || !completedHomeCoordinates.isEmpty
    }

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

    func withRenderedPathSegments(_ segments: [[CLLocationCoordinate2D]]?) -> SessionSummaryData {
        SessionSummaryData(
            distance: distance,
            time: time,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            renderedPathSegments: segments,
            completedHomeCoordinates: completedHomeCoordinates,
            completedCount: completedCount,
            conversationsCount: conversationsCount,
            leadsCreatedCount: leadsCreatedCount,
            startTime: startTime,
            isNetworkingSession: isNetworkingSession,
            isDemoSession: isDemoSession
        )
    }

    func withCompletedHomeCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> SessionSummaryData {
        SessionSummaryData(
            distance: distance,
            time: time,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            renderedPathSegments: renderedPathSegments,
            completedHomeCoordinates: coordinates,
            completedCount: completedCount,
            conversationsCount: conversationsCount,
            leadsCreatedCount: leadsCreatedCount,
            startTime: startTime,
            isNetworkingSession: isNetworkingSession,
            isDemoSession: isDemoSession
        )
    }

    func withIsNetworkingSession(_ value: Bool) -> SessionSummaryData {
        SessionSummaryData(
            distance: distance,
            time: time,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            renderedPathSegments: renderedPathSegments,
            completedHomeCoordinates: completedHomeCoordinates,
            completedCount: completedCount,
            conversationsCount: conversationsCount,
            leadsCreatedCount: leadsCreatedCount,
            startTime: startTime,
            isNetworkingSession: value,
            isDemoSession: isDemoSession
        )
    }

    func withIsDemoSession(_ value: Bool) -> SessionSummaryData {
        SessionSummaryData(
            distance: distance,
            time: time,
            goalType: goalType,
            goalAmount: goalAmount,
            pathCoordinates: pathCoordinates,
            renderedPathSegments: renderedPathSegments,
            completedHomeCoordinates: completedHomeCoordinates,
            completedCount: completedCount,
            conversationsCount: conversationsCount,
            leadsCreatedCount: leadsCreatedCount,
            startTime: startTime,
            isNetworkingSession: isNetworkingSession,
            isDemoSession: value
        )
    }
}

/// Identifiable wrapper so we can drive fullScreenCover(item:) from a single optional (bulletproof presentation).
/// Stable id from data so the same summary never gets two identities (fixes cover dismissing when both onChange and onReceive fire).
struct EndSessionSummaryItem: Identifiable {
    var id: String {
        if let sessionID {
            return sessionID.uuidString
        }
        return "\(data.distance)-\(data.time)-\(data.doorsCount)-\(data.conversations)"
    }
    let data: SessionSummaryData
    let sessionID: UUID?
    /// Live `CampaignMapView` capture at session end; preferred over Mapbox static for the homes share card.
    let campaignMapSnapshot: UIImage?
    init(data: SessionSummaryData, sessionID: UUID?, campaignMapSnapshot: UIImage? = nil) {
        self.data = data
        self.sessionID = sessionID
        self.campaignMapSnapshot = campaignMapSnapshot
    }
}
