import Foundation

struct LeaderboardUser: Identifiable, Codable {
    let id: String // user_id from Supabase
    let name: String
    let avatarUrl: String?
    let countryCode: String?
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
    let pending: MetricSnapshot
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
        case countryCode = "country_code"
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
        case pending
    }
    
    // Custom initializer for manual construction
    init(
        id: String,
        name: String,
        avatarUrl: String?,
        countryCode: String?,
        brokerage: String?,
        rank: Int,
        doorknocks: Int,
        leads: Int,
        conversations: Int,
        distance: Double,
        daily: MetricSnapshot,
        weekly: MetricSnapshot,
        monthly: MetricSnapshot,
        allTime: MetricSnapshot,
        pending: MetricSnapshot = MetricSnapshot()
    ) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
        self.countryCode = countryCode
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
        self.pending = pending
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "User"
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode)
        brokerage = try container.decodeIfPresent(String.self, forKey: .brokerage)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        doorknocks = try container.decodeIfPresent(Int.self, forKey: .doorknocks) ?? 0
        leads = try container.decodeIfPresent(Int.self, forKey: .leads) ?? 0
        conversations = try container.decodeIfPresent(Int.self, forKey: .conversations) ?? 0
        distance = try container.decodeIfPresent(Double.self, forKey: .distance) ?? 0.0

        let topLevelSnapshot = MetricSnapshot(
            leads: leads,
            conversations: conversations,
            distance: distance,
            doorknocks: doorknocks
        )
        daily = try container.decodeIfPresent(MetricSnapshot.self, forKey: .daily) ?? topLevelSnapshot
        weekly = try container.decodeIfPresent(MetricSnapshot.self, forKey: .weekly) ?? topLevelSnapshot
        monthly = try container.decodeIfPresent(MetricSnapshot.self, forKey: .monthly) ?? topLevelSnapshot
        allTime = try container.decodeIfPresent(MetricSnapshot.self, forKey: .allTime) ?? topLevelSnapshot
        pending = try container.decodeIfPresent(MetricSnapshot.self, forKey: .pending) ?? MetricSnapshot()
    }

    var countryFlag: String {
        CountryOptions.flag(for: countryCode)
    }
    
    // Helper to get value for selected metric and timeframe
    func value(for metric: String, timeframe: String) -> Double {
        let snapshot = snapshot(for: timeframe)
        
        return snapshot.value(for: metric)
    }
    
    // Helper to get value for selected metric (uses all_time by default)
    func value(for metric: String) -> Double {
        return value(for: metric, timeframe: "all_time")
    }

    func pendingValue(for metric: String) -> Double {
        return pending.value(for: metric)
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
