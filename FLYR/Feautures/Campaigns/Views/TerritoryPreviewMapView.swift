import SwiftUI
import MapboxMaps
import CoreLocation

/// Small map preview for New Campaign territory. Centers on the given coordinate (e.g. from starting address).
/// Uses v11-style map with buildings; dark style in dark mode, light in light mode (campaign creation only).
/// Shows a red stick-man location marker (feet anchored at the point) when provided. When polygon is set, draws the polygon and fits camera to its bounds.
struct TerritoryPreviewMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D?
    var polygon: [CLLocationCoordinate2D]? = nil
    var useDarkStyle: Bool = false
    var height: CGFloat = 220

    private static let defaultCenter = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)
    private static let previewBuildingsLayerId = "preview-buildings"
    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!

    private static func addBuildingsLayer(to map: MapboxMap, useDarkStyle: Bool) {
        guard !map.allLayerIdentifiers.contains(where: { $0.id == previewBuildingsLayerId }) else { return }
        do {
            var layer = FillExtrusionLayer(id: previewBuildingsLayerId, source: "composite")
            layer.sourceLayer = "building"
            layer.minZoom = 12
            layer.fillExtrusionOpacity = .constant(0.85)
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
            layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
            let buildingColor = useDarkStyle ? UIColor.darkGray : UIColor(white: 0.92, alpha: 1)
            layer.fillExtrusionColor = .constant(StyleColor(buildingColor))
            try map.addLayer(layer)
        } catch {
            print("⚠️ [TerritoryPreview] Could not add buildings layer: \(error)")
        }
    }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: CGRect(x: 0, y: 0, width: 320, height: max(200, height)))
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.logo.margins = CGPoint(x: 6, y: 6)
        mapView.ornaments.options.compass.visibility = .hidden

        let styleURI = useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI
        mapView.mapboxMap.loadStyle(styleURI)

        let dark = useDarkStyle
        let coord = center ?? Self.defaultCenter
        let initialPolygon = polygon
        mapView.mapboxMap.onStyleLoaded.observeNext { [weak mapView] _ in
            guard let mapView = mapView, let map = mapView.mapboxMap else { return }
            Self.addBuildingsLayer(to: map, useDarkStyle: dark)
            if let poly = initialPolygon, poly.count >= 3 {
                context.coordinator.setCameraToPolygonBounds(poly, on: mapView)
            } else {
                map.setCamera(to: CameraOptions(center: coord, zoom: 14))
            }
        }

        // Red stick-man location marker (feet anchored at the point)
        let markerManager = mapView.annotations.makePointAnnotationManager()
        context.coordinator.pointAnnotationManager = markerManager

        // Polygon overlay (same styling as MapDrawingMapRepresentable)
        let red = UIColor(red: 239/255, green: 68/255, blue: 68/255, alpha: 1)
        let polygonManager = mapView.annotations.makePolygonAnnotationManager()
        polygonManager.fillColor = StyleColor(red.withAlphaComponent(0.15))
        polygonManager.fillOpacity = 1.0
        polygonManager.fillOutlineColor = StyleColor(red)
        context.coordinator.polygonAnnotationManager = polygonManager

        context.coordinator.mapView = mapView
        context.coordinator.updateMarker(at: center)
        context.coordinator.updatePolygonAnnotation(polygon)
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.updateMarker(at: center)
        context.coordinator.updatePolygonAnnotation(polygon)
        if let polygon = polygon, polygon.count >= 3 {
            context.coordinator.setCameraToPolygonBounds(polygon, on: mapView)
        } else {
            let coord = center ?? Self.defaultCenter
            mapView.mapboxMap.setCamera(to: CameraOptions(center: coord, zoom: 14))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var mapView: MapView?
        var pointAnnotationManager: PointAnnotationManager?
        var polygonAnnotationManager: PolygonAnnotationManager?

        func updateMarker(at center: CLLocationCoordinate2D?) {
            guard let manager = pointAnnotationManager else { return }
            guard let center = center, let image = LocationMarkerImage.markerImage else {
                manager.annotations = []
                return
            }
            var annotation = PointAnnotation(coordinate: LocationCoordinate2D(latitude: center.latitude, longitude: center.longitude))
            annotation.image = .init(image: image, name: LocationMarkerImage.imageName)
            annotation.iconAnchor = .bottom
            annotation.iconSize = 1.0
            manager.annotations = [annotation]
        }

        func updatePolygonAnnotation(_ vertices: [CLLocationCoordinate2D]?) {
            guard let manager = polygonAnnotationManager else { return }
            guard let vertices = vertices, vertices.count >= 3 else {
                manager.annotations = []
                return
            }
            var ring = vertices.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            if ring.first != ring.last, let first = ring.first {
                ring.append(first)
            }
            let polygon = Polygon([ring])
            let annotation = PolygonAnnotation(polygon: polygon)
            manager.annotations = [annotation]
        }

        func setCameraToPolygonBounds(_ polygon: [CLLocationCoordinate2D], on mapView: MapView) {
            let lats = polygon.map { $0.latitude }
            let lons = polygon.map { $0.longitude }
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            let padding = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
            mapView.mapboxMap.setCamera(to: CameraOptions(center: center, padding: padding, zoom: 14))
        }
    }
}
