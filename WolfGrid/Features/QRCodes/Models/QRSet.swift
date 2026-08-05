import Foundation

/// QR Set model matching the qr_sets table schema
public struct QRSet: Identifiable, Codable, Equatable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let totalAddresses: Int
    public let variantCount: Int
    public let qrCodeIds: [UUID]
    public let campaignId: UUID?
    public let userId: UUID
    
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalAddresses: Int = 0,
        variantCount: Int = 0,
        qrCodeIds: [UUID] = [],
        campaignId: UUID? = nil,
        userId: UUID
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalAddresses = totalAddresses
        self.variantCount = variantCount
        self.qrCodeIds = qrCodeIds
        self.campaignId = campaignId
        self.userId = userId
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case totalAddresses = "total_addresses"
        case variantCount = "variant_count"
        case qrCodeIds = "qr_code_ids"
        case campaignId = "campaign_id"
        case userId = "user_id"
    }
}

/// Database row representation for QR sets
public struct QRSetDBRow: Codable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let totalAddresses: Int?
    public let variantCount: Int?
    public let qrCodeIds: [UUID]
    public let campaignId: UUID?
    public let userId: UUID
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case totalAddresses = "total_addresses"
        case variantCount = "variant_count"
        case qrCodeIds = "qr_code_ids"
        case campaignId = "campaign_id"
        case userId = "user_id"
    }
    
    /// Convert to QRSet model
    func toQRSet() -> QRSet {
        return QRSet(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            totalAddresses: totalAddresses ?? 0,
            variantCount: variantCount ?? 0,
            qrCodeIds: qrCodeIds,
            campaignId: campaignId,
            userId: userId
        )
    }
}

