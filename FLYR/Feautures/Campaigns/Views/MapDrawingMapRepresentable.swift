import SwiftUI
import MapboxMaps
import CoreLocation

/// Mapbox MapView for polygon drawing (iOS parity with web Mapbox GL Draw draw_polygon).
/// Red styling: fill #ef4444 15%, stroke 3px, vertex circles. Tap to add; drag vertex to move; tap first again to close.
/// Uses v11-style map with 2D building footprints (campaign creation only), or satellite style when useSatellite is true.
/// Optionally shows a red stick-man location marker at the starting address (feet anchored at the point).
struct MapDrawingMapRepresentable: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    /// When set, a red stick-man marker is shown at this coordinate (starting address).
    var startingAddressCoordinate: CLLocationCoordinate2D?
    /// When set, this is the next-best camera fallback after the starting address.
    var userLocationCoordinate: CLLocationCoordinate2D?
    let polygonVertices: [CLLocationCoordinate2D]
    var useDarkStyle: Bool = false
    /// When true, shows satellite imagery (with street labels). When false, shows streets (light or dark).
    var useSatellite: Bool = false
    let onTap: (CLLocationCoordinate2D) -> Void
    let onMoveVertex: (Int, CLLocationCoordinate2D) -> Void

    private static let drawingBuildingsLayerId = "drawing-2d-buildings"
    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/streets-v11")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/dark-v11")!
    private static let satelliteStyleURI = StyleURI(rawValue: "mapbox://styles/mapbox/satellite-streets-v12")!

    private static func add2DBuildingsLayer(to map: MapboxMap, useDarkStyle: Bool) {
        guard !map.allLayerIdentifiers.contains(where: { $0.id == drawingBuildingsLayerId }) else { return }
        do {
            for layerId in map.allLayerIdentifiers.map(\.id) {
                let lower = layerId.lowercased()
                if (lower.contains("building") || lower.contains("structure")) && layerId != drawingBuildingsLayerId {
                    try? map.setLayerProperty(for: layerId, property: "visibility", value: "none")
                }
            }

            var layer = FillLayer(id: drawingBuildingsLayerId, source: "composite")
            layer.sourceLayer = "building"
            layer.minZoom = 10
            layer.filter = Exp(.match) {
                Exp(.get) { "type" }
                [
                    "commercial", "industrial", "retail", "warehouse", "office",
                    "church", "cathedral", "chapel", "temple", "mosque",
                    "hospital", "civic", "government", "public",
                    "university", "school", "college", "kindergarten",
                    "train_station", "transportation", "hangar",
                    "parking", "garage", "garages",
                    "service", "manufacture", "factory",
                    "supermarket", "hotel", "motel",
                    "stadium", "grandstand",
                    "fire_station", "barn", "silo", "greenhouse",
                    "kiosk", "roof", "ruins", "bridge", "construction"
                ]
                false
                true
            }
            let buildingFill = useDarkStyle ? UIColor(hex: "#111111")! : UIColor(hex: "#c8c1b2")!
            let buildingOutline = useDarkStyle ? UIColor(hex: "#0a0a0a")! : UIColor(hex: "#b5ad9d")!
            layer.fillColor = .constant(StyleColor(buildingFill))
            layer.fillOpacity = .constant(0.8)
            layer.fillOutlineColor = .constant(StyleColor(buildingOutline))

            let labelLayerId = map.allLayerIdentifiers.first { $0.id.lowercased().contains("label") }?.id
            if let labelLayerId {
                try map.addLayer(layer, layerPosition: .below(labelLayerId))
            } else {
                try map.addLayer(layer)
            }
        } catch {
            print("⚠️ [MapDrawing] Could not add 2D buildings layer: \(error)")
        }
    }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.ornaments.options.scaleBar.visibility = .visible
        mapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
        mapView.ornaments.options.compass.visibility = .adaptive
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.rotateEnabled = true

        let red = UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)

        // Polygon fill + outline as Polygon Annotations — always on top, like vertices.
        let polygonManager = mapView.annotations.makePolygonAnnotationManager()
        polygonManager.fillColor = StyleColor(red.withAlphaComponent(0.15))
        polygonManager.fillOpacity = 1.0
        polygonManager.fillOutlineColor = StyleColor(red)
        context.coordinator.polygonAnnotationManager = polygonManager

        // Vertices as Circle Annotations (half size: radius 5).
        let vertexManager = mapView.annotations.makeCircleAnnotationManager()
        vertexManager.circleRadius = 5
        vertexManager.circleColor = StyleColor(red)
        vertexManager.circleStrokeColor = StyleColor(.white)
        vertexManager.circleStrokeWidth = 1.5
        context.coordinator.vertexAnnotationManager = vertexManager

        // Red stick-man marker for starting address (feet anchored at the point).
        let startingMarkerManager = mapView.annotations.makePointAnnotationManager()
        context.coordinator.startingAddressMarkerManager = startingMarkerManager

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.numberOfTouchesRequired = 1
        // Tap only when map pan didn't happen (quick tap = add vertex; drag = pan map).
        tapGesture.require(toFail: mapView.gestures.panGestureRecognizer)
        mapView.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        panGesture.maximumNumberOfTouches = 1
        mapView.gestures.panGestureRecognizer.require(toFail: panGesture)
        mapView.addGestureRecognizer(panGesture)

        context.coordinator.mapView = mapView
        context.coordinator.onTap = onTap
        context.coordinator.onMoveVertex = onMoveVertex
        context.coordinator.fallbackCenter = center
        context.coordinator.startingAddressCoordinate = startingAddressCoordinate
        context.coordinator.userLocationCoordinate = userLocationCoordinate
        context.coordinator.polygonVertices = polygonVertices
        context.coordinator.updateStartingAddressMarker(at: startingAddressCoordinate)
        context.coordinator.useSatellite = useSatellite
        context.coordinator.useDarkStyle = useDarkStyle
        context.coordinator.bindStyleLoadedObserver(to: mapView)
        context.coordinator.applyStyleIfNeeded(on: mapView, force: true)

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onMoveVertex = onMoveVertex
        context.coordinator.fallbackCenter = center
        context.coordinator.startingAddressCoordinate = startingAddressCoordinate
        context.coordinator.userLocationCoordinate = userLocationCoordinate
        context.coordinator.polygonVertices = polygonVertices
        context.coordinator.useSatellite = useSatellite
        context.coordinator.useDarkStyle = useDarkStyle
        context.coordinator.applyStyleIfNeeded(on: mapView)
        context.coordinator.updatePolygonAnnotation(polygonVertices)
        context.coordinator.updateVertexAnnotations(polygonVertices)
        context.coordinator.updateStartingAddressMarker(at: startingAddressCoordinate)
        // Only set camera when no vertices yet (initial load). Once user starts drawing, don't recenter or zoom.
        if polygonVertices.isEmpty {
            context.coordinator.applyPreferredCamera(on: mapView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var mapView: MapView?
        var polygonAnnotationManager: PolygonAnnotationManager?
        var vertexAnnotationManager: CircleAnnotationManager?
        var startingAddressMarkerManager: PointAnnotationManager?
        var onTap: ((CLLocationCoordinate2D) -> Void)?
        var onMoveVertex: ((Int, CLLocationCoordinate2D) -> Void)?
        var fallbackCenter: CLLocationCoordinate2D?
        var startingAddressCoordinate: CLLocationCoordinate2D?
        var userLocationCoordinate: CLLocationCoordinate2D?
        var polygonVertices: [CLLocationCoordinate2D] = []
        private var lastCameraCenter: CLLocationCoordinate2D?
        private var lastPolygonCameraSignature: String?
        private var draggingVertexIndex: Int?
        var useSatellite: Bool = false
        var useDarkStyle: Bool = false
        private var styleLoadedObserver: AnyCancelable?
        private var loadedStyleRawValue: String?
        private var cameraToRestoreAfterStyleLoad: CameraSnapshot?

        private struct CameraSnapshot {
            let center: CLLocationCoordinate2D
            let zoom: CGFloat
            let bearing: CLLocationDirection
            let pitch: CGFloat
            let padding: UIEdgeInsets
        }

        private var desiredStyleURI: StyleURI {
            useSatellite ? MapDrawingMapRepresentable.satelliteStyleURI : (useDarkStyle ? MapDrawingMapRepresentable.darkStyleURI : MapDrawingMapRepresentable.lightStyleURI)
        }

        func bindStyleLoadedObserver(to mapView: MapView) {
            guard styleLoadedObserver == nil else { return }
            styleLoadedObserver = mapView.mapboxMap.onStyleLoaded.observeNext { [weak self, weak mapView] _ in
                guard let self, let mapView else { return }
                if !self.useSatellite {
                    MapDrawingMapRepresentable.add2DBuildingsLayer(to: mapView.mapboxMap, useDarkStyle: self.useDarkStyle)
                }
                if let snapshot = self.cameraToRestoreAfterStyleLoad {
                    mapView.mapboxMap.setCamera(to: CameraOptions(
                        center: snapshot.center,
                        padding: snapshot.padding,
                        zoom: snapshot.zoom,
                        bearing: snapshot.bearing,
                        pitch: snapshot.pitch
                    ))
                    self.cameraToRestoreAfterStyleLoad = nil
                    return
                }
                self.applyPreferredCamera(on: mapView, force: true)
            }
        }

        func applyStyleIfNeeded(on mapView: MapView, force: Bool = false) {
            let nextStyleRaw = desiredStyleURI.rawValue
            if !force, loadedStyleRawValue == nextStyleRaw { return }
            let cameraState = mapView.mapboxMap.cameraState
            if !force {
                cameraToRestoreAfterStyleLoad = CameraSnapshot(
                    center: cameraState.center,
                    zoom: cameraState.zoom,
                    bearing: cameraState.bearing,
                    pitch: cameraState.pitch,
                    padding: cameraState.padding
                )
            } else {
                cameraToRestoreAfterStyleLoad = nil
            }
            loadedStyleRawValue = nextStyleRaw
            mapView.mapboxMap.loadStyle(desiredStyleURI)
        }

        func updateStartingAddressMarker(at coordinate: CLLocationCoordinate2D?) {
            guard let manager = startingAddressMarkerManager else { return }
            guard let coordinate = coordinate, let image = LocationMarkerImage.markerImage else {
                manager.annotations = []
                return
            }
            var annotation = PointAnnotation(coordinate: LocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
            annotation.image = .init(image: image, name: LocationMarkerImage.imageName)
            annotation.iconAnchor = .bottom
            annotation.iconSize = 1.0
            manager.annotations = [annotation]
        }

        /// Hit radius in points for detecting tap/drag on a vertex (generous for small circles)
        private let vertexHitRadius: CGFloat = 20

        func updatePolygonAnnotation(_ vertices: [CLLocationCoordinate2D]) {
            guard vertices.count >= 3 else {
                polygonAnnotationManager?.annotations = []
                return
            }
            var ring = vertices.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if ring.first != ring.last, let first = ring.first {
                ring.append(first)
            }
            let polygon = Polygon([ring])
            let annotation = PolygonAnnotation(polygon: polygon)
            polygonAnnotationManager?.annotations = [annotation]
        }

        func updateVertexAnnotations(_ vertices: [CLLocationCoordinate2D]) {
            let annotations = vertices.map { coord in
                CircleAnnotation(centerCoordinate: LocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude))
            }
            vertexAnnotationManager?.annotations = annotations
        }

        /// Index of vertex near the given point (in map view coordinates), or nil.
        private func vertexIndexNear(point: CGPoint, in mapView: MapView) -> Int? {
            guard let map = mapView.mapboxMap else { return nil }
            for (index, vertex) in polygonVertices.enumerated() {
                let coord = LocationCoordinate2D(latitude: vertex.latitude, longitude: vertex.longitude)
                let vertexPoint = map.point(for: coord)
                let dx = point.x - vertexPoint.x
                let dy = point.y - vertexPoint.y
                if dx * dx + dy * dy <= vertexHitRadius * vertexHitRadius {
                    return index
                }
            }
            return nil
        }

        func applyPreferredCamera(on mapView: MapView, force: Bool = false) {
            if polygonVertices.count >= 2 {
                setCameraToPolygonVertices(polygonVertices, on: mapView, force: force)
                return
            }
            if let firstVertex = polygonVertices.first {
                updateCamera(center: firstVertex, on: mapView, force: force)
                return
            }
            if let startingAddressCoordinate {
                updateCamera(center: startingAddressCoordinate, on: mapView, force: force)
                return
            }
            if let userLocationCoordinate {
                updateCamera(center: userLocationCoordinate, on: mapView, force: force)
                return
            }
            if let fallbackCenter {
                updateCamera(center: fallbackCenter, on: mapView, force: force)
            }
        }

        func updateCamera(center: CLLocationCoordinate2D, on mapView: MapView, force: Bool = false) {
            lastPolygonCameraSignature = nil
            if !force,
               let last = lastCameraCenter,
               abs(last.latitude - center.latitude) < 0.0001,
               abs(last.longitude - center.longitude) < 0.0001 {
                return
            }
            lastCameraCenter = center
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15, bearing: 0, pitch: 0))
        }

        private func setCameraToPolygonVertices(_ vertices: [CLLocationCoordinate2D], on mapView: MapView, force: Bool = false) {
            let signature = vertices
                .map { "\($0.latitude),\($0.longitude)" }
                .joined(separator: "|")
            if !force, signature == lastPolygonCameraSignature {
                return
            }

            let latitudes = vertices.map(\.latitude)
            let longitudes = vertices.map(\.longitude)
            guard let minLat = latitudes.min(),
                  let maxLat = latitudes.max(),
                  let minLon = longitudes.min(),
                  let maxLon = longitudes.max() else {
                return
            }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )

            if let last = lastCameraCenter,
               abs(last.latitude - center.latitude) < 0.0001,
               abs(last.longitude - center.longitude) < 0.0001,
               !force {
                lastPolygonCameraSignature = signature
                return
            }

            lastCameraCenter = center
            lastPolygonCameraSignature = signature
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15, bearing: 0, pitch: 0))
        }

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard sender.state == .ended,
                  let mapView = mapView ?? sender.view as? MapView,
                  let map = mapView.mapboxMap else { return }
            let point = sender.location(in: mapView)
            if vertexIndexNear(point: point, in: mapView) != nil { return }
            let coordinate = map.coordinate(for: point)
            onTap?(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let mapView = mapView ?? sender.view as? MapView,
                  let map = mapView.mapboxMap else { return }
            let point = sender.location(in: mapView)
            switch sender.state {
            case .began:
                if let index = vertexIndexNear(point: point, in: mapView) {
                    draggingVertexIndex = index
                }
            case .changed:
                if let index = draggingVertexIndex {
                    let coordinate = map.coordinate(for: point)
                    onMoveVertex?(index, CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
            case .ended, .cancelled:
                draggingVertexIndex = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UIPanGestureRecognizer,
                  let mapView = mapView ?? gestureRecognizer.view as? MapView else {
                return true
            }

            let point = gestureRecognizer.location(in: mapView)
            return vertexIndexNear(point: point, in: mapView) != nil
        }
    }
}
