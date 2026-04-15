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
    /// Road segments (Mapbox centerlines) for the campaign — drawn so the walking trail aligns with the road network.
    var roadCorridors: [StreetCorridor] = []

    private let sessionLineSourceId = "session-line-source"
    private let sessionLineLayerId = "session-line-layer"
    private let sessionRoadsSourceId = "session-roads-source"
    private let sessionRoadsLayerId = "session-roads-layer"
    private let userLocationSourceId = "session-user-location-source"
    private let userLocationLayerId = "session-user-location-layer"
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: CGRect(x: 0, y: 0, width: 320, height: 260))
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let scale = mapView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0 {
            mapView.contentScaleFactor = scale
        }

        // Configure ornaments (logo/attribution visibility is @_spi in Mapbox SDK so we can't hide them via options)
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .adaptive
        
        // Load custom light style
        mapView.mapboxMap?.loadStyle(StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!)
        
        // Wait for map to load before adding layers
        _ = mapView.mapboxMap?.onMapLoaded.observeNext { _ in
            context.coordinator.setupMap(mapView: mapView)
        }
        
        context.coordinator.mapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        let scale = mapView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0, mapView.contentScaleFactor != scale {
            mapView.contentScaleFactor = scale
        }
        context.coordinator.updatePath(coordinates: coordinates)
        context.coordinator.updateRoads(roadCorridors: roadCorridors)
        context.coordinator.updateUserLocation(currentLocation, heading: currentHeading)
        context.coordinator.updateCamera(location: currentLocation, heading: currentHeading)
        mapView.setNeedsLayout()
        mapView.layoutIfNeeded()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionLineSourceId: sessionLineSourceId,
            sessionLineLayerId: sessionLineLayerId,
            sessionRoadsSourceId: sessionRoadsSourceId,
            sessionRoadsLayerId: sessionRoadsLayerId,
            userLocationSourceId: userLocationSourceId,
            userLocationLayerId: userLocationLayerId
        )
    }

    @MainActor
    class Coordinator {
        let sessionLineSourceId: String
        let sessionLineLayerId: String
        let sessionRoadsSourceId: String
        let sessionRoadsLayerId: String
        let userLocationSourceId: String
        let userLocationLayerId: String
        weak var mapView: MapView?
        private var isSetup = false

        init(
            sessionLineSourceId: String,
            sessionLineLayerId: String,
            sessionRoadsSourceId: String,
            sessionRoadsLayerId: String,
            userLocationSourceId: String,
            userLocationLayerId: String
        ) {
            self.sessionLineSourceId = sessionLineSourceId
            self.sessionLineLayerId = sessionLineLayerId
            self.sessionRoadsSourceId = sessionRoadsSourceId
            self.sessionRoadsLayerId = sessionRoadsLayerId
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
                _ = map.onStyleLoaded.observeNext { [weak self] _ in
                    guard let self = self, let map = mapView.mapboxMap else { return }
                    self.addAllLayers(to: map)
                }
            }
        }
        
        private func addAllLayers(to map: MapboxMap) {
            // Add terrain (using mapbox-dem source if available)
            do {
                // Terrain requires a source ID string, typically "mapbox-dem" for Mapbox terrain
                try map.setTerrain(Terrain(sourceId: "mapbox-dem"))
                print("✅ [SessionMap] Added terrain")
            } catch {
                print("⚠️ [SessionMap] Failed to set terrain: \(error)")
            }
            
            // No Mapbox 3D buildings — app shows only "my" (campaign) buildings elsewhere; session map is flat + path only
            
            // Campaign road segments (Mapbox centerlines) — drawn first so the walking trail appears on top
            do {
                var roadsSource = GeoJSONSource(id: sessionRoadsSourceId)
                roadsSource.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(roadsSource)
                var roadsLayer = LineLayer(id: sessionRoadsLayerId, source: sessionRoadsSourceId)
                roadsLayer.lineColor = .constant(StyleColor(UIColor.gray.withAlphaComponent(0.6)))
                roadsLayer.lineWidth = .constant(3.0)
                roadsLayer.lineOpacity = .constant(0.9)
                roadsLayer.lineJoin = .constant(.round)
                roadsLayer.lineCap = .constant(.round)
                try map.addLayer(roadsLayer)
                print("✅ [SessionMap] Added session roads (walking trail) layer")
            } catch {
                print("❌ [SessionMap] Failed to add session roads layer: \(error)")
            }
            
            // Session path: smooth line (round join/cap), red, slight transparency
            do {
                var source = GeoJSONSource(id: sessionLineSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                var lineLayer = LineLayer(id: sessionLineLayerId, source: sessionLineSourceId)
                lineLayer.lineColor = .constant(StyleColor(.red))
                lineLayer.lineWidth = .constant(5.0)
                lineLayer.lineOpacity = .constant(0.8)
                lineLayer.lineJoin = .constant(.round)
                lineLayer.lineCap = .constant(.round)

                try map.addLayer(lineLayer)
                print("✅ [SessionMap] Added session path line layer")
            } catch {
                print("❌ [SessionMap] Failed to add session line: \(error)")
            }

            // User location: puck (outer glow + inner circle) then arrow that rotates with heading
            do {
                try map.addImage(SessionMapArrowImage.makeImage(), id: SessionMapArrowImage.id)
                var source = GeoJSONSource(id: userLocationSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                var puckOuter = CircleLayer(id: "\(userLocationLayerId)-puck-outer", source: userLocationSourceId)
                puckOuter.circleRadius = .constant(14)
                puckOuter.circleColor = .constant(StyleColor(UIColor.red.withAlphaComponent(0.45)))
                puckOuter.circleOpacity = .constant(1.0)
                puckOuter.circleStrokeWidth = .constant(0)
                try map.addLayer(puckOuter)

                var puckInner = CircleLayer(id: "\(userLocationLayerId)-puck-inner", source: userLocationSourceId)
                puckInner.circleRadius = .constant(6)
                puckInner.circleColor = .constant(StyleColor(.white))
                puckInner.circleOpacity = .constant(1.0)
                puckInner.circleStrokeWidth = .constant(0)
                try map.addLayer(puckInner)

                var symbolLayer = SymbolLayer(id: userLocationLayerId, source: userLocationSourceId)
                symbolLayer.iconImage = .constant(.name(SessionMapArrowImage.id))
                symbolLayer.iconRotate = .expression(Exp(.get) { "heading" })
                symbolLayer.iconSize = .constant(1.0)
                symbolLayer.iconAllowOverlap = .constant(true)
                symbolLayer.iconIgnorePlacement = .constant(true)
                symbolLayer.iconAnchor = .constant(.center)

                try map.addLayer(symbolLayer)
                print("✅ [SessionMap] Added user location puck + arrow layer")
            } catch {
                print("❌ [SessionMap] Failed to add user location layer: \(error)")
            }
        }

        /// Updates the session polyline from normalized (centerline) or raw segments. Display only — do NOT use this path for visit scoring.
        func updatePath(coordinates: [CLLocationCoordinate2D]) {
            guard let map = mapView?.mapboxMap else { return }
            let segments = SessionManager.shared.renderPathSegments()
            let features = segments
                .filter { $0.count >= 2 }
                .map { segment -> Feature in
                    let lineCoords = segment.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    return Feature(geometry: .lineString(LineString(lineCoords)))
                }
            let collection = FeatureCollection(features: features)
            map.updateGeoJSONSource(withId: sessionLineSourceId, geoJSON: .featureCollection(collection))
        }
        
        func updateRoads(roadCorridors: [StreetCorridor]) {
            guard let map = mapView?.mapboxMap else { return }
            guard map.sourceExists(withId: sessionRoadsSourceId) else { return }
            let features = roadCorridors
                .filter { $0.polyline.count >= 2 }
                .map { corridor -> Feature in
                    let lineCoords = corridor.polyline.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    return Feature(geometry: .lineString(LineString(lineCoords)))
                }
            let collection = FeatureCollection(features: features)
            map.updateGeoJSONSource(withId: sessionRoadsSourceId, geoJSON: .featureCollection(collection))
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
            map.updateGeoJSONSource(withId: userLocationSourceId, geoJSON: .feature(feature))
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
