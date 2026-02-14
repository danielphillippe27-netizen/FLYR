import SwiftUI
import MapboxMaps
import CoreLocation

/// Mapbox MapView for polygon drawing (iOS parity with web Mapbox GL Draw draw_polygon).
/// Red styling: fill #ef4444 15%, stroke 3px, vertex circles. Tap to add; drag vertex to move; tap first again to close.
/// Uses v11-style map with buildings; dark style in dark mode, light style in light mode (campaign creation only).
/// Optionally shows a red stick-man location marker at the starting address (feet anchored at the point).
struct MapDrawingMapRepresentable: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    /// When set, a red stick-man marker is shown at this coordinate (starting address).
    var startingAddressCoordinate: CLLocationCoordinate2D?
    let polygonVertices: [CLLocationCoordinate2D]
    var useDarkStyle: Bool = false
    let onTap: (CLLocationCoordinate2D) -> Void
    let onMoveVertex: (Int, CLLocationCoordinate2D) -> Void

    private static let drawingBuildingsLayerId = "drawing-buildings"
    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!

    private static func addBuildingsLayer(to map: MapboxMap, useDarkStyle: Bool) {
        guard !map.allLayerIdentifiers.contains(where: { $0.id == drawingBuildingsLayerId }) else { return }
        do {
            var layer = FillExtrusionLayer(id: drawingBuildingsLayerId, source: "composite")
            layer.sourceLayer = "building"
            layer.minZoom = 12
            layer.fillExtrusionOpacity = .constant(0.85)
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
            layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
            let buildingColor = useDarkStyle ? UIColor.darkGray : UIColor(white: 0.92, alpha: 1)
            layer.fillExtrusionColor = .constant(StyleColor(buildingColor))
            try map.addLayer(layer)
        } catch {
            print("⚠️ [MapDrawing] Could not add buildings layer: \(error)")
        }
    }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.ornaments.options.scaleBar.visibility = .visible
        mapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
        mapView.ornaments.options.compass.visibility = .adaptive

        let styleURI = useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI
        mapView.mapboxMap.loadStyle(styleURI)

        let dark = useDarkStyle
        mapView.mapboxMap.onStyleLoaded.observeNext { [weak mapView] _ in
            guard let map = mapView?.mapboxMap else { return }
            Self.addBuildingsLayer(to: map, useDarkStyle: dark)
        }

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
        mapView.addGestureRecognizer(panGesture)

        context.coordinator.mapView = mapView
        context.coordinator.onTap = onTap
        context.coordinator.onMoveVertex = onMoveVertex
        context.coordinator.updateStartingAddressMarker(at: startingAddressCoordinate)

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onMoveVertex = onMoveVertex
        context.coordinator.polygonVertices = polygonVertices
        context.coordinator.updatePolygonAnnotation(polygonVertices)
        context.coordinator.updateVertexAnnotations(polygonVertices)
        context.coordinator.updateStartingAddressMarker(at: startingAddressCoordinate)
        // Only set camera when no vertices yet (initial load). Once user starts drawing, don't recenter or zoom.
        if polygonVertices.isEmpty {
            context.coordinator.updateCamera(center: center, on: mapView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var mapView: MapView?
        var polygonAnnotationManager: PolygonAnnotationManager?
        var vertexAnnotationManager: CircleAnnotationManager?
        var startingAddressMarkerManager: PointAnnotationManager?
        var onTap: ((CLLocationCoordinate2D) -> Void)?
        var onMoveVertex: ((Int, CLLocationCoordinate2D) -> Void)?
        var polygonVertices: [CLLocationCoordinate2D] = []
        private var lastCameraCenter: CLLocationCoordinate2D?
        private var draggingVertexIndex: Int?

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

        func updateCamera(center: CLLocationCoordinate2D, on mapView: MapView) {
            if let last = lastCameraCenter,
               abs(last.latitude - center.latitude) < 0.0001,
               abs(last.longitude - center.longitude) < 0.0001 {
                return
            }
            lastCameraCenter = center
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, zoom: 15))
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
    }
}
