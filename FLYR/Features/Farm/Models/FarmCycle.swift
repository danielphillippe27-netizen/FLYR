import Foundation

/// Farm cycle model backed by the existing `farm_phases` table.
struct FarmCycle: Identifiable, Codable, Equatable {
    let id: UUID
    let farmId: UUID
    let cycleName: String
    let startDate: Date
    let endDate: Date
    let campaignId: UUID?
    let results: [String: AnyCodable]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case cycleName = "phase_name"
        case startDate = "start_date"
        case endDate = "end_date"
        case campaignId = "campaign_id"
        case results
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        farmId = try container.decode(UUID.self, forKey: .farmId)
        cycleName = try container.decode(String.self, forKey: .cycleName)

        if let dateString = try? container.decode(String.self, forKey: .startDate) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            startDate = dateFormatter.date(from: dateString) ?? Date()
        } else {
            startDate = try container.decode(Date.self, forKey: .startDate)
        }

        if let dateString = try? container.decode(String.self, forKey: .endDate) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            endDate = dateFormatter.date(from: dateString) ?? Date()
        } else {
            endDate = try container.decode(Date.self, forKey: .endDate)
        }

        campaignId = try container.decodeIfPresent(UUID.self, forKey: .campaignId)
        results = try container.decodeIfPresent([String: AnyCodable].self, forKey: .results)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    init(
        id: UUID = UUID(),
        farmId: UUID,
        cycleName: String,
        startDate: Date,
        endDate: Date,
        campaignId: UUID? = nil,
        results: [String: AnyCodable]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.farmId = farmId
        self.cycleName = cycleName
        self.startDate = startDate
        self.endDate = endDate
        self.campaignId = campaignId
        self.results = results
        self.createdAt = createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(farmId, forKey: .farmId)
        try container.encode(cycleName, forKey: .cycleName)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        try container.encode(dateFormatter.string(from: startDate), forKey: .startDate)
        try container.encode(dateFormatter.string(from: endDate), forKey: .endDate)

        try container.encodeIfPresent(campaignId, forKey: .campaignId)
        try container.encodeIfPresent(results, forKey: .results)
        try container.encode(createdAt, forKey: .createdAt)
    }
}
