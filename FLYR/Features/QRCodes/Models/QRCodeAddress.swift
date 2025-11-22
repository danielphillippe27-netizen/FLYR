import Foundation
import CoreLocation

/// Model representing an address with QR code data
public struct QRCodeAddress: Identifiable, Codable, Equatable {
    public let id: UUID
    public let addressId: UUID // FK to campaign_addresses or farm_addresses
    public let formatted: String
    public let coordinate: CLLocationCoordinate2D?
    public let qrCodeImage: Data? // Cached QR code image data
    public let webURL: String // https://flyr.ca/address/{id}
    public let deepLinkURL: String // flyr://address/{id}
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        addressId: UUID,
        formatted: String,
        coordinate: CLLocationCoordinate2D? = nil,
        qrCodeImage: Data? = nil,
        webURL: String,
        deepLinkURL: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.addressId = addressId
        self.formatted = formatted
        self.coordinate = coordinate
        self.qrCodeImage = qrCodeImage
        self.webURL = webURL
        self.deepLinkURL = deepLinkURL
        self.createdAt = createdAt
    }
    
    /// Generate URLs for this address
    static func generateURLs(for addressId: UUID) -> (webURL: String, deepLinkURL: String) {
        let webURL = "https://flyrpro.app/address/\(addressId.uuidString)"
        let deepLinkURL = "flyr://address/\(addressId.uuidString)"
        return (webURL, deepLinkURL)
    }
}



