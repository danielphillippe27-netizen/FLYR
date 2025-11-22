import Foundation

struct LeaderboardUser: Identifiable, Codable {
    let id: String // user_id from Supabase
    let name: String
    let avatarUrl: String?
    let rank: Int
    let flyers: Int
    let leads: Int
    let conversations: Int
    let distance: Double
    let daily: MetricSnapshot
    let weekly: MetricSnapshot
    let allTime: MetricSnapshot
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
        case rank
        case flyers
        case leads
        case conversations
        case distance
        case daily
        case weekly
        case allTime = "all_time"
    }
    
    // Custom initializer for manual construction
    init(
        id: String,
        name: String,
        avatarUrl: String?,
        rank: Int,
        flyers: Int,
        leads: Int,
        conversations: Int,
        distance: Double,
        daily: MetricSnapshot,
        weekly: MetricSnapshot,
        allTime: MetricSnapshot
    ) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.rank = rank
        self.flyers = flyers
        self.leads = leads
        self.conversations = conversations
        self.distance = distance
        self.daily = daily
        self.weekly = weekly
        self.allTime = allTime
    }
    
    // Helper to get value for selected metric and timeframe
    func value(for metric: String, timeframe: String) -> Double {
        let snapshot = snapshot(for: timeframe)
        
        switch metric {
        case "flyers":
            return Double(snapshot.flyers)
        case "doorknocks":
            return Double(snapshot.doorknocks)
        case "leads":
            return Double(snapshot.leads)
        case "distance":
            return snapshot.distance
        case "conversations":
            return Double(snapshot.conversations)
        case "appointments":
            // Placeholder until backend supports appointments
            return 0.0
        case "deals":
            // Placeholder until backend supports deals
            return 0.0
        default:
            return Double(snapshot.flyers)
        }
    }
    
    // Helper to get value for selected metric (uses all_time by default)
    func value(for metric: String) -> Double {
        return value(for: metric, timeframe: "all_time")
    }
    
    // Helper to get formatted value for selected metric
    func formattedValue(for metric: String) -> String {
        switch metric {
        case "flyers":
            return "\(flyers)"
        case "doorknocks":
            let snapshot = allTime
            return "\(snapshot.doorknocks)"
        case "leads":
            return "\(leads)"
        case "conversations":
            return "\(conversations)"
        case "distance":
            return String(format: "%.1f km", distance)
        default:
            return "\(flyers)"
        }
    }
    
    // Helper to get metric snapshot for timeframe
    func snapshot(for timeframe: String) -> MetricSnapshot {
        switch timeframe {
        case "daily":
            return daily
        case "weekly":
            return weekly
        case "monthly":
            // Placeholder: use weekly snapshot until backend supports monthly
            return weekly
        case "all_time":
            return allTime
        default:
            return allTime
        }
    }
}

