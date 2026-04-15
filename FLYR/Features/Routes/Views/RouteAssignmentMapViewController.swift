import UIKit
import MapboxMaps
import CoreLocation

enum RouteAssignmentMapDisplayMode: String, CaseIterable {
    case buildings = "Buildings"
    case addresses = "Addresses"
}

/// Mapbox map for a single assignment: building footprints (optional campaign) or address columns.
final class RouteAssignmentMapViewController: UIViewController {
    var campaignId: UUID?
    var stops: [RoutePlanStop] = []
    var displayMode: RouteAssignmentMapDisplayMode = .buildings {
        didSet {
            guard isViewLoaded else { return }
            Task { @MainActor in await applyDisplayMode() }
        }
    }

    private var mapView: MapView!
    private var loadingIndicator: UIActivityIndicatorView?
    private var messageLabel: UILabel?
    private var allBuildingFeatures: [BuildingFeature] = []

    private let routeExtrusionHeight: Double = 7.5
    private let addressColumnHalfWidthMeters: Double = 2.75
    private let addressColumnHeight: Double = 8

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupMap()
        setupLoading()
        setupMessageLabel()
        Task { @MainActor in
            await reloadMapContent()
        }
    }

    func reload(stops: [RoutePlanStop], campaignId: UUID?, mode: RouteAssignmentMapDisplayMode) {
        self.stops = stops
        self.campaignId = campaignId
        self.displayMode = mode
        Task { @MainActor in
            await reloadMapContent()
        }
    }

    // MARK: - Setup

    private func setupMap() {
        let options = MapInitOptions(cameraOptions: CameraOptions(zoom: 14))
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
    }

    private func setupLoading() {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        view.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadingIndicator = indicator
    }

    private func setupMessageLabel() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.isHidden = true
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        messageLabel = label
    }

    // MARK: - Content

    @MainActor
    private func reloadMapContent() async {
        messageLabel?.isHidden = true
        messageLabel?.text = nil
        removeRouteLayers()

        let coords = stops.compactMap { s -> CLLocationCoordinate2D? in
            guard let lat = s.latitude, let lon = s.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        if coords.isEmpty {
            showMessage("No geocoded stops for this route.")
            setFlatOverview()
            return
        }

        loadingIndicator?.startAnimating()
        defer { loadingIndicator?.stopAnimating() }

        if let cid = campaignId {
            do {
                allBuildingFeatures = try await BuildingLinkService.shared.fetchBuildings(campaignId: cid.uuidString)
            } catch {
                allBuildingFeatures = []
            }
        } else {
            allBuildingFeatures = []
        }

        await applyDisplayMode()
        fitCamera(to: coords, pitch: displayMode == .buildings ? 60 : 45)
    }

    @MainActor
    private func applyDisplayMode() async {
        removeRouteLayers()
        messageLabel?.isHidden = true

        let coords = stops.compactMap { s -> CLLocationCoordinate2D? in
            guard let lat = s.latitude, let lon = s.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard !coords.isEmpty else {
            showMessage("No geocoded stops for this route.")
            return
        }

        switch displayMode {
        case .buildings:
            guard campaignId != nil else {
                showMessage("No campaign linked—use Addresses to see stop locations.")
                renderAddressColumns(stops: stops, matchingBuildings: [])
                fitCamera(to: coords, pitch: 45)
                return
            }
            let matched = matchBuildingsToStops(features: allBuildingFeatures, stops: stops)
            if matched.isEmpty {
                showMessage("No building footprints matched these stops. Try Addresses.")
                renderAddressColumns(stops: stops, matchingBuildings: [])
                fitCamera(to: coords, pitch: 45)
                return
            }
            renderBuildings(matched)
            fitCamera(to: matched.compactMap { centroid(of: $0.geometry) }, pitch: 60)

        case .addresses:
            let perStopBuildings: [BuildingFeature?] = stops.map { stop in
                allBuildingFeatures.first { buildingMatchesStop($0, stop: stop) }
            }
            renderAddressColumns(stops: stops, matchingBuildings: perStopBuildings)
            fitCamera(to: coords, pitch: 45)
        }
    }

    private func showMessage(_ text: String) {
        messageLabel?.text = text
        messageLabel?.isHidden = false
    }

    // MARK: - Rendering

    private func renderBuildings(_ features: [BuildingFeature]) {
        var mbxFeatures: [Feature] = []
        for bf in features {
            guard let geometry = convertToMapboxGeometry(bf.geometry) else { continue }
            var props = jsonPropertiesForStatus(from: bf.properties)
            props["height_m"] = .number(routeExtrusionHeight)
            var feature = Feature(geometry: geometry)
            feature.properties = props
            let fid = bf.properties.gersId ?? bf.properties.id
            feature.identifier = .string(fid)
            mbxFeatures.append(feature)
        }

        addGeoJSONSourceAndExtrusion(
            sourceId: "route-assign-source",
            layerId: "route-assign-extrusion",
            features: mbxFeatures,
            heightKey: "height_m",
            colorExpression: routeStatusColorExpression()
        )
    }

    /// One column per stop; uses matched building properties when available for coloring.
    private func renderAddressColumns(stops: [RoutePlanStop], matchingBuildings: [BuildingFeature?]) {
        var mbxFeatures: [Feature] = []
        for (idx, stop) in stops.enumerated() {
            guard let lat = stop.latitude, let lon = stop.longitude else { continue }
            let match = idx < matchingBuildings.count ? matchingBuildings[idx] : nil
            let props: [String: JSONValue]
            if let b = match {
                props = jsonPropertiesForStatus(from: b.properties)
            } else {
                props = defaultRedStatusProps()
            }
            var merged = props
            merged["height_m"] = .number(addressColumnHeight)

            let polygon = squarePolygon(centerLat: lat, centerLon: lon, halfSizeMeters: addressColumnHalfWidthMeters)
            var feature = Feature(geometry: .polygon(polygon))
            feature.properties = merged
            feature.identifier = .string("addr-\(stop.id)")
            mbxFeatures.append(feature)
        }

        guard !mbxFeatures.isEmpty else { return }

        addGeoJSONSourceAndExtrusion(
            sourceId: "route-assign-addr-source",
            layerId: "route-assign-addr-extrusion",
            features: mbxFeatures,
            heightKey: "height_m",
            colorExpression: routeStatusColorExpression()
        )
    }

    private func addGeoJSONSourceAndExtrusion(
        sourceId: String,
        layerId: String,
        features: [Feature],
        heightKey: String,
        colorExpression: Exp
    ) {
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: features))

        do {
            guard let map = mapView.mapboxMap else { return }
            if map.layerExists(withId: layerId) {
                try map.removeLayer(withId: layerId)
            }
            if map.sourceExists(withId: sourceId) {
                try map.removeSource(withId: sourceId)
            }
            try map.addSource(source)

            var layer = FillExtrusionLayer(id: layerId, source: sourceId)
            layer.fillExtrusionHeight = .expression(Exp(.get) { heightKey })
            layer.fillExtrusionBase = .constant(0)
            layer.fillExtrusionOpacity = .constant(0.9)
            layer.fillExtrusionColor = .expression(colorExpression)
            try map.addLayer(layer)
        } catch {
            #if DEBUG
            print("⚠️ [RouteAssignmentMap] Layer error: \(error)")
            #endif
        }
    }

    private func removeRouteLayers() {
        guard let map = mapView.mapboxMap else { return }
        let pairs = [
            ("route-assign-extrusion", "route-assign-source"),
            ("route-assign-addr-extrusion", "route-assign-addr-source")
        ]
        for (layer, source) in pairs {
            if map.layerExists(withId: layer) {
                try? map.removeLayer(withId: layer)
            }
            if map.sourceExists(withId: source) {
                try? map.removeSource(withId: source)
            }
        }
    }

    // MARK: - Matching & geometry

    private func matchBuildingsToStops(features: [BuildingFeature], stops: [RoutePlanStop]) -> [BuildingFeature] {
        var seen = Set<String>()
        var out: [BuildingFeature] = []
        for stop in stops {
            for bf in features where buildingMatchesStop(bf, stop: stop) {
                let key = bf.properties.gersId ?? bf.properties.id
                if seen.insert(key).inserted {
                    out.append(bf)
                }
            }
        }
        return out
    }

    private func buildingMatchesStop(_ building: BuildingFeature, stop: RoutePlanStop) -> Bool {
        let p = building.properties
        if let aid = stop.addressId, let pid = p.addressId, let u = UUID(uuidString: pid), u == aid {
            return true
        }
        if let bid = stop.buildingId {
            if let pb = p.buildingId, let u = UUID(uuidString: pb), u == bid { return true }
            if let u = UUID(uuidString: p.id), u == bid { return true }
        }
        if let g = stop.gersId, !g.isEmpty {
            if let pg = p.gersId, pg == g { return true }
            if p.id == g { return true }
        }
        return false
    }

    private func squarePolygon(centerLat: Double, centerLon: Double, halfSizeMeters: Double) -> Polygon {
        let dLat = halfSizeMeters / 111_320.0
        let cosLat = max(0.2, cos(centerLat * .pi / 180.0))
        let dLon = halfSizeMeters / (111_320.0 * cosLat)
        let ring: [LocationCoordinate2D] = [
            LocationCoordinate2D(latitude: centerLat - dLat, longitude: centerLon - dLon),
            LocationCoordinate2D(latitude: centerLat - dLat, longitude: centerLon + dLon),
            LocationCoordinate2D(latitude: centerLat + dLat, longitude: centerLon + dLon),
            LocationCoordinate2D(latitude: centerLat + dLat, longitude: centerLon - dLon),
            LocationCoordinate2D(latitude: centerLat - dLat, longitude: centerLon - dLon)
        ]
        return Polygon([ring])
    }

    private func convertToMapboxGeometry(_ geometry: MapFeatureGeoJSONGeometry) -> MapboxMaps.Geometry? {
        if let polygon = geometry.asPolygon {
            let polygonCoords = polygon.map { ring in
                ring.map { coord in
                    LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }
            return .polygon(Polygon(polygonCoords))
        }
        if let multi = geometry.asMultiPolygon {
            let multiCoords = multi.map { polygon in
                polygon.map { ring in
                    ring.map { coord in
                        LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    }
                }
            }
            return .multiPolygon(MultiPolygon(multiCoords))
        }
        return nil
    }

    private func centroid(of geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        if let polygon = geometry.asPolygon,
           let firstRing = polygon.first,
           let firstPoint = firstRing.first,
           firstPoint.count >= 2 {
            return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
        }
        if let multi = geometry.asMultiPolygon,
           let firstPoly = multi.first,
           let firstRing = firstPoly.first,
           let firstPoint = firstRing.first,
           firstPoint.count >= 2 {
            return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
        }
        return nil
    }

    // MARK: - Styling (web MAP_STATUS_CONFIG parity)

    private func jsonPropertiesForStatus(from p: BuildingProperties) -> [String: JSONValue] {
        var props: [String: JSONValue] = [:]
        props["scans_total"] = .number(Double(p.scansTotal))
        props["status"] = .string(p.status)
        props["qr_scanned"] = .boolean(p.qrScanned ?? false)
        if let fs = p.featureStatus {
            props["address_status"] = .string(fs)
        }
        return props
    }

    private func defaultRedStatusProps() -> [String: JSONValue] {
        [
            "scans_total": .number(0),
            "status": .string(""),
            "qr_scanned": .boolean(false)
        ]
    }

    private func routeStatusColorExpression() -> Exp {
        Exp(.switchCase) {
            Exp(.eq) { Exp(.get) { "qr_scanned" }; true }
            UIColor(hex: "#a855f7")!

            Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
            UIColor(hex: "#a855f7")!

            Exp(.eq) { Exp(.get) { "status" }; "hot" }
            UIColor(hex: "#3b82f6")!

            Exp(.eq) { Exp(.get) { "address_status" }; "hot" }
            UIColor(hex: "#3b82f6")!

            Exp(.eq) { Exp(.get) { "status" }; "visited" }
            UIColor(hex: "#22c55e")!

            Exp(.eq) { Exp(.get) { "status" }; "touched" }
            UIColor(hex: "#22c55e")!

            Exp(.eq) { Exp(.get) { "address_status" }; "visited" }
            UIColor(hex: "#22c55e")!

            Exp(.eq) { Exp(.get) { "address_status" }; "touched" }
            UIColor(hex: "#22c55e")!

            UIColor(hex: "#ef4444")!
        }
    }

    // MARK: - Camera

    private func fitCamera(to coordinates: [CLLocationCoordinate2D], pitch: CGFloat) {
        guard !coordinates.isEmpty, let mapView else { return }
        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        let latSpan = max(maxLat - minLat, 0.0004)
        let lonSpan = max(maxLon - minLon, 0.0004)
        let adjustedLat = latSpan * 1.4
        let adjustedLon = lonSpan * 1.4
        let zoomLat = log2(360.0 / adjustedLat) - 8.2
        let zoomLon = log2(360.0 / (adjustedLon * max(0.2, cos(center.latitude * .pi / 180.0)))) - 8.2
        let zoom = min(16, max(11, min(zoomLat, zoomLon)))

        let camera = CameraOptions(
            center: center,
            padding: UIEdgeInsets(top: 70, left: 70, bottom: 70, right: 70),
            zoom: zoom,
            bearing: 0,
            pitch: pitch
        )
        mapView.camera.fly(to: camera, duration: 0.35)
    }

    private func setFlatOverview() {
        guard let mapView else { return }
        mapView.mapboxMap.setCamera(to: CameraOptions(pitch: 0))
    }
}
