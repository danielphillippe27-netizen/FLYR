import SwiftUI
import MapboxMaps
import CoreLocation

// MARK: - SwiftUI MapView Container

/// SwiftUI wrapper for Mapbox MapView with proper initialization
struct MapboxViewContainer: UIViewRepresentable {
    let featureCollection: GeoJSONFeatureCollection?
    let centerCoordinate: CLLocationCoordinate2D?
    let zoomLevel: Double
    
    init(
        featureCollection: GeoJSONFeatureCollection? = nil,
        centerCoordinate: CLLocationCoordinate2D? = nil,
        zoomLevel: Double = 15
    ) {
        self.featureCollection = featureCollection
        self.centerCoordinate = centerCoordinate
        self.zoomLevel = zoomLevel
    }
    
    func makeUIView(context: Context) -> MapView {
        print("🗺️ [CONTAINER] Creating MapView with proper frame")
        
        // Create with real size to avoid {64,64} warnings
        let mapView = MapView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 340)
        )
        
        // Register with bridge
        MapboxBridge.shared.mapView = mapView
        
        // Use custom light style
        try? mapView.mapboxMap.loadStyleURI(StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!)
        
        // Set camera position when map loads
        if let center = centerCoordinate {
            mapView.mapboxMap.onNext(event: .mapLoaded) { _ in
                let cameraOptions = CameraOptions(
                    center: center,
                    zoom: zoomLevel
                )
                mapView.mapboxMap.setCamera(to: cameraOptions)
                print("🗺️ [CONTAINER] Set camera to center: \(center) at zoom \(zoomLevel)")
            }
        }
        
        print("✅ [CONTAINER] MapView created and registered with bridge")
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Update camera if center coordinate changes
        if let center = centerCoordinate {
            let cameraOptions = CameraOptions(
                center: center,
                zoom: zoomLevel
            )
            mapView.mapboxMap.setCamera(to: cameraOptions)
        }
    }
}
