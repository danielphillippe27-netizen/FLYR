import Foundation

/// Batch model for QR code batch configuration
public struct Batch: Identifiable, Codable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let name: String
    public let qrType: QRType
    public let landingPageId: UUID?
    public let customURL: String?
    public let exportFormat: ExportFormat
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        qrType: QRType,
        landingPageId: UUID? = nil,
        customURL: String? = nil,
        exportFormat: ExportFormat,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.qrType = qrType
        self.landingPageId = landingPageId
        self.customURL = customURL
        self.exportFormat = exportFormat
        self.createdAt = createdAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case qrType = "qr_type"
        case landingPageId = "landing_page_id"
        case customURL = "custom_url"
        case exportFormat = "export_format"
        case createdAt = "created_at"
    }
}

/// Database row representation for batches
public struct BatchDBRow: Codable {
    public let id: UUID
    public let userId: UUID
    public let name: String
    public let qrType: String
    public let landingPageId: UUID?
    public let customURL: String?
    public let exportFormat: String
    public let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case qrType = "qr_type"
        case landingPageId = "landing_page_id"
        case customURL = "custom_url"
        case exportFormat = "export_format"
        case createdAt = "created_at"
    }
    
    /// Convert to Batch model
    func toBatch() -> Batch? {
        guard let qrType = QRType(rawValue: qrType),
              let exportFormat = ExportFormat(rawValue: exportFormat) else {
            return nil
        }
        
        return Batch(
            id: id,
            userId: userId,
            name: name,
            qrType: qrType,
            landingPageId: landingPageId,
            customURL: customURL,
            exportFormat: exportFormat,
            createdAt: createdAt
        )
    }
}



