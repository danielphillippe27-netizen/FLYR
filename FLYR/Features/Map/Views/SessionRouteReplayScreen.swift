import SwiftUI
import MapboxMaps
import CoreLocation

struct SessionRouteReplayScreen: View {
    let data: SessionSummaryData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if data.pathCoordinates.count >= 2 {
                SessionRouteReplayMapboxViewRepresentable(coordinates: data.pathCoordinates)
                    .ignoresSafeArea()
            } else {
                Text("No route to display")
                    .foregroundColor(.white.opacity(0.8))
            }

            HStack {
                Button("Close") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
    }
}

private struct SessionRouteReplayMapboxViewRepresentable: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    private let routeSourceId = "session-replay-route-source"
    private let routeLayerId = "session-replay-route-layer"

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .adaptive
        if let map = mapView.mapboxMap {
            MapTheme.loadBlueStandardLightStyle(on: map)
        }
        _ = mapView.mapboxMap?.onMapLoaded.observeNext { _ in
            context.coordinator.setup(mapView: mapView)
            context.coordinator.updateRoute(with: self.coordinates)
        }
        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.updateRoute(with: coordinates)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(routeSourceId: routeSourceId, routeLayerId: routeLayerId)
    }

    @MainActor
    final class Coordinator {
        private let routeSourceId: String
        private let routeLayerId: String
        weak var mapView: MapView?
        private var isSetup = false
        private var hasFramedRoute = false

        init(routeSourceId: String, routeLayerId: String) {
            self.routeSourceId = routeSourceId
            self.routeLayerId = routeLayerId
        }

        func setup(mapView: MapView) {
            guard !isSetup, let map = mapView.mapboxMap else { return }
            isSetup = true

            do {
                var source = GeoJSONSource(id: routeSourceId)
                source.data = .featureCollection(FeatureCollection(features: []))
                try map.addSource(source)

                var lineLayer = LineLayer(id: routeLayerId, source: routeSourceId)
                lineLayer.lineColor = .constant(StyleColor(.systemRed))
                lineLayer.lineWidth = .constant(5.0)
                lineLayer.lineOpacity = .constant(0.9)
                lineLayer.lineJoin = .constant(.round)
                lineLayer.lineCap = .constant(.round)
                try map.addLayer(lineLayer)
            } catch {
                print("❌ [SessionReplayMap] Failed to setup route layer: \(error)")
            }
        }

        func updateRoute(with coordinates: [CLLocationCoordinate2D]) {
            guard let map = mapView?.mapboxMap,
                  map.sourceExists(withId: routeSourceId) else { return }

            let features: [Feature]
            if coordinates.count >= 2 {
                let line = coordinates.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                features = [Feature(geometry: .lineString(LineString(line)))]
            } else {
                features = []
            }
            map.updateGeoJSONSource(withId: routeSourceId, geoJSON: .featureCollection(FeatureCollection(features: features)))

            guard coordinates.count >= 2 else { return }
            if !hasFramedRoute {
                hasFramedRoute = true
                frameRoute(coordinates: coordinates)
            }
        }

        private func frameRoute(coordinates: [CLLocationCoordinate2D]) {
            guard let mapView else { return }
            let lats = coordinates.map(\.latitude)
            let lons = coordinates.map(\.longitude)
            guard let minLat = lats.min(),
                  let maxLat = lats.max(),
                  let minLon = lons.min(),
                  let maxLon = lons.max() else { return }

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )

            let span = max(maxLat - minLat, maxLon - minLon)
            let zoom: CGFloat
            switch span {
            case ..<0.001: zoom = 17.0
            case ..<0.003: zoom = 16.0
            case ..<0.008: zoom = 15.0
            case ..<0.02: zoom = 14.0
            case ..<0.05: zoom = 13.0
            case ..<0.12: zoom = 12.0
            default: zoom = 11.0
            }

            mapView.camera.ease(
                to: CameraOptions(center: center, zoom: zoom, bearing: 0, pitch: 0),
                duration: 0.8
            )
            if let map = mapView.mapboxMap {
                MapTheme.applyLightModeShadowPolicy(to: map, pitch: 0)
            }
        }
    }
}
