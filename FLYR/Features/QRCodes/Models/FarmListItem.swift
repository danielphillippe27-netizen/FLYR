import Foundation

/// Farm list item (lightweight representation for selection)
public struct FarmListItem: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let areaLabel: String?
    public let addressCount: Int?
    
    public init(id: UUID, name: String, areaLabel: String? = nil, addressCount: Int? = nil) {
        self.id = id
        self.name = name
        self.areaLabel = areaLabel
        self.addressCount = addressCount
    }
}

/// Farm database row (QRCode module)
public struct QRFarmDBRow: Codable {
    public let id: UUID
    public let ownerId: UUID
    public let name: String
    public let areaLabel: String?
    public let frequencyDays: Int
    public let createdAt: Date
    public let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case areaLabel = "area_label"
        case frequencyDays = "frequency_days"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    /// Convert to FarmListItem
    func toFarmListItem(addressCount: Int? = nil) -> FarmListItem {
        FarmListItem(
            id: id,
            name: name,
            areaLabel: areaLabel,
            addressCount: addressCount
        )
    }
}

