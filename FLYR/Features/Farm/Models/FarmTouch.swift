import Foundation

/// Type of farm touch
enum FarmTouchType: String, Codable, CaseIterable, Identifiable {
    case flyer = "flyer"
    case doorKnock = "door_knock"
    case event = "event"
    case newsletter = "newsletter"
    case ad = "ad"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .flyer: return "Flyer"
        case .doorKnock: return "Door Knock"
        case .event: return "Event"
        case .newsletter: return "Newsletter"
        case .ad: return "Ad"
        case .custom: return "Custom"
        }
    }
    
    var iconName: String {
        switch self {
        case .flyer: return "paperplane.fill"
        case .doorKnock: return "door.left.hand.open"
        case .event: return "calendar"
        case .newsletter: return "envelope.fill"
        case .ad: return "megaphone.fill"
        case .custom: return "star.fill"
        }
    }
    
    var colorName: String {
        switch self {
        case .flyer: return "blue"
        case .doorKnock: return "green"
        case .event: return "orange"
        case .newsletter: return "purple"
        case .ad: return "yellow"
        case .custom: return "gray"
        }
    }
}

/// Farm touch model representing a planned or executed touch
struct FarmTouch: Identifiable, Codable, Equatable {
    let id: UUID
    let farmId: UUID
    let date: Date
    let type: FarmTouchType
    let title: String
    let notes: String?
    let orderIndex: Int?
    let completed: Bool
    let campaignId: UUID?
    let batchId: UUID?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case date
        case type
        case title
        case notes
        case orderIndex = "order_index"
        case completed
        case campaignId = "campaign_id"
        case batchId = "batch_id"
        case createdAt = "created_at"
    }
    
    /// Custom date decoder for date-only fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        farmId = try container.decode(UUID.self, forKey: .farmId)
        
        // Decode date (can be date-only string or full timestamp)
        if let dateString = try? container.decode(String.self, forKey: .date) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            if let dateValue = dateFormatter.date(from: dateString) {
                date = dateValue
            } else {
                // Fallback to ISO8601
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = isoFormatter.date(from: dateString) ?? Date()
            }
        } else {
            date = try container.decode(Date.self, forKey: .date)
        }
        
        type = try container.decode(FarmTouchType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex)
        completed = try container.decode(Bool.self, forKey: .completed)
        campaignId = try container.decodeIfPresent(UUID.self, forKey: .campaignId)
        batchId = try container.decodeIfPresent(UUID.self, forKey: .batchId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    init(
        id: UUID = UUID(),
        farmId: UUID,
        date: Date,
        type: FarmTouchType,
        title: String,
        notes: String? = nil,
        orderIndex: Int? = nil,
        completed: Bool = false,
        campaignId: UUID? = nil,
        batchId: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.farmId = farmId
        self.date = date
        self.type = type
        self.title = title
        self.notes = notes
        self.orderIndex = orderIndex
        self.completed = completed
        self.campaignId = campaignId
        self.batchId = batchId
        self.createdAt = createdAt
    }
    
    /// Encode date as date-only string
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(farmId, forKey: .farmId)
        
        // Encode date as date-only string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        try container.encode(dateFormatter.string(from: date), forKey: .date)
        
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(orderIndex, forKey: .orderIndex)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(campaignId, forKey: .campaignId)
        try container.encodeIfPresent(batchId, forKey: .batchId)
        try container.encode(createdAt, forKey: .createdAt)
    }
}



