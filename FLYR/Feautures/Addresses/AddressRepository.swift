import Foundation
import CoreLocation

// MARK: - Address Repository Protocol

/// Protocol defining the contract for address lookup services
/// Allows dependency injection and testing without concrete implementations
public protocol AddressRepository {
    /// Find nearest addresses to a location
    /// - Parameters:
    ///   - location: Center coordinate for search
    ///   - limit: Maximum number of addresses to return
    ///   - radiusMeters: Search radius in meters
    ///   - campaignId: Optional; when set, backend uses it for generate-address-list (Lambda/S3)
    /// - Returns: Array of address candidates sorted by distance
    func nearestAddresses(
        at location: CLLocationCoordinate2D,
        limit: Int,
        radiusMeters: Double,
        campaignId: UUID?
    ) async throws -> [AddressCandidate]

    /// Find addresses on the same street as a seed address
    /// - Parameters:
    ///   - seed: Reference address candidate
    ///   - limit: Maximum number of addresses to return
    /// - Returns: Array of address candidates on the same street
    func sameStreet(
        seed: AddressCandidate,
        limit: Int
    ) async throws -> [AddressCandidate]
}


