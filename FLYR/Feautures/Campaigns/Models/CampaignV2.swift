import Foundation

// MARK: - Campaign Type

public enum CampaignType: String, CaseIterable, Identifiable, Codable {
  case flyer
  case doorKnock
  case event
  case survey
  case gift
  case popBy
  case openHouse

  public var id: String { rawValue }

  public var title: String {
    switch self {
      case .flyer:            "Flyer"
      case .doorKnock:        "Door Knock"
      case .event:            "Event"
      case .survey:           "Survey"
      case .gift:             "Gift"
      case .popBy:            "Pop-By"
      case .openHouse:        "Open House"
    }
  }

  public var label: String { title }

  /// Picker options: Flyer and Door Knock only.
  public static var ordered: [CampaignType] {
    [.flyer, .doorKnock]
  }
}

extension CampaignType: CustomStringConvertible {
  public var description: String { title }
}

// MARK: - Address Source

public enum AddressSource: String, CaseIterable, Identifiable, Codable {
    case closestHome = "closest_home"
    case importList = "import_list"
    case map = "map"
    case sameStreet = "same_street"
    
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .closestHome: return "Nearby"
        case .importList: return "List"
        case .map: return "Map"
        case .sameStreet: return "Street"
        }
    }
    
    var label: String { displayName }
}

// MARK: - Address Quality

enum AddressQuality: String, CaseIterable, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    
    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

// MARK: - Campaign Status

enum CampaignStatus: String, Codable {
    case draft = "draft"
    case active = "active"
    case completed = "completed"
    case paused = "paused"
    case archived = "archived"
}

// MARK: - Campaign V2

struct CampaignV2: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: CampaignType
    var addressSource: AddressSource
    var addresses: [CampaignAddress]
    var totalFlyers: Int      // Maps to DB total_flyers
    var scans: Int            // Maps to DB scans
    var conversions: Int      // Maps to DB conversions
    var createdAt: Date
    var status: CampaignStatus
    var seedQuery: String?    // Maps to DB region (e.g., "Main St, Toronto")
    
    // Computed progress based on scans/total_flyers (0.0-1.0)
    var progress: Double {
        guard totalFlyers > 0 else { return 0.0 }
        return Double(scans) / Double(totalFlyers)
    }
    
    // Helper for display as percentage
    var progressPct: Int {
        Int(round(progress * 100))
    }
    
    // Custom decoder for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(CampaignType.self, forKey: .type)
        addressSource = try container.decode(AddressSource.self, forKey: .addressSource)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decodeIfPresent(CampaignStatus.self, forKey: .status) ?? .draft
        seedQuery = try container.decodeIfPresent(String.self, forKey: .seedQuery)
        
        // New fields with defaults for backward compatibility
        totalFlyers = try container.decodeIfPresent(Int.self, forKey: .totalFlyers) ?? 0
        scans = try container.decodeIfPresent(Int.self, forKey: .scans) ?? 0
        conversions = try container.decodeIfPresent(Int.self, forKey: .conversions) ?? 0
        
        // Handle backward compatibility: try [CampaignAddress] first, fallback to [String]
        if let campaignAddresses = try? container.decode([CampaignAddress].self, forKey: .addresses) {
            addresses = campaignAddresses
            // If totalFlyers wasn't set, use addresses count
            if totalFlyers == 0 {
                totalFlyers = campaignAddresses.count
            }
        } else if let stringAddresses = try? container.decode([String].self, forKey: .addresses) {
            // Convert [String] to [CampaignAddress] for backward compatibility
            addresses = stringAddresses.map { CampaignAddress(address: $0) }
            if totalFlyers == 0 {
                totalFlyers = stringAddresses.count
            }
        } else {
            addresses = []
        }
        
        // Handle old progress field (0.0-1.0) if present
        if let oldProgress = try? container.decode(Double.self, forKey: .progress) {
            // Convert old progress to scans if not already set
            if scans == 0 && totalFlyers > 0 {
                scans = Int(round(oldProgress * Double(totalFlyers)))
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, addressSource, addresses, createdAt, status
        case totalFlyers, scans, conversions, seedQuery
        case progress // For backward compatibility only
    }
    
    // Custom encoder (don't encode computed progress)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(addressSource, forKey: .addressSource)
        try container.encode(addresses, forKey: .addresses)
        try container.encode(totalFlyers, forKey: .totalFlyers)
        try container.encode(scans, forKey: .scans)
        try container.encode(conversions, forKey: .conversions)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(seedQuery, forKey: .seedQuery)
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        type: CampaignType,
        addressSource: AddressSource,
        addresses: [CampaignAddress] = [],
        totalFlyers: Int? = nil,
        scans: Int = 0,
        conversions: Int = 0,
        createdAt: Date = Date(),
        status: CampaignStatus = .draft,
        seedQuery: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.addressSource = addressSource
        self.addresses = addresses
        self.totalFlyers = totalFlyers ?? addresses.count
        self.scans = scans
        self.conversions = conversions
        self.createdAt = createdAt
        self.status = status
        self.seedQuery = seedQuery
    }
    
    static func == (lhs: CampaignV2, rhs: CampaignV2) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Campaign Draft

struct CampaignDraft: Codable {
    let name: String
    let type: CampaignType
    let addressSource: AddressSource
    let addresses: [CampaignAddress]
    
    enum CodingKeys: String, CodingKey {
        case name, type, addresses
        case addressSource = "address_source"
    }
}

// Legacy alias for compatibility
typealias CampaignV2Draft = CampaignDraft

// MARK: - Preview Helpers

extension CampaignV2 {
    static let mockCampaigns: [CampaignV2] = [
        CampaignV2(
            name: "Downtown Door Knocking",
            type: .doorKnock,
            addressSource: .closestHome,
            addresses: [
                CampaignAddress(address: "123 Main St"),
                CampaignAddress(address: "456 Oak Ave"),
                CampaignAddress(address: "789 Pine St")
            ],
            totalFlyers: 3,
            scans: 1,
            conversions: 0,
            createdAt: Date().addingTimeInterval(-86400 * 2)
        ),
        CampaignV2(
            name: "Summer Flyer Campaign",
            type: .flyer,
            addressSource: .importList,
            addresses: [
                CampaignAddress(address: "321 Elm St"),
                CampaignAddress(address: "654 Maple Ave"),
                CampaignAddress(address: "987 Cedar St"),
                CampaignAddress(address: "147 Birch Rd")
            ],
            totalFlyers: 4,
            scans: 3,
            conversions: 1,
            createdAt: Date().addingTimeInterval(-86400 * 5)
        ),
        CampaignV2(
            name: "Holiday Event",
            type: .event,
            addressSource: .closestHome,
            addresses: [CampaignAddress(address: "555 Event Lane")],
            totalFlyers: 1,
            scans: 0,
            conversions: 0,
            createdAt: Date().addingTimeInterval(-3600)
        )
    ]
}
