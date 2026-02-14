import SwiftUI
import CoreLocation
import Combine

// MARK: - Use Addresses Hook

/// Modern hook for address management with protocol-based dependency injection
/// Provides clean separation between UI state and business logic
@MainActor
final class UseAddresses: ObservableObject {
    @Published private(set) var items: [AddressCandidate] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    
    private let repository: AddressRepository
    private let geoAdapter: GeoStreetAdapter
    
    public init(
        repository: AddressRepository? = nil,
        geoAdapter: GeoStreetAdapter? = nil
    ) {
        self.repository = repository ?? AddressService.shared
        self.geoAdapter = geoAdapter ?? GeoStreetAdapter()
    }
    
    /// Fetch nearest addresses to a center point
    /// - Parameters:
    ///   - center: Center coordinate for search
    ///   - target: Target number of addresses to return
    ///   - radiusMeters: Search radius in meters (default: 30)
    ///   - campaignId: Optional; when set, backend uses it for generate-address-list (New Campaign flow passes nil → Mapbox)
    func fetchNearest(center: CLLocationCoordinate2D, target: Int, radiusMeters: Double = 30, campaignId: UUID? = nil) {
        Task { [weak self] in
            guard let self else { return }
            
            self.isLoading = true
            self.error = nil
            
            do {
                self.items = try await repository.nearestAddresses(
                    at: center,
                    limit: target,
                    radiusMeters: radiusMeters,
                    campaignId: campaignId
                )
            } catch {
                self.error = error.localizedDescription
            }
            
            self.isLoading = false
        }
    }
    
    /// Fetch addresses on the same street as a seed location
    /// - Parameters:
    ///   - seed: Seed coordinate for street determination
    ///   - target: Target number of addresses to return
    ///   - street: Optional street name (if nil, will reverse geocode)
    ///   - locality: Optional locality name
    func fetchSameStreet(seed: CLLocationCoordinate2D, target: Int, street: String? = nil, locality: String? = nil) {
        Task { [weak self] in
            guard let self else { return }
            
            self.isLoading = true
            self.error = nil
            
            do {
                // Determine street name and locality
                let (streetName, localityName): (String, String?)
                if let street = street {
                    streetName = street
                    localityName = locality
                } else {
                    let result = try await geoAdapter.reverseSeedStreet(at: seed)
                    streetName = result.street
                    localityName = result.locality
                }
                
                // Use localityName in the seed candidate for better context
                let seedAddress = localityName?.isEmpty == false ? "Seed Location, \(localityName!)" : "Seed Location"
                
                // Create seed candidate for repository call
                let seedCandidate = AddressCandidate(
                    address: seedAddress,
                    coordinate: seed,
                    distanceMeters: 0,
                    number: "",
                    street: streetName,
                    houseKey: ""
                )
                
                self.items = try await repository.sameStreet(seed: seedCandidate, limit: target)
            } catch {
                self.error = error.localizedDescription
            }
            
            self.isLoading = false
        }
    }
    
    /// Clear results and reset state
    func clear() {
        items = []
        error = nil
        isLoading = false
    }
}
