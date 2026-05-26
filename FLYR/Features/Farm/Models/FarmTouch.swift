import Foundation

/// Type of farm touch
enum FarmTouchType: String, Codable, CaseIterable, Identifiable, Sendable {
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
        case .doorKnock: return "door.left.hand.closed"
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

    var defaultModeRawValue: String {
        switch self {
        case .flyer: return "flyer"
        case .doorKnock: return "door_knock"
        case .event: return "event"
        case .newsletter: return "newsletter"
        case .ad: return "social_ad"
        case .custom: return "pop_by"
        }
    }
}

/// Farm touch model representing a planned or executed touch
struct FarmTouch: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let farmId: UUID
    let cycleNumber: Int?
    let date: Date
    let type: FarmTouchType
    let mode: String?
    let title: String
    let notes: String?
    let orderIndex: Int?
    let completed: Bool
    let campaignId: UUID?
    let batchId: UUID?
    let sessionId: UUID?
    let completedAt: Date?
    let completedByUserId: UUID?
    let executionMetrics: [String: AnyCodable]?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case cycleNumber = "cycle_number"
        case date
        case type
        case mode
        case title
        case notes
        case orderIndex = "order_index"
        case completed
        case campaignId = "campaign_id"
        case batchId = "batch_id"
        case sessionId = "session_id"
        case completedAt = "completed_at"
        case completedByUserId = "completed_by_user_id"
        case executionMetrics = "execution_metrics"
        case createdAt = "created_at"
    }
    
    /// Custom date decoder for date-only fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        farmId = try container.decode(UUID.self, forKey: .farmId)
        cycleNumber = try container.decodeIfPresent(Int.self, forKey: .cycleNumber)
        
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
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex)
        completed = try container.decode(Bool.self, forKey: .completed)
        campaignId = try container.decodeIfPresent(UUID.self, forKey: .campaignId)
        batchId = try container.decodeIfPresent(UUID.self, forKey: .batchId)
        sessionId = try container.decodeIfPresent(UUID.self, forKey: .sessionId)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        completedByUserId = try container.decodeIfPresent(UUID.self, forKey: .completedByUserId)
        executionMetrics = try container.decodeIfPresent([String: AnyCodable].self, forKey: .executionMetrics)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    init(
        id: UUID = UUID(),
        farmId: UUID,
        cycleNumber: Int? = nil,
        date: Date,
        type: FarmTouchType,
        mode: String? = nil,
        title: String,
        notes: String? = nil,
        orderIndex: Int? = nil,
        completed: Bool = false,
        campaignId: UUID? = nil,
        batchId: UUID? = nil,
        sessionId: UUID? = nil,
        completedAt: Date? = nil,
        completedByUserId: UUID? = nil,
        executionMetrics: [String: AnyCodable]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.farmId = farmId
        self.cycleNumber = cycleNumber
        self.date = date
        self.type = type
        self.mode = mode
        self.title = title
        self.notes = notes
        self.orderIndex = orderIndex
        self.completed = completed
        self.campaignId = campaignId
        self.batchId = batchId
        self.sessionId = sessionId
        self.completedAt = completedAt
        self.completedByUserId = completedByUserId
        self.executionMetrics = executionMetrics
        self.createdAt = createdAt
    }
    
    /// Encode date as date-only string
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(farmId, forKey: .farmId)
        try container.encodeIfPresent(cycleNumber, forKey: .cycleNumber)
        
        // Encode date as date-only string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        try container.encode(dateFormatter.string(from: date), forKey: .date)
        
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(orderIndex, forKey: .orderIndex)
        try container.encode(completed, forKey: .completed)
        try container.encodeIfPresent(campaignId, forKey: .campaignId)
        try container.encodeIfPresent(batchId, forKey: .batchId)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(completedByUserId, forKey: .completedByUserId)
        try container.encodeIfPresent(executionMetrics, forKey: .executionMetrics)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

extension FarmTouch {
    var effectiveModeRawValue: String {
        let trimmedMode = mode?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedMode, !trimmedMode.isEmpty {
            return trimmedMode.lowercased()
        }
        return type.defaultModeRawValue
    }

    var effectiveModeDisplayName: String {
        switch effectiveModeRawValue {
        case "flyer":
            return "Flyer Run"
        case "door_knock", "door_knocking":
            return "Door Knock"
        case "event", "community_event":
            return "Community Event"
        case "newsletter":
            return "Newsletter"
        case "ad", "social_ad":
            return "Social Ad Campaign"
        case "phone_call", "call":
            return "Phone Call"
        case "pop_by", "popby":
            return "Pop-By"
        case "survey":
            return "Survey"
        case "custom":
            return "Custom"
        default:
            return effectiveModeRawValue
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    var effectiveIconName: String {
        switch effectiveModeRawValue {
        case "flyer":
            return "paperplane.fill"
        case "door_knock", "door_knocking":
            return "door.left.hand.closed"
        case "event", "community_event":
            return "calendar"
        case "newsletter":
            return "envelope.fill"
        case "ad", "social_ad":
            return "megaphone.fill"
        case "phone_call", "call":
            return "phone.fill"
        case "pop_by", "popby":
            return "gift.fill"
        case "survey":
            return "list.clipboard.fill"
        default:
            return type.iconName
        }
    }

    var effectiveColorName: String {
        switch effectiveModeRawValue {
        case "flyer":
            return "blue"
        case "door_knock", "door_knocking":
            return "green"
        case "event", "community_event":
            return "orange"
        case "newsletter":
            return "purple"
        case "ad", "social_ad":
            return "yellow"
        case "phone_call", "call":
            return "teal"
        case "pop_by", "popby":
            return "purple"
        case "survey":
            return "indigo"
        default:
            return type.colorName
        }
    }

    var effectiveDisplayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty
            || trimmed.localizedCaseInsensitiveContains("cycle")
            || type == .custom {
            return effectiveModeDisplayName
        }

        switch effectiveModeRawValue {
        case "pop_by", "popby":
            return "Pop-By"
        case "phone_call", "call":
            return "Phone Call"
        default:
            return trimmed
        }
    }
}
