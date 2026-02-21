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
    let appointments: Int
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
        case appointments
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        user_id = try container.decode(UUID.self, forKey: .user_id)
        day_streak = try container.decode(Int.self, forKey: .day_streak)
        best_streak = try container.decode(Int.self, forKey: .best_streak)
        doors_knocked = try container.decode(Int.self, forKey: .doors_knocked)
        flyers = try container.decode(Int.self, forKey: .flyers)
        conversations = try container.decode(Int.self, forKey: .conversations)
        leads_created = try container.decode(Int.self, forKey: .leads_created)
        appointments = (try? container.decodeIfPresent(Int.self, forKey: .appointments)) ?? 0
        qr_codes_scanned = try container.decode(Int.self, forKey: .qr_codes_scanned)
        distance_walked = try container.decode(Double.self, forKey: .distance_walked)
        time_tracked = try container.decode(Int.self, forKey: .time_tracked)
        conversation_per_door = try container.decode(Double.self, forKey: .conversation_per_door)
        conversation_lead_rate = try container.decode(Double.self, forKey: .conversation_lead_rate)
        qr_code_scan_rate = try container.decode(Double.self, forKey: .qr_code_scan_rate)
        qr_code_lead_rate = try container.decode(Double.self, forKey: .qr_code_lead_rate)
        streak_days = try container.decodeIfPresent([String].self, forKey: .streak_days)
        xp = try container.decode(Int.self, forKey: .xp)
        updated_at = try container.decode(String.self, forKey: .updated_at)
        created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(day_streak, forKey: .day_streak)
        try container.encode(best_streak, forKey: .best_streak)
        try container.encode(doors_knocked, forKey: .doors_knocked)
        try container.encode(flyers, forKey: .flyers)
        try container.encode(conversations, forKey: .conversations)
        try container.encode(leads_created, forKey: .leads_created)
        try container.encode(appointments, forKey: .appointments)
        try container.encode(qr_codes_scanned, forKey: .qr_codes_scanned)
        try container.encode(distance_walked, forKey: .distance_walked)
        try container.encode(time_tracked, forKey: .time_tracked)
        try container.encode(conversation_per_door, forKey: .conversation_per_door)
        try container.encode(conversation_lead_rate, forKey: .conversation_lead_rate)
        try container.encode(qr_code_scan_rate, forKey: .qr_code_scan_rate)
        try container.encode(qr_code_lead_rate, forKey: .qr_code_lead_rate)
        try container.encodeIfPresent(streak_days, forKey: .streak_days)
        try container.encode(xp, forKey: .xp)
        try container.encode(updated_at, forKey: .updated_at)
        try container.encodeIfPresent(created_at, forKey: .created_at)
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

