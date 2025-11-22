import Foundation
import CoreLocation

// MARK: - Address Provider Protocol

/// Protocol for address lookup services (ODA, Mapbox, etc.)
public protocol AddressProvider {
    /// Find nearest addresses to a center point
    func nearest(center: CLLocationCoordinate2D, limit: Int) async throws -> [AddressCandidate]
    
    /// Find addresses on the same street as a seed point
    func sameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, limit: Int) async throws -> [AddressCandidate]
    
    /// Try DB once with short timeout, else throw (caller falls back to Mapbox)
    /// Default implementation falls back to regular nearest() call
    func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int) async throws -> [AddressCandidate]
}

// MARK: - Default Implementation

extension AddressProvider {
    /// Default implementation that just calls nearest() - used by MapboxProvider
    public func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int = 1200) async throws -> [AddressCandidate] {
        return try await nearest(center: center, limit: limit)
    }
}


