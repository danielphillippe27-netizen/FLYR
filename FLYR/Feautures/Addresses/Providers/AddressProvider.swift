import Foundation
import CoreLocation

// MARK: - Address Provider Protocol

/// Protocol for address lookup services (MotherDuck/Overture via backend, Mapbox fallback).
public protocol AddressProvider {
    /// Find nearest addresses to a center point. MotherDuck requires campaignId (nil → throw); Mapbox ignores campaignId.
    func nearest(center: CLLocationCoordinate2D, limit: Int, campaignId: UUID?) async throws -> [AddressCandidate]
    
    /// Find addresses on the same street as a seed point
    func sameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, limit: Int) async throws -> [AddressCandidate]
    
    /// Try DB once with short timeout, else throw (caller falls back to Mapbox)
    /// Default implementation falls back to regular nearest() call
    func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int, campaignId: UUID?) async throws -> [AddressCandidate]
}

// MARK: - Default Implementation

extension AddressProvider {
    /// Default implementation that just calls nearest() - used by MapboxProvider
    public func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int = 1200, campaignId: UUID? = nil) async throws -> [AddressCandidate] {
        return try await nearest(center: center, limit: limit, campaignId: campaignId)
    }
}


