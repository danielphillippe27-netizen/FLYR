import Foundation
import Combine
import CoreLocation
import MapboxMaps

// MARK: - Use Building Outlines Hook

@MainActor
final class UseBuildingOutlines: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var outlines: [CampaignAddress] = []
    @Published var isReady = false
    
    private let buildingsAPI = BuildingsAPI.shared
    private var highlightService: BuildingHighlightService?
    
    /// Load building outlines for a list of addresses
    func load(for addresses: [AddressCandidate]) async {
        guard !addresses.isEmpty else {
            outlines = []
            return
        }
        
        isLoading = true
        error = nil
        outlines = []
        
        defer { isLoading = false }
        
        do {
            // Use TaskGroup to fetch outlines in parallel for better performance
            let results = try await withThrowingTaskGroup(of: (AddressCandidate, [[CLLocationCoordinate2D]]?).self) { group in
                var results: [(AddressCandidate, [[CLLocationCoordinate2D]]?)] = []
                
                // Add tasks for each address
                for address in addresses {
                    group.addTask {
                        let outline = try await self.buildingsAPI.buildingOutline(for: address)
                        return (address, outline)
                    }
                }
                
                // Collect results
                for try await result in group {
                    results.append(result)
                }
                
                return results
            }
            
            // Convert results to CampaignAddress objects
            let campaignAddresses = results.map { (address, outline) in
                CampaignAddress(
                    address: address.address,
                    coordinate: address.coordinate,
                    buildingOutline: outline
                )
            }
            
            outlines = campaignAddresses
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    /// Attach to a MapView for rendering building highlights
    /// - Parameter mapView: The MapView to attach to
    func attach(mapView: MapView) {
        highlightService = BuildingHighlightService(mapView: mapView)
        highlightService?.ensureLayers()
        isReady = true
    }
    
    /// Render building highlights for given coordinates
    /// - Parameter coords: Array of coordinates to highlight
    func render(for coords: [CLLocationCoordinate2D]) {
        Task { await highlightService?.highlightBuildings(coords: coords) }
    }
    
    /// Clear outlines and reset state
    func clear() {
        outlines = []
        error = nil
        isLoading = false
    }
}
