import Foundation

struct LeaderboardUser: Identifiable, Codable {
    let id: String // user_id from Supabase
    let name: String
    let avatarUrl: String?
    let brokerage: String?
    let rank: Int
    let doorknocks: Int
    let leads: Int
    let conversations: Int
    let distance: Double
    let daily: MetricSnapshot
    let weekly: MetricSnapshot
    let monthly: MetricSnapshot
    let allTime: MetricSnapshot
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
        case brokerage
        case rank
        case doorknocks
        case leads
        case conversations
        case distance
        case daily
        case weekly
        case monthly
        case allTime = "all_time"
    }
    
    // Custom initializer for manual construction
    init(
        id: String,
        name: String,
        avatarUrl: String?,
        brokerage: String?,
        rank: Int,
        doorknocks: Int,
        leads: Int,
        conversations: Int,
        distance: Double,
        daily: MetricSnapshot,
        weekly: MetricSnapshot,
        monthly: MetricSnapshot,
        allTime: MetricSnapshot
    ) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.brokerage = brokerage
        self.rank = rank
        self.doorknocks = doorknocks
        self.leads = leads
        self.conversations = conversations
        self.distance = distance
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
        self.allTime = allTime
    }
    
    // Helper to get value for selected metric and timeframe
    func value(for metric: String, timeframe: String) -> Double {
        let snapshot = snapshot(for: timeframe)
        
        switch metric {
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
            return Double(snapshot.doorknocks)
        }
    }
    
    // Helper to get value for selected metric (uses all_time by default)
    func value(for metric: String) -> Double {
        return value(for: metric, timeframe: "all_time")
    }
    
    // Helper to get formatted value for selected metric
    func formattedValue(for metric: String) -> String {
        switch metric {
        case "doorknocks":
            return "\(doorknocks)"
        case "leads":
            return "\(leads)"
        case "conversations":
            return "\(conversations)"
        case "distance":
            return String(format: "%.1f km", distance)
        default:
            return "\(doorknocks)"
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
            return monthly
        case "all_time":
            return allTime
        default:
            return allTime
        }
    }
}
