import Foundation

/// Farm phase model representing a phase in the farm lifecycle
struct FarmPhase: Identifiable, Codable, Equatable {
    let id: UUID
    let farmId: UUID
    let phaseName: String
    let startDate: Date
    let endDate: Date
    let campaignId: UUID?
    let results: [String: AnyCodable]?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case phaseName = "phase_name"
        case startDate = "start_date"
        case endDate = "end_date"
        case campaignId = "campaign_id"
        case results
        case createdAt = "created_at"
    }
    
    /// Custom date decoder for date-only fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        farmId = try container.decode(UUID.self, forKey: .farmId)
        phaseName = try container.decode(String.self, forKey: .phaseName)
        
        // Decode dates (can be date-only string or full timestamp)
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
        phaseName: String,
        startDate: Date,
        endDate: Date,
        campaignId: UUID? = nil,
        results: [String: AnyCodable]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.farmId = farmId
        self.phaseName = phaseName
        self.startDate = startDate
        self.endDate = endDate
        self.campaignId = campaignId
        self.results = results
        self.createdAt = createdAt
    }
    
    /// Encode dates as date-only strings
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(farmId, forKey: .farmId)
        try container.encode(phaseName, forKey: .phaseName)
        
        // Encode dates as date-only strings
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        try container.encode(dateFormatter.string(from: startDate), forKey: .startDate)
        try container.encode(dateFormatter.string(from: endDate), forKey: .endDate)
        
        try container.encodeIfPresent(campaignId, forKey: .campaignId)
        try container.encodeIfPresent(results, forKey: .results)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    /// Get result value as Int
    func getResultInt(_ key: String) -> Int? {
        guard let value = results?[key]?.value else { return nil }
        if let int = value as? Int {
            return int
        } else if let double = value as? Double {
            return Int(double)
        } else if let string = value as? String, let int = Int(string) {
            return int
        }
        return nil
    }
    
    /// Get result value as Double
    func getResultDouble(_ key: String) -> Double? {
        guard let value = results?[key]?.value else { return nil }
        if let double = value as? Double {
            return double
        } else if let int = value as? Int {
            return Double(int)
        } else if let string = value as? String, let double = Double(string) {
            return double
        }
        return nil
    }
    
    /// Get result value as String
    func getResultString(_ key: String) -> String? {
        guard let value = results?[key]?.value else { return nil }
        if let string = value as? String {
            return string
        } else {
            return String(describing: value)
        }
    }
}



