import Foundation
import SwiftUI
import CoreLocation
import Combine

/// Hook for managing map snapshot state and API calls
@MainActor
final class UseMapSnapshot: ObservableObject {
    @Published var mapImage: UIImage?
    @Published var isLoading = false
    @Published var error: String?
    
    private let mapAPI: MapAPIType
    
    init(mapAPI: MapAPIType? = nil) {
        if let mapAPI = mapAPI {
            self.mapAPI = mapAPI
        } else {
            self.mapAPI = MapboxMapAPI(accessToken: MapboxManager.shared.accessToken)
        }
    }
    
    /// Load a map snapshot with optional markers
    func loadMapSnapshot(center: CLLocationCoordinate2D, 
                        markers: [MapMarker] = []) {
        Task {
            await loadMapSnapshotAsync(center: center, markers: markers)
        }
    }
    
    private func loadMapSnapshotAsync(center: CLLocationCoordinate2D, 
                                    markers: [MapMarker]) async {
        print("🗺️ [MAP DEBUG] Loading map snapshot for center: \(center)")
        print("🗺️ [MAP DEBUG] Markers count: \(markers.count)")
        
        isLoading = true
        error = nil
        
        do {
            let imageData = try await mapAPI.getMapSnapshot(center: center, markers: markers)
            let image = UIImage(data: imageData)
            
            await MainActor.run {
                self.mapImage = image
                self.isLoading = false
                print("🗺️ [MAP DEBUG] Map snapshot loaded successfully")
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
                print("❌ [MAP DEBUG] Map snapshot failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Clear the current map image
    func clear() {
        mapImage = nil
        error = nil
        isLoading = false
    }
}
