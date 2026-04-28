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
    let headingPresentationState: MapHeadingPresentationState

    private let sessionLineSourceId = "session-line-source"
    private let sessionLineLayerId = "session-line-layer"
    private let headingConeSourceId = "session-heading-cone-source"
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
        context.coordinator.updateUserLocation(currentLocation, headingState: headingPresentationState)
        context.coordinator.updateCamera(location: currentLocation, headingState: headingPresentationState)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sessionLineSourceId: sessionLineSourceId,
            sessionLineLayerId: sessionLineLayerId,
            headingConeSourceId: headingConeSourceId,
            userLocationSourceId: userLocationSourceId,
            userLocationLayerId: userLocationLayerId
        )
    }

    @MainActor
    class Coordinator {
        let sessionLineSourceId: String
        let sessionLineLayerId: String
        let headingConeSourceId: String
        let userLocationSourceId: String
        let userLocationLayerId: String
        weak var mapView: MapView?
        private var isSetup = false
        private var lastPathSignature: Int?
        private var lastUserLocationSnapshot: SessionUserLocationSnapshot?
        private var lastCameraSnapshot: SessionCameraSnapshot?

        init(
            sessionLineSourceId: String,
            sessionLineLayerId: String,
            headingConeSourceId: String,
            userLocationSourceId: String,
            userLocationLayerId: String
        ) {
            self.sessionLineSourceId = sessionLineSourceId
            self.sessionLineLayerId = sessionLineLayerId
            self.headingConeSourceId = headingConeSourceId
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
            
            // Session path source is retained, but the breadcrumb line is intentionally hidden.
            do {
                var source = GeoJSONSource(id: sessionLineSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)
                print("✅ [SessionMap] Added hidden session path source")
            } catch {
                print("❌ [SessionMap] Failed to add session path source: \(error)")
            }

            do {
                var source = GeoJSONSource(id: headingConeSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                for band in UserHeadingConeBand.allCases {
                    var layer = FillLayer(
                        id: Self.headingLayerId(for: band),
                        source: headingConeSourceId
                    )
                    layer.filter = Exp(.eq) {
                        Exp(.get) { "band" }
                        band.rawValue
                    }
                    layer.fillColor = .constant(UserHeadingIndicatorRenderer.styleColor(for: band))
                    layer.fillOpacity = .expression(
                        Exp(.coalesce) {
                            Exp(.get) { "opacity" }
                            1.0
                        }
                    )
                    try map.addLayer(layer)
                }
            } catch {
                print("❌ [SessionMap] Failed to add heading cone layer: \(error)")
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
                symbolLayer.iconOpacity = .expression(
                    Exp(.coalesce) {
                        Exp(.get) { "headingOpacity" }
                        0.0
                    }
                )
                symbolLayer.iconSize = .constant(1.0)
                symbolLayer.iconAllowOverlap = .constant(true)
                symbolLayer.iconIgnorePlacement = .constant(true)
                symbolLayer.iconAnchor = .constant(.center)

                try map.addLayer(symbolLayer)
                print("✅ [SessionMap] Added user location puck + arrow layer")
            } catch {
                print("❌ [SessionMap] Failed to add user location layer: \(error)")
            }

            let sessionManager = SessionManager.shared
            updatePath(coordinates: sessionManager.pathCoordinates)
            updateUserLocation(
                sessionManager.currentLocation,
                headingState: sessionManager.headingPresentationState
            )
            updateCamera(
                location: sessionManager.currentLocation,
                headingState: sessionManager.headingPresentationState
            )
        }

        /// Keeps the session path source empty so the breadcrumb line is not rendered.
        func updatePath(coordinates: [CLLocationCoordinate2D]) {
            guard let map = mapView?.mapboxMap else { return }
            guard map.sourceExists(withId: sessionLineSourceId) else { return }
            let signature = Self.coordinateSignature(for: coordinates)
            guard lastPathSignature != signature else { return }
            lastPathSignature = signature
            map.updateGeoJSONSource(
                withId: sessionLineSourceId,
                geoJSON: .featureCollection(FeatureCollection(features: []))
            )
        }

        func updateUserLocation(_ location: CLLocation?, headingState: MapHeadingPresentationState) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap else { return }

            let emptyCollection = FeatureCollection(features: [])
            guard let loc = location else {
                map.updateGeoJSONSource(withId: userLocationSourceId, geoJSON: .featureCollection(emptyCollection))
                if map.sourceExists(withId: headingConeSourceId) {
                    map.updateGeoJSONSource(withId: headingConeSourceId, geoJSON: .featureCollection(emptyCollection))
                }
                return
            }
            guard map.sourceExists(withId: userLocationSourceId) else { return }
            let snapshot = SessionUserLocationSnapshot(location: loc.coordinate, headingState: headingState)
            guard lastUserLocationSnapshot != snapshot else { return }
            lastUserLocationSnapshot = snapshot

            var feature = Feature(geometry: .point(Point(loc.coordinate)))
            feature.properties = [
                "heading": .number(Double(headingState.heading ?? 0)),
                "headingOpacity": .number(headingState.heading != nil ? 1.0 : 0.0)
            ]
            map.updateGeoJSONSource(withId: userLocationSourceId, geoJSON: .feature(feature))

            if map.sourceExists(withId: headingConeSourceId) {
                let collection = UserHeadingIndicatorRenderer.featureCollection(
                    center: loc.coordinate,
                    presentationState: headingState
                )
                map.updateGeoJSONSource(withId: headingConeSourceId, geoJSON: .featureCollection(collection))
            }
        }

        func updateCamera(location: CLLocation?, headingState: MapHeadingPresentationState) {
            guard let mapView = mapView,
                  let location = location else { return }
            let heading = headingState.heading ?? lastCameraSnapshot?.heading ?? 0

            let snapshot = SessionCameraSnapshot(location: location.coordinate, heading: heading)
            if let lastCameraSnapshot {
                let movedDistance = GeospatialUtilities.distanceMeters(lastCameraSnapshot.location, snapshot.location)
                let headingDelta = abs(CLLocationDirection.shortestCompassDelta(from: lastCameraSnapshot.heading, to: snapshot.heading))
                guard movedDistance >= 1.5 || headingDelta >= 3 else { return }
            }

            let shouldAnimate = lastCameraSnapshot != nil
            lastCameraSnapshot = snapshot

            // Set camera to follow user with 3D tilt
            let cameraOptions = CameraOptions(
                center: location.coordinate,
                zoom: 18.0,
                bearing: heading,
                pitch: 60.0
            )

            if shouldAnimate {
                mapView.camera.ease(
                    to: cameraOptions,
                    duration: 0.8
                )
            } else {
                mapView.mapboxMap?.setCamera(to: cameraOptions)
            }
        }

        private static func coordinateSignature(for coordinates: [CLLocationCoordinate2D]) -> Int {
            var hasher = Hasher()
            hasher.combine(coordinates.count)
            if let first = coordinates.first {
                hasher.combine(Self.quantizedCoordinate(first))
            }
            if coordinates.count > 2 {
                hasher.combine(Self.quantizedCoordinate(coordinates[coordinates.count / 2]))
            }
            if let last = coordinates.last {
                hasher.combine(Self.quantizedCoordinate(last))
            }
            return hasher.finalize()
        }

        private static func quantizedCoordinate(_ coordinate: CLLocationCoordinate2D) -> QuantizedCoordinate {
            QuantizedCoordinate(coordinate: coordinate)
        }

        private static func headingLayerId(for band: UserHeadingConeBand) -> String {
            "session-user-heading-\(band.rawValue)"
        }
    }
}

private struct QuantizedCoordinate: Hashable {
    let latitudeE6: Int
    let longitudeE6: Int

    init(coordinate: CLLocationCoordinate2D) {
        latitudeE6 = Int((coordinate.latitude * 1_000_000).rounded())
        longitudeE6 = Int((coordinate.longitude * 1_000_000).rounded())
    }
}

private struct SessionUserLocationSnapshot: Equatable {
    let location: QuantizedCoordinate
    let headingState: MapHeadingPresentationState

    init(location: CLLocationCoordinate2D, headingState: MapHeadingPresentationState) {
        self.location = QuantizedCoordinate(coordinate: location)
        self.headingState = headingState
    }
}

private struct SessionCameraSnapshot {
    let location: CLLocationCoordinate2D
    let heading: CLLocationDirection
}
