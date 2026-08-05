import Foundation
import CoreLocation

// MARK: - Geo Street Adapter

/// Lightweight adapter wrapping GeoAPI.reverseStreet() with normalization
/// Centralizes reverse-geocoding logic to avoid duplication and ensure consistent formatting
public struct GeoStreetAdapter {
    private let geoAPI: GeoAPI
    
    init(geoAPI: GeoAPI? = nil) {
        self.geoAPI = geoAPI ?? GeoAPI.shared
    }
    
    /// Reverse geocode a location to get normalized street name and locality
    /// - Parameter location: Coordinate to reverse geocode
    /// - Returns: Tuple of (street: String, locality: String?)
    public func reverseSeedStreet(at location: CLLocationCoordinate2D) async throws -> (street: String, locality: String?) {
        let result = try await geoAPI.reverseStreet(location)
        return (
            street: normalize(result.street),
            locality: normalize(result.locality)
        )
    }
    
    /// Normalize street names for consistent comparison and storage
    /// - Parameter input: Raw street name or locality
    /// - Returns: Normalized string (trimmed, uppercased, standardized spacing)
    private func normalize(_ input: String?) -> String {
        guard let input = input else { return "" }
        
        return input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }
}
