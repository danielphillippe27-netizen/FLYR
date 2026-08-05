import Foundation

/// QR Code model matching the qr_codes table schema
public struct QRCode: Identifiable, Codable, Equatable {
    public let id: UUID
    public let addressId: UUID?
    public let campaignId: UUID?
    public let farmId: UUID?
    public let batchId: UUID?
    public let landingPageId: UUID?
    public let qrVariant: String? // 'A' or 'B' for A/B testing
    public let slug: String? // URL-friendly identifier for routing
    public let qrUrl: String
    public let qrImage: String? // Base64 encoded PNG
    public let createdAt: Date
    public let updatedAt: Date
    public let metadata: QRCodeMetadata?
    
    public init(
        id: UUID = UUID(),
        addressId: UUID? = nil,
        campaignId: UUID? = nil,
        farmId: UUID? = nil,
        batchId: UUID? = nil,
        landingPageId: UUID? = nil,
        qrVariant: String? = nil,
        slug: String? = nil,
        qrUrl: String,
        qrImage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: QRCodeMetadata? = nil
    ) {
        self.id = id
        self.addressId = addressId
        self.campaignId = campaignId
        self.farmId = farmId
        self.batchId = batchId
        self.landingPageId = landingPageId
        self.qrVariant = qrVariant
        self.slug = slug
        self.qrUrl = qrUrl
        self.qrImage = qrImage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case addressId = "address_id"
        case campaignId = "campaign_id"
        case farmId = "farm_id"
        case batchId = "batch_id"
        case landingPageId = "landing_page_id"
        case qrVariant = "qr_variant"
        case slug
        case qrUrl = "qr_url"
        case qrImage = "qr_image"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case metadata
    }
    
    /// Returns the entity ID (address, campaign, or farm)
    public var entityId: UUID? {
        addressId ?? campaignId ?? farmId
    }
    
    /// Returns the entity type
    public var entityType: QRCodeEntityType {
        if addressId != nil {
            return .address
        } else if campaignId != nil {
            return .campaign
        } else if farmId != nil {
            return .farm
        } else {
            return .unknown
        }
    }
}

/// Entity type for QR codes
public enum QRCodeEntityType {
    case address
    case campaign
    case farm
    case unknown
}

/// Metadata stored with QR codes
public struct QRCodeMetadata: Codable, Equatable {
    public let addressCount: Int?
    public let entityName: String?
    public let deviceInfo: String?
    public let name: String?
    public let isPrinted: Bool?
    public let batchName: String?
    public let destinationType: String?
    public let utmSource: String?
    public let utmMedium: String?
    public let utmCampaign: String?
    public let customUTM: String?
    
    public init(
        addressCount: Int? = nil,
        entityName: String? = nil,
        deviceInfo: String? = nil,
        name: String? = nil,
        isPrinted: Bool? = nil,
        batchName: String? = nil,
        destinationType: String? = nil,
        utmSource: String? = nil,
        utmMedium: String? = nil,
        utmCampaign: String? = nil,
        customUTM: String? = nil
    ) {
        self.addressCount = addressCount
        self.entityName = entityName
        self.deviceInfo = deviceInfo
        self.name = name
        self.isPrinted = isPrinted
        self.batchName = batchName
        self.destinationType = destinationType
        self.utmSource = utmSource
        self.utmMedium = utmMedium
        self.utmCampaign = utmCampaign
        self.customUTM = customUTM
    }
    
    enum CodingKeys: String, CodingKey {
        case addressCount = "address_count"
        case entityName = "entity_name"
        case deviceInfo = "device_info"
        case name
        case isPrinted = "is_printed"
        case batchName = "batch_name"
        case destinationType = "destination_type"
        case utmSource = "utm_source"
        case utmMedium = "utm_medium"
        case utmCampaign = "utm_campaign"
        case customUTM = "custom_utm"
    }
}

/// Database row representation for QR codes
public struct QRCodeDBRow: Codable {
    public let id: UUID
    public let addressId: UUID?
    public let campaignId: UUID?
    public let farmId: UUID?
    public let batchId: UUID?
    public let landingPageId: UUID?
    public let qrVariant: String?
    public let slug: String?
    public let qrUrl: String
    public let qrImage: String?
    public let createdAt: Date
    public let updatedAt: Date
    let metadata: [String: AnyCodable]? // Internal - AnyCodable is internal
    
    enum CodingKeys: String, CodingKey {
        case id
        case addressId = "address_id"
        case campaignId = "campaign_id"
        case farmId = "farm_id"
        case batchId = "batch_id"
        case landingPageId = "landing_page_id"
        case qrVariant = "qr_variant"
        case slug
        case qrUrl = "qr_url"
        case qrImage = "qr_image"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case metadata
    }
    
    /// Convert to QRCode model
    func toQRCode() -> QRCode {
        let metadataModel: QRCodeMetadata? = {
            guard let metadata = metadata else { return nil }
            
            let addressCount = (metadata["address_count"]?.value as? Int) ?? (metadata["addressCount"]?.value as? Int)
            let entityName = (metadata["entity_name"]?.value as? String) ?? (metadata["entityName"]?.value as? String)
            let deviceInfo = (metadata["device_info"]?.value as? String) ?? (metadata["deviceInfo"]?.value as? String)
            let name = metadata["name"]?.value as? String
            let isPrinted = (metadata["is_printed"]?.value as? Bool) ?? (metadata["isPrinted"]?.value as? Bool)
            let batchName = (metadata["batch_name"]?.value as? String) ?? (metadata["batchName"]?.value as? String)
            let destinationType = (metadata["destination_type"]?.value as? String) ?? (metadata["destinationType"]?.value as? String)
            let utmSource = (metadata["utm_source"]?.value as? String) ?? (metadata["utmSource"]?.value as? String)
            let utmMedium = (metadata["utm_medium"]?.value as? String) ?? (metadata["utmMedium"]?.value as? String)
            let utmCampaign = (metadata["utm_campaign"]?.value as? String) ?? (metadata["utmCampaign"]?.value as? String)
            let customUTM = (metadata["custom_utm"]?.value as? String) ?? (metadata["customUTM"]?.value as? String)
            
            return QRCodeMetadata(
                addressCount: addressCount,
                entityName: entityName,
                deviceInfo: deviceInfo,
                name: name,
                isPrinted: isPrinted,
                batchName: batchName,
                destinationType: destinationType,
                utmSource: utmSource,
                utmMedium: utmMedium,
                utmCampaign: utmCampaign,
                customUTM: customUTM
            )
        }()
        
        return QRCode(
            id: id,
            addressId: addressId,
            campaignId: campaignId,
            farmId: farmId,
            batchId: batchId,
            landingPageId: landingPageId,
            qrVariant: qrVariant,
            slug: slug,
            qrUrl: qrUrl,
            qrImage: qrImage,
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadata: metadataModel
        )
    }
}

