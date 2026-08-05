import Foundation
import MapboxMaps

// MARK: - Mapbox Bridge for Layer Updates

/// Bridge class to handle MapView updates from SwiftUI
final class MapboxBridge {
    static let shared = MapboxBridge()
    private init() {}
    
    weak var mapView: MapView?
    
    func updatePolygons(_ featureCollection: GeoJSONFeatureCollection) {
        guard let mapView = mapView else { 
            print("⚠️ [BRIDGE] No MapView available for polygon update")
            return 
        }
        
        print("🏗️ [BRIDGE] Updating polygons: \(featureCollection.features.count) features")
        
        let base = "campaign-buildings"
        let srcId = "\(base)-src"
        
        do {
            try BuildingLayers.addOrUpdate(
                map: mapView.mapboxMap,
                sourceId: srcId,
                featureCollection: featureCollection
            )
            print("✅ [BRIDGE] Successfully updated building layers")
        } catch {
            print("❌ [BRIDGE] Failed to update building layers: \(error)")
        }
    }
    
    func setSelectedBuilding(_ addressId: UUID?) {
        guard let mapView = mapView else { return }
        
        let base = "campaign-buildings"
        let srcId = "\(base)-src"
        
        do {
            try BuildingLayers.setSelected(
                map: mapView.mapboxMap,
                selectedAddressId: addressId,
                sourceId: srcId
            )
        } catch {
            print("❌ [BRIDGE] Failed to set selected building: \(error)")
        }
    }
}
