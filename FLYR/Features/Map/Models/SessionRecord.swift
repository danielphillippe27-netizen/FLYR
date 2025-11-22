import Foundation
import CoreLocation

/// Session record model for Supabase storage
struct SessionRecord: Codable {
    let id: UUID?
    let user_id: UUID
    let start_time: Date
    let end_time: Date
    let distance_meters: Double
    let goal_type: String
    let goal_amount: Int
    let path_geojson: String
    let created_at: Date?
    let updated_at: Date?
    
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
    }
}

/// Helper data structure for session summary display
struct SessionSummaryData {
    let distance: Double
    let time: TimeInterval
    let goalType: GoalType
    let goalAmount: Int
    let pathCoordinates: [CLLocationCoordinate2D]
}

