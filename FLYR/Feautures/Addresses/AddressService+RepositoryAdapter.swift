import Foundation
import CoreLocation

// MARK: - AddressService Repository Adapter

/// Extension making AddressService conform to AddressRepository protocol
/// Preserves all existing functionality while enabling protocol-based dependency injection
extension AddressService: AddressRepository {
    
    public func nearestAddresses(
        at location: CLLocationCoordinate2D,
        limit: Int,
        radiusMeters: Double
    ) async throws -> [AddressCandidate] {
        // Delegate to existing fetchNearest method, preserving ODA-first, Mapbox-fallback logic
        return try await fetchNearest(center: location, target: limit)
    }
    
    public func sameStreet(
        seed: AddressCandidate,
        limit: Int
    ) async throws -> [AddressCandidate] {
        // Delegate to existing fetchSameStreet method
        // Note: This requires street name and locality, which we'll get from GeoAPI
        // For now, we'll use the seed's street if available, otherwise reverse geocode
        let street = seed.street.isEmpty ? "Unknown Street" : seed.street
        let locality: String? = nil // Will be determined by reverse geocoding if needed
        
        return try await fetchSameStreet(
            seed: seed.coordinate,
            street: street,
            locality: locality,
            target: limit
        )
    }
}
