import Foundation
import CoreLocation

// MARK: - Address Cache Row (DB Model)

public struct AddressCacheRow: Codable, Equatable {
    public let id: UUID
    public let street: String
    public let locality: String?
    public let houseNumber: String
    public let formattedAddress: String
    public let lat: Double
    public let lon: Double
    public let source: String
    public let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case street
        case locality
        case houseNumber = "house_number"
        case formattedAddress = "formatted_address"
        case lat
        case lon
        case source
        case createdAt = "created_at"
    }
}

// MARK: - Converters

extension AddressCacheRow {
    /// Convert DB row to AddressCandidate for use in app
    public func toAddressCandidate() -> AddressCandidate {
        return AddressCandidate(
            address: formattedAddress,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            distanceMeters: 0.0, // Distance not stored in cache, will be recalculated
            number: houseNumber,
            street: street,
            houseKey: "\(houseNumber) \(street)".uppercased()
        )
    }
    
    /// Create cache row from AddressCandidate + metadata
    public static func fromAddressCandidate(
        _ candidate: AddressCandidate,
        street: String,
        locality: String?,
        source: String
    ) -> [String: Any] {
        return [
            "street": street.uppercased(),
            "locality": locality ?? NSNull(),
            "house_number": candidate.number,
            "formatted_address": candidate.address,
            "lat": candidate.coordinate.latitude,
            "lon": candidate.coordinate.longitude,
            "source": source
        ]
    }
}

