import Foundation

struct LeaderboardEntry: Codable, Identifiable {
    let id: UUID
    let user_id: UUID
    let user_email: String
    let flyers: Int
    let conversations: Int
    let leads: Int
    let distance: Double
    let time_minutes: Int
    let day_streak: Int
    let best_streak: Int
    let rank: Int
    let updated_at: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case user_id
        case user_email
        case flyers
        case conversations
        case leads
        case distance
        case time_minutes
        case day_streak
        case best_streak
        case rank
        case updated_at
    }
    
    var formattedDistance: String {
        String(format: "%.1f km", distance)
    }
    
    var formattedTime: String {
        let hours = time_minutes / 60
        let minutes = time_minutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    func value(for sortBy: LeaderboardSortBy) -> String {
        switch sortBy {
        case .flyers:
            return "\(flyers)"
        case .conversations:
            return "\(conversations)"
        case .leads:
            return "\(leads)"
        case .distance:
            return formattedDistance
        case .time:
            return formattedTime
        }
    }
}

enum LeaderboardSortBy: String, CaseIterable {
    case flyers = "flyers"
    case conversations = "conversations"
    case leads = "leads"
    case distance = "distance"
    case time = "time"
    
    var displayName: String {
        switch self {
        case .flyers: return "Flyers"
        case .conversations: return "Conversations"
        case .leads: return "Leads"
        case .distance: return "Distance"
        case .time: return "Time"
        }
    }
}



