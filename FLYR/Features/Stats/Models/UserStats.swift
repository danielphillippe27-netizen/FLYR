import Foundation

struct UserStats: Codable, Identifiable {
    let id: UUID
    let user_id: UUID
    let day_streak: Int
    let best_streak: Int
    let doors_knocked: Int
    let flyers: Int
    let conversations: Int
    let leads_created: Int
    let qr_codes_scanned: Int
    let distance_walked: Double
    let time_tracked: Int
    let conversation_per_door: Double
    let conversation_lead_rate: Double
    let qr_code_scan_rate: Double
    let qr_code_lead_rate: Double
    let streak_days: [String]?
    let xp: Int
    let updated_at: String
    let created_at: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case day_streak
        case best_streak
        case doors_knocked
        case flyers
        case conversations
        case leads_created
        case qr_codes_scanned
        case distance_walked
        case time_tracked
        case conversation_per_door
        case conversation_lead_rate
        case qr_code_scan_rate
        case qr_code_lead_rate
        case streak_days
        case xp
        case updated_at
        case created_at
    }
    
    // Helper computed properties for display
    var formattedDistanceWalked: String {
        String(format: "%.1f", distance_walked)
    }
    
    var formattedConversationPerDoor: String {
        String(format: "%.1f", conversation_per_door)
    }
    
    var formattedTimeTracked: String {
        let hours = time_tracked / 60
        let minutes = time_tracked % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

