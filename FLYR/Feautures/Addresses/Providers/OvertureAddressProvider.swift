import Foundation
import CoreLocation

// MARK: - Overture Address Provider

/// Address provider backed by backend (Lambda + S3) via generate-address-list API.
public struct OvertureAddressProvider: AddressProvider {
    private let service = OvertureAddressService.shared

    public init() {}

    public func nearest(center: CLLocationCoordinate2D, limit: Int, campaignId: UUID? = nil) async throws -> [AddressCandidate] {
        return try await service.getAddressesNearest(center: center, limit: limit, campaignId: campaignId)
    }

    /// Same-street not supported by backend; throw so AddressService falls back to Mapbox.
    public func sameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, limit: Int) async throws -> [AddressCandidate] {
        throw NSError(domain: "OvertureAddressProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Same-street not supported by backend; use Mapbox fallback."])
    }

    /// Try backend once with timeout; throws on timeout so caller can fall back to Mapbox.
    public func tryDBOnce(center: CLLocationCoordinate2D, limit: Int, timeoutMs: Int = 1200, campaignId: UUID? = nil) async throws -> [AddressCandidate] {
        try await withThrowingTaskGroup(of: [AddressCandidate].self) { group in
            group.addTask {
                try await self.nearest(center: center, limit: limit, campaignId: campaignId)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                throw NSError(domain: "OvertureAddressProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Backend timeout after \(timeoutMs)ms"])
            }
            let first = try await group.next() ?? []
            group.cancelAll()
            return first
        }
    }
}
