import SwiftUI
import MapboxMaps
import CoreLocation

struct SessionMapboxViewRepresentable: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let currentLocation: CLLocation?
    let currentHeading: CLLocationDirection
    
    private let sessionLineSourceId = "session-line-source"
    private let sessionLineLayerId = "session-line-layer"
    private let session3DBuildingsLayerId = "session-3d-buildings"
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Configure ornaments
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
        mapView.ornaments.options.compass.visibility = .adaptive
        
        // Load outdoors style
        mapView.mapboxMap?.loadStyle(.outdoors)
        
        // Wait for map to load before adding layers
        mapView.mapboxMap?.onMapLoaded.observeNext { _ in
            context.coordinator.setupMap(mapView: mapView)
        }
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.updatePath(coordinates: coordinates)
        context.coordinator.updateCamera(location: currentLocation, heading: currentHeading)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionLineSourceId: sessionLineSourceId,
            sessionLineLayerId: sessionLineLayerId,
            session3DBuildingsLayerId: session3DBuildingsLayerId
        )
    }
    
    class Coordinator {
        let sessionLineSourceId: String
        let sessionLineLayerId: String
        let session3DBuildingsLayerId: String
        weak var mapView: MapView?
        private var isSetup = false
        
        init(
            sessionLineSourceId: String,
            sessionLineLayerId: String,
            session3DBuildingsLayerId: String
        ) {
            self.sessionLineSourceId = sessionLineSourceId
            self.sessionLineLayerId = sessionLineLayerId
            self.session3DBuildingsLayerId = session3DBuildingsLayerId
        }
        
        func setupMap(mapView: MapView) {
            guard !isSetup else { return }
            isSetup = true
            
            guard let map = mapView.mapboxMap else { return }
            
            // Wait for style to be fully loaded before adding layers
            if map.isStyleLoaded {
                addAllLayers(to: map)
            } else {
                // If style not loaded yet, wait for it
                map.onStyleLoaded.observeNext { [weak self] _ in
                    guard let self = self, let map = mapView.mapboxMap else { return }
                    self.addAllLayers(to: map)
                }
            }
        }
        
        private func addAllLayers(to map: MapboxMap) {
            // Add terrain (using mapbox-dem source if available)
            do {
                // Terrain requires a source ID string, typically "mapbox-dem" for Mapbox terrain
                try map.style.setTerrain(Terrain(sourceId: "mapbox-dem"))
                print("✅ [SessionMap] Added terrain")
            } catch {
                print("⚠️ [SessionMap] Failed to set terrain: \(error)")
            }
            
            // Add 3D buildings layer - ensure it's added after style is loaded
            do {
                // Check if layer already exists
                if map.allLayerIdentifiers.contains(where: { $0.id == session3DBuildingsLayerId }) {
                    try map.removeLayer(withId: session3DBuildingsLayerId)
                }
                
                var layer = FillExtrusionLayer(id: session3DBuildingsLayerId, source: "composite")
                layer.sourceLayer = "building"
                layer.minZoom = 13
                layer.fillExtrusionOpacity = .constant(0.9)
                layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
                layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
                layer.fillExtrusionColor = .constant(StyleColor(.white))
                
                try map.addLayer(layer)
                print("✅ [SessionMap] Added 3D buildings layer")
            } catch {
                print("❌ [SessionMap] Failed to add 3D buildings: \(error)")
            }
            
            // Create empty GeoJSON source for session line
            do {
                var source = GeoJSONSource(id: sessionLineSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)
                
                // Add red line layer (after buildings layer exists)
                var lineLayer = LineLayer(id: sessionLineLayerId, source: sessionLineSourceId)
                lineLayer.lineColor = .constant(StyleColor(.red))
                lineLayer.lineWidth = .constant(4.0)
                lineLayer.lineOpacity = .constant(1.0)
                lineLayer.lineJoin = .constant(.round)
                lineLayer.lineCap = .constant(.round)
                
                try map.addLayer(lineLayer, layerPosition: .above(session3DBuildingsLayerId))
                print("✅ [SessionMap] Added session line layer")
            } catch {
                print("❌ [SessionMap] Failed to add session line: \(error)")
            }
        }
        
        func updatePath(coordinates: [CLLocationCoordinate2D]) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap,
                  !coordinates.isEmpty else { return }
            
            // Convert coordinates to Mapbox LineString
            let lineCoords = coordinates.map { coord in
                LocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
            }
            
            let lineString = LineString(lineCoords)
            let feature = Feature(geometry: .lineString(lineString))
            
            do {
                // Update GeoJSON source with new path
                try map.updateGeoJSONSource(withId: sessionLineSourceId, geoJSON: .feature(feature))
            } catch {
                print("⚠️ [SessionMap] Failed to update path: \(error)")
            }
        }
        
        func updateCamera(location: CLLocation?, heading: CLLocationDirection) {
            guard let mapView = mapView,
                  let location = location else { return }
            
            // Set camera to follow user with 3D tilt
            let cameraOptions = CameraOptions(
                center: location.coordinate,
                zoom: 18.0,
                bearing: heading,
                pitch: 60.0
            )
            
            // Use ease for smooth camera transitions
            mapView.camera.ease(
                to: cameraOptions,
                duration: 0.8
            )
        }
    }
}

