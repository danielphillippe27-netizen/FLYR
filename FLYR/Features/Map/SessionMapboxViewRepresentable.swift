import SwiftUI
import MapboxMaps
import CoreLocation
import UIKit

/// Arrow image for user location puck (points up = north); rotation is applied via symbol layer.
private enum SessionMapArrowImage {
    static let id = "session-user-location-arrow"
    
    static func makeImage() -> UIImage {
        let size: CGFloat = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let path = UIBezierPath()
            // Arrow pointing up: wide at bottom, point at top
            let w: CGFloat = 10
            let h: CGFloat = 14
            let cx = size / 2
            let cy = size / 2
            path.move(to: CGPoint(x: cx, y: cy - h))
            path.addLine(to: CGPoint(x: cx + w, y: cy + h * 0.4))
            path.addLine(to: CGPoint(x: cx + w * 0.35, y: cy + h * 0.2))
            path.addLine(to: CGPoint(x: cx + w * 0.35, y: cy + h))
            path.addLine(to: CGPoint(x: cx - w * 0.35, y: cy + h))
            path.addLine(to: CGPoint(x: cx - w * 0.35, y: cy + h * 0.2))
            path.addLine(to: CGPoint(x: cx - w, y: cy + h * 0.4))
            path.close()
            UIColor.white.setStroke()
            UIColor.systemRed.setFill()
            path.lineWidth = 2
            path.lineJoinStyle = .round
            path.stroke()
            path.fill()
        }
    }
}

struct SessionMapboxViewRepresentable: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let currentLocation: CLLocation?
    let currentHeading: CLLocationDirection

    private let sessionLineSourceId = "session-line-source"
    private let sessionLineLayerId = "session-line-layer"
    private let userLocationSourceId = "session-user-location-source"
    private let userLocationLayerId = "session-user-location-layer"
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Configure ornaments (logo/attribution visibility is @_spi in Mapbox SDK so we can't hide them via options)
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .adaptive
        
        // Load custom light style
        mapView.mapboxMap?.loadStyle(StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!)
        
        // Wait for map to load before adding layers
        mapView.mapboxMap?.onMapLoaded.observeNext { _ in
            context.coordinator.setupMap(mapView: mapView)
        }
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.updatePath(coordinates: coordinates)
        context.coordinator.updateUserLocation(currentLocation, heading: currentHeading)
        context.coordinator.updateCamera(location: currentLocation, heading: currentHeading)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionLineSourceId: sessionLineSourceId,
            sessionLineLayerId: sessionLineLayerId,
            userLocationSourceId: userLocationSourceId,
            userLocationLayerId: userLocationLayerId
        )
    }

    class Coordinator {
        let sessionLineSourceId: String
        let sessionLineLayerId: String
        let userLocationSourceId: String
        let userLocationLayerId: String
        weak var mapView: MapView?
        private var isSetup = false

        init(
            sessionLineSourceId: String,
            sessionLineLayerId: String,
            userLocationSourceId: String,
            userLocationLayerId: String
        ) {
            self.sessionLineSourceId = sessionLineSourceId
            self.sessionLineLayerId = sessionLineLayerId
            self.userLocationSourceId = userLocationSourceId
            self.userLocationLayerId = userLocationLayerId
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
            
            // No Mapbox 3D buildings — app shows only "my" (campaign) buildings elsewhere; session map is flat + path only
            
            // Create empty GeoJSON source for session path (red line like Strava)
            do {
                var source = GeoJSONSource(id: sessionLineSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                var lineLayer = LineLayer(id: sessionLineLayerId, source: sessionLineSourceId)
                lineLayer.lineColor = .constant(StyleColor(.red))
                lineLayer.lineWidth = .constant(5.0)
                lineLayer.lineOpacity = .constant(1.0)
                lineLayer.lineJoin = .constant(.round)
                lineLayer.lineCap = .constant(.round)

                try map.addLayer(lineLayer)
                print("✅ [SessionMap] Added session path line layer")
            } catch {
                print("❌ [SessionMap] Failed to add session line: \(error)")
            }

            // User location: arrow that rotates with heading
            do {
                try map.addImage(SessionMapArrowImage.makeImage(), id: SessionMapArrowImage.id)
                var source = GeoJSONSource(id: userLocationSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                var symbolLayer = SymbolLayer(id: userLocationLayerId, source: userLocationSourceId)
                symbolLayer.iconImage = .constant(.name(SessionMapArrowImage.id))
                symbolLayer.iconRotate = .expression(Exp(.get) { "heading" })
                symbolLayer.iconSize = .constant(1.0)
                symbolLayer.iconAllowOverlap = .constant(true)
                symbolLayer.iconIgnorePlacement = .constant(true)
                symbolLayer.iconAnchor = .constant(.center)

                try map.addLayer(symbolLayer)
                print("✅ [SessionMap] Added user location arrow layer")
            } catch {
                print("❌ [SessionMap] Failed to add user location layer: \(error)")
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
                try map.updateGeoJSONSource(withId: sessionLineSourceId, geoJSON: .feature(feature))
            } catch {
                print("⚠️ [SessionMap] Failed to update path: \(error)")
            }
        }

        func updateUserLocation(_ location: CLLocation?, heading: CLLocationDirection) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap else { return }
            guard let loc = location else {
                // No location yet; keep previous or empty (don’t show marker at 0,0)
                return
            }
            var feature = Feature(geometry: .point(Point(loc.coordinate)))
            feature.properties = ["heading": .number(Double(heading))]
            do {
                try map.updateGeoJSONSource(withId: userLocationSourceId, geoJSON: .feature(feature))
            } catch {
                print("⚠️ [SessionMap] Failed to update user location: \(error)")
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

