import Foundation

/// Source of a farm lead
enum FarmLeadSource: String, Codable, CaseIterable, Identifiable {
    case qrScan = "qr_scan"
    case doorKnock = "door_knock"
    case flyer = "flyer"
    case event = "event"
    case newsletter = "newsletter"
    case ad = "ad"
    case custom = "custom"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .qrScan: return "QR Scan"
        case .doorKnock: return "Door Knock"
        case .flyer: return "Flyer"
        case .event: return "Event"
        case .newsletter: return "Newsletter"
        case .ad: return "Ad"
        case .custom: return "Custom"
        }
    }
}

/// Farm lead model representing a lead generated from a farm touch
struct FarmLead: Identifiable, Codable, Equatable {
    let id: UUID
    let farmId: UUID
    let touchId: UUID?
    let leadSource: FarmLeadSource
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case touchId = "touch_id"
        case leadSource = "lead_source"
        case name
        case phone
        case email
        case address
        case createdAt = "created_at"
    }
    
    init(
        id: UUID = UUID(),
        farmId: UUID,
        touchId: UUID? = nil,
        leadSource: FarmLeadSource,
        name: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.farmId = farmId
        self.touchId = touchId
        self.leadSource = leadSource
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.createdAt = createdAt
    }
}



