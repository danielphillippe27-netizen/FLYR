import Foundation
import CoreLocation

// MARK: - Address Candidate (temporary during search)

public struct AddressCandidate: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let address: String
    public let coordinate: CLLocationCoordinate2D
    public let distanceMeters: Double
    public let number: String
    public let street: String
    public let houseKey: String // "5900 MAIN STREET" for strong deduplication
    public let source: String? // "overture" (backend), "mapbox" for UI display
    
    public init(
        id: UUID = .init(),
        address: String,
        coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        number: String = "",
        street: String = "",
        houseKey: String = "",
        source: String? = nil
    ) {
        self.id = id
        self.address = address
        self.coordinate = coordinate
        self.distanceMeters = distanceMeters
        self.number = number
        self.street = street
        self.houseKey = houseKey
        self.source = source
    }
    
    public static func == (lhs: AddressCandidate, rhs: AddressCandidate) -> Bool {
        return lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Seed Geocode Result

public struct SeedGeocode {
    public let query: String
    public let coordinate: CLLocationCoordinate2D
    
    public init(query: String, coordinate: CLLocationCoordinate2D) {
        self.query = query
        self.coordinate = coordinate
    }
}

// CampaignAddress lives in BuildingLinkModels.swift (single source of truth)

// MARK: - String House Number Extraction

extension String {
    /// Extract house number from address string
    /// Pattern: `^\s*(\d+[A-Za-z]?)\b` - supports "123", "123A", "5900B", etc.
    func extractHouseNumber() -> String? {
        let pattern = #"^\s*(\d+[A-Za-z]?)\b"#
        return range(of: pattern, options: .regularExpression).map { 
            String(self[$0]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - CLLocationCoordinate2D Codable Support

extension CLLocationCoordinate2D: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let array = try container.decode([Double].self)
        guard array.count == 2 else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected array of 2 doubles for coordinate"
                )
            )
        }
        self.init(latitude: array[1], longitude: array[0])
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([longitude, latitude])
    }
}
