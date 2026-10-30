import SwiftUI
import CoreLocation
import UIKit
import GoogleMaps

enum CampaignMapRendererDecision: Equatable {
    case mapbox3D
    case google2D

    static func resolve(
        dataResolved: Bool,
        hasRenderableBuildings: Bool,
        activeSession: Bool,
        sessionUses2D: Bool,
        mapboxAvailable: Bool,
        googleAvailable: Bool
    ) -> CampaignMapRendererDecision? {
        guard dataResolved else { return nil }
        if activeSession {
            if (sessionUses2D || !mapboxAvailable) && googleAvailable { return .google2D }
            return mapboxAvailable ? .mapbox3D : nil
        }
        if !hasRenderableBuildings { return googleAvailable ? .google2D : nil }
        return mapboxAvailable ? .mapbox3D : nil
    }
}

struct StandardCampaignMapMarker: Equatable {
    let addressId: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String
    let address: MapLayerManager.AddressTapResult
    let status: AddressStatus

    static func == (lhs: StandardCampaignMapMarker, rhs: StandardCampaignMapMarker) -> Bool {
        lhs.addressId == rhs.addressId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.title == rhs.title
            && lhs.status == rhs.status
            && lhs.address.formatted == rhs.address.formatted
            && lhs.address.gersId == rhs.address.gersId
            && lhs.address.buildingGersId == rhs.address.buildingGersId
            && lhs.address.houseNumber == rhs.address.houseNumber
            && lhs.address.streetName == rhs.address.streetName
            && lhs.address.source == rhs.address.source
            && lhs.address.parcelId == rhs.address.parcelId
            && lhs.address.campaignParcelId == rhs.address.campaignParcelId
            && lhs.address.hasParcelLink == rhs.address.hasParcelLink
    }
}

struct StandardCampaignMapCamera: Equatable {
    let center: CLLocationCoordinate2D
    let zoom: Float

    static func == (lhs: StandardCampaignMapCamera, rhs: StandardCampaignMapCamera) -> Bool {
        lhs.center.latitude == rhs.center.latitude
            && lhs.center.longitude == rhs.center.longitude
            && lhs.zoom == rhs.zoom
    }
}

private struct StandardCampaignCluster {
    let coordinates: [CLLocationCoordinate2D]
}

private enum StandardCampaignClustering {
    private static let iconCache: NSCache<NSNumber, UIImage> = {
        let cache = NSCache<NSNumber, UIImage>()
        cache.countLimit = 128
        return cache
    }()

    static func icon(count: Int) -> UIImage {
        let key = NSNumber(value: count)
        if let cached = iconCache.object(forKey: key) { return cached }
        let text = String(count)
        let size: CGFloat = count >= 1000 ? 56 : 48
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: size - 2, height: size - 2)).fill()
            UIColor(red: 225 / 255, green: 0, blue: 25 / 255, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: size - 8, height: size - 8)).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16), .foregroundColor: UIColor.white
            ]
            let label = text as NSString
            let measured = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: (size - measured.width) / 2, y: (size - measured.height) / 2), withAttributes: attributes)
        }
        iconCache.setObject(image, forKey: key)
        return image
    }
}

private enum StandardCampaignMarkerIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(for status: AddressStatus) -> UIImage {
        let key = status.rawValue
        if let cached = cache[key] {
            return cached
        }

        let image = makeImage(
            fillColor: fillColor(for: status),
            symbolName: symbolName(for: status)
        )
        cache[key] = image
        return image
    }

    private static func fillColor(for status: AddressStatus) -> UIColor {
        switch status {
        case .none, .untouched:
            return MapStatusColor.untouched
        case .noAnswer:
            return MapStatusColor.noOneHome
        case .delivered:
            return MapStatusColor.touched
        case .talked:
            return MapStatusColor.conversations
        case .appointment, .futureSeller:
            return MapStatusColor.hotLead
        case .hotLead:
            return MapStatusColor.lead
        case .doNotKnock:
            return MapStatusColor.doNotKnock
        }
    }

    private static func symbolName(for status: AddressStatus) -> String {
        switch status {
        case .none, .untouched:
            return "megaphone.fill"
        case .delivered, .noAnswer:
            return "door.left.hand.closed"
        case .talked, .hotLead:
            return "person.fill"
        case .futureSeller:
            return "arrow.uturn.right.circle.fill"
        case .appointment:
            return "calendar"
        case .doNotKnock:
            return "hand.raised.fill"
        }
    }

    private static func makeImage(fillColor: UIColor, symbolName: String) -> UIImage {
        let canvasSize = CGSize(width: 24, height: 24)
        let symbolRect = CGRect(x: 3, y: 3, width: 18, height: 18)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.28).cgColor)

            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: configuration)?
                .withTintColor(fillColor, renderingMode: .alwaysOriginal) {
                symbol.draw(in: symbolRect)
            }
        }
    }
}

struct StandardCampaignGoogleMapView: UIViewRepresentable {
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)

    let campaignId: String
    let markers: [StandardCampaignMapMarker]
    let pathCoordinates: [CLLocationCoordinate2D]
    let boundaryCoordinates: [CLLocationCoordinate2D]
    let fallbackCenter: CLLocationCoordinate2D?
    let initialCamera: StandardCampaignMapCamera?
    let selectedCircleCenter: CLLocationCoordinate2D?
    let showUserLocation: Bool
    var userLocation: CLLocation? = nil
    var userHeading: CLLocationDirection? = nil
    let useSatelliteMap: Bool
    let useDarkMapStyle: Bool
    let contentInsets: UIEdgeInsets
    let onReady: (() -> Void)?
    let onMarkerTap: (MapLayerManager.AddressTapResult) -> Void
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onMapLongPress: (CLLocationCoordinate2D, CGPoint) -> Void
    let onCameraIdle: (StandardCampaignMapCamera) -> Void
    var onUserMapInteraction: () -> Void = {}
    let onTripleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let initialCenter = fallbackCenter ?? Self.defaultCenter
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition.camera(withTarget: initialCenter, zoom: 15)
        options.backgroundColor = UIColor.systemGray6

        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.mapType = useSatelliteMap ? .hybrid : .normal
        applyTheme(to: mapView)
        mapView.isBuildingsEnabled = true
        mapView.isTrafficEnabled = false
        mapView.isIndoorEnabled = false
        mapView.isMyLocationEnabled = showUserLocation
        mapView.padding = contentInsets

        mapView.settings.compassButton = false
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.settings.myLocationButton = false
        mapView.settings.indoorPicker = false

        let tripleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTripleTap(_:)))
        tripleTapGesture.numberOfTapsRequired = 3
        tripleTapGesture.cancelsTouchesInView = false
        tripleTapGesture.delaysTouchesBegan = false
        tripleTapGesture.delaysTouchesEnded = false
        mapView.addGestureRecognizer(tripleTapGesture)

        DispatchQueue.main.async {
            context.coordinator.syncUserLocation(on: mapView)
            context.coordinator.syncMarkers(on: mapView)
            context.coordinator.syncPath(on: mapView)
            context.coordinator.syncBoundary(on: mapView)
            context.coordinator.syncTapCircle(on: mapView)
            context.coordinator.updateCameraIfNeeded(on: mapView)
            onReady?()
        }

        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        uiView.padding = contentInsets
        uiView.mapType = useSatelliteMap ? .hybrid : .normal
        applyTheme(to: uiView)
        context.coordinator.syncUserLocation(on: uiView)
        context.coordinator.syncMarkers(on: uiView)
        context.coordinator.syncPath(on: uiView)
        context.coordinator.syncBoundary(on: uiView)
        context.coordinator.syncTapCircle(on: uiView)
        context.coordinator.updateCameraIfNeeded(on: uiView)
    }

    private func applyTheme(to mapView: GMSMapView) {
        guard !useSatelliteMap, useDarkMapStyle else {
            mapView.mapStyle = nil
            return
        }
        mapView.mapStyle = try? GMSMapStyle(jsonString: Self.darkMapStyleJSON)
    }

    private static let darkMapStyleJSON = """
    [
      {"elementType":"geometry","stylers":[{"color":"#1f1f1f"}]},
      {"elementType":"labels.text.fill","stylers":[{"color":"#d6d6d6"}]},
      {"elementType":"labels.text.stroke","stylers":[{"color":"#1f1f1f"}]},
      {"featureType":"road","elementType":"geometry","stylers":[{"color":"#3a3a3a"}]},
      {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#555555"}]},
      {"featureType":"water","elementType":"geometry","stylers":[{"color":"#101820"}]}
    ]
    """

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: StandardCampaignGoogleMapView
        private var lastMarkerData: [UUID: StandardCampaignMapMarker] = [:]
        private var markersByAddressId: [UUID: GMSMarker] = [:]
        private var pathPolyline: GMSPolyline?
        private var boundaryPolygon: GMSPolygon?
        private var tapCircle: GMSCircle?
        private var lastCampaignId: String?
        private var hasAppliedInitialCamera = false
        private var lastMarkerCount = 0
        private var lastFallbackCenter: CLLocationCoordinate2D?

        private(set) var userLocationMarker: GMSMarker?
        private(set) var userHeadingMarker: GMSMarker?
        private var userAccuracyCircle: GMSCircle?

        private static let userLocationIcon = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { context in
            context.cgContext.setShadow(offset: .zero, blur: 2, color: UIColor.black.withAlphaComponent(0.2).cgColor)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 18, height: 18)).fill()
            context.cgContext.setShadow(offset: .zero, blur: 0)
            UIColor.systemBlue.setFill()
            UIBezierPath(ovalIn: CGRect(x: 5, y: 5, width: 12, height: 12)).fill()
        }

        private static let userHeadingIcon = UIGraphicsImageRenderer(size: CGSize(width: 72, height: 72)).image { context in
            let center = CGPoint(x: 36, y: 36)
            let cone = UIBezierPath()
            cone.move(to: center)
            cone.addArc(withCenter: center, radius: 34, startAngle: -.pi * 2 / 3,
                        endAngle: -.pi / 3, clockwise: true)
            cone.close()
            context.cgContext.addPath(cone.cgPath)
            context.cgContext.clip()
            let colors = [UIColor.systemBlue.withAlphaComponent(0.5).cgColor,
                          UIColor.systemBlue.withAlphaComponent(0.02).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 6,
                    endCenter: center, endRadius: 34, options: [.drawsBeforeStartLocation])
            }
        }

        func syncUserLocation(on mapView: GMSMapView) {
            guard parent.showUserLocation, let location = parent.userLocation,
                  CLLocationCoordinate2DIsValid(location.coordinate) else {
                userLocationMarker?.map = nil
                userHeadingMarker?.map = nil
                userAccuracyCircle?.map = nil
                // The SDK can supply its native location dot before the session's first fix.
                mapView.isMyLocationEnabled = parent.showUserLocation
                return
            }
            mapView.isMyLocationEnabled = false
            let dot = userLocationMarker ?? GMSMarker()
            if userLocationMarker == nil {
                dot.icon = Self.userLocationIcon
                dot.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                dot.title = "Your location"
                dot.isTappable = false
                dot.zIndex = 1001
                userLocationMarker = dot
            }
            dot.position = location.coordinate
            if dot.map == nil { dot.map = mapView }

            let accuracy = userAccuracyCircle ?? GMSCircle()
            if userAccuracyCircle == nil {
                accuracy.fillColor = UIColor.systemBlue.withAlphaComponent(0.10)
                accuracy.strokeColor = UIColor.systemBlue.withAlphaComponent(0.18)
                accuracy.strokeWidth = 1
                accuracy.isTappable = false
                userAccuracyCircle = accuracy
            }
            accuracy.position = location.coordinate
            accuracy.radius = location.horizontalAccuracy.isFinite ? max(0, location.horizontalAccuracy) : 0
            if accuracy.map == nil { accuracy.map = mapView }

            guard let heading = parent.userHeading, heading.isFinite else {
                userHeadingMarker?.map = nil
                return
            }
            let pointer = userHeadingMarker ?? GMSMarker()
            if userHeadingMarker == nil {
                pointer.icon = Self.userHeadingIcon
                pointer.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                pointer.isFlat = true
                pointer.isTappable = false
                pointer.zIndex = 1000
                userHeadingMarker = pointer
            }
            pointer.position = location.coordinate
            let normalizedHeading = heading.truncatingRemainder(dividingBy: 360)
            pointer.rotation = normalizedHeading >= 0 ? normalizedHeading : normalizedHeading + 360
            if pointer.map == nil { pointer.map = mapView }
        }

        init(parent: StandardCampaignGoogleMapView) {
            self.parent = parent
        }

        private var clusterLayout = StandardCampaignClusterLayout()
        private var clusterPoints: [UUID: StandardCampaignClusterLayout.Point] = [:]
        private var clusterMarkers: [StandardCampaignClusterLayout.Cell: GMSMarker] = [:]
        private var renderedClusters: [StandardCampaignClusterLayout.Cell: [UUID: StandardCampaignClusterLayout.Point]] = [:]
        private var isCameraMoving = false
        private var cameraGestureTrace: PerfTrace.Span?
        private(set) var clusterSyncCount = 0
        private(set) var clusterMarkerCreationCount = 0

        private func syncClusters(on mapView: GMSMapView) {
            let started = ProcessInfo.processInfo.systemUptime
            guard let plan = clusterLayout.update(points: clusterPoints, zoom: mapView.camera.zoom,
                                                  isMoving: isCameraMoving) else { return }
            clusterSyncCount += 1
            for cell in Array(clusterMarkers.keys) where plan.clusters[cell] == nil {
                clusterMarkers.removeValue(forKey: cell)?.map = nil
            }
            for (cell, members) in plan.clusters {
                // Keep the same Google overlay if membership and positions did not change.
                guard renderedClusters[cell] != members || clusterMarkers[cell] == nil else { continue }
                let coordinates = members.values.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                var bounds = GMSCoordinateBounds()
                coordinates.forEach { bounds = bounds.includingCoordinate($0) }
                var east = bounds.northEast.longitude
                let west = bounds.southWest.longitude
                if east < west { east += 360 }
                var longitude = (west + east) / 2
                if longitude > 180 { longitude -= 360 }
                let marker: GMSMarker
                if let existing = clusterMarkers[cell] { marker = existing }
                else {
                    marker = GMSMarker()
                    clusterMarkers[cell] = marker
                    clusterMarkerCreationCount += 1
                }
                marker.position = CLLocationCoordinate2D(
                    latitude: (bounds.northEast.latitude + bounds.southWest.latitude) / 2,
                    longitude: longitude)
                marker.icon = StandardCampaignClustering.icon(count: members.count)
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                marker.title = "\(members.count) homes"
                marker.snippet = "Tap to zoom in"
                marker.userData = StandardCampaignCluster(coordinates: coordinates)
                marker.zIndex = 100
                if marker.map !== mapView { marker.map = mapView }
            }
            renderedClusters = plan.clusters
            for (id, marker) in markersByAddressId {
                if plan.individualIDs.contains(id) {
                    if marker.map !== mapView { marker.map = mapView }
                } else if marker.map != nil { marker.map = nil }
            }
            PerfTrace.event("map_2d", "cluster_layout", fields: [
                "durationMs": Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                "pins": clusterPoints.count, "clusters": clusterMarkers.count,
                "individuals": plan.individualIDs.count, "rebuilds": clusterSyncCount,
                "clusterMarkersCreated": clusterMarkerCreationCount
            ])
        }

        func syncMarkers(on mapView: GMSMapView) {
            let started = ProcessInfo.processInfo.systemUptime
            let incomingByID = Dictionary(parent.markers.filter { CLLocationCoordinate2DIsValid($0.coordinate) }
                .map { ($0.addressId, $0) }, uniquingKeysWith: { _, latest in latest })
            for addressId in Array(markersByAddressId.keys) where incomingByID[addressId] == nil {
                markersByAddressId.removeValue(forKey: addressId)?.map = nil
                clusterPoints[addressId] = nil
            }
            var changed = 0
            for markerData in incomingByID.values {
                let marker = markersByAddressId[markerData.addressId] ?? {
                    let marker = GMSMarker(position: markerData.coordinate)
                    // Attach only individual pins after clustering; hidden pins need no map work.
                    markersByAddressId[markerData.addressId] = marker
                    return marker
                }()
                // Equality includes geocoding/link metadata, so unchanged view
                // updates do not touch a Google overlay at all.
                guard lastMarkerData[markerData.addressId] != markerData else { continue }
                marker.userData = markerData.address
                changed += 1
                clusterPoints[markerData.addressId] = StandardCampaignClusterLayout.Point(
                    latitude: markerData.coordinate.latitude, longitude: markerData.coordinate.longitude)
                marker.position = markerData.coordinate
                marker.title = markerData.title
                marker.snippet = markerData.status.displayName
                marker.icon = StandardCampaignMarkerIcon.image(for: markerData.status)
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                marker.appearAnimation = .none
            }
            lastMarkerData = incomingByID
            syncClusters(on: mapView)
            if changed > 0 {
                PerfTrace.event("map_2d", "sync_markers", fields: [
                    "durationMs": Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                    "pins": incomingByID.count, "changed": changed, "moving": isCameraMoving
                ])
            }
        }

        func syncPath(on mapView: GMSMapView) {
            pathPolyline?.map = nil
            pathPolyline = nil

            let validCoordinates = parent.pathCoordinates.filter(CLLocationCoordinate2DIsValid)
            guard validCoordinates.count >= 2 else {
                return
            }

            let path = GMSMutablePath()
            validCoordinates.forEach { path.add($0) }

            let polyline = GMSPolyline(path: path)
            polyline.strokeColor = UIColor.white.withAlphaComponent(0.9)
            polyline.strokeWidth = 4
            polyline.map = mapView
            pathPolyline = polyline
        }

        func syncBoundary(on mapView: GMSMapView) {
            boundaryPolygon?.map = nil
            boundaryPolygon = nil

            let coordinates = parent.boundaryCoordinates.filter(CLLocationCoordinate2DIsValid)
            guard coordinates.count >= 3 else { return }
            let path = GMSMutablePath()
            coordinates.forEach { path.add($0) }
            let polygon = GMSPolygon(path: path)
            polygon.fillColor = UIColor.systemRed.withAlphaComponent(0.08)
            polygon.strokeColor = UIColor.systemRed.withAlphaComponent(0.88)
            polygon.strokeWidth = 3
            polygon.isTappable = false
            polygon.map = mapView
            boundaryPolygon = polygon
        }

        func syncTapCircle(on mapView: GMSMapView) {
            guard let center = parent.selectedCircleCenter, CLLocationCoordinate2DIsValid(center) else {
                tapCircle?.map = nil
                tapCircle = nil
                return
            }

            let circle = tapCircle ?? GMSCircle(position: center, radius: 10)
            circle.position = center
            circle.radius = 10
            circle.fillColor = UIColor.systemRed.withAlphaComponent(0.16)
            circle.strokeColor = UIColor.systemRed.withAlphaComponent(0.9)
            circle.strokeWidth = 2
            circle.map = mapView
            tapCircle = circle
        }

        func updateCameraIfNeeded(on mapView: GMSMapView) {
            if lastCampaignId != parent.campaignId {
                lastCampaignId = parent.campaignId
                hasAppliedInitialCamera = false
                lastMarkerCount = 0
                lastFallbackCenter = nil
            }

            if lastMarkerCount == 0, !parent.markers.isEmpty {
                hasAppliedInitialCamera = false
            }

            if parent.markers.isEmpty, fallbackCenterChanged {
                hasAppliedInitialCamera = false
            }

            lastMarkerCount = parent.markers.count
            lastFallbackCenter = parent.fallbackCenter

            guard !hasAppliedInitialCamera else { return }

            if let camera = parent.initialCamera,
               CLLocationCoordinate2DIsValid(camera.center) {
                hasAppliedInitialCamera = true
                mapView.moveCamera(GMSCameraUpdate.setCamera(
                    GMSCameraPosition(target: camera.center, zoom: camera.zoom)
                ))
                return
            }

            let markerCoordinates = parent.markers.map(\.coordinate).filter(CLLocationCoordinate2DIsValid)
            let pathCoordinates = parent.pathCoordinates.filter(CLLocationCoordinate2DIsValid)
            let coordinatesForBounds = markerCoordinates.isEmpty ? pathCoordinates : markerCoordinates

            if coordinatesForBounds.isEmpty {
                let fallbackCenter = parent.fallbackCenter ?? StandardCampaignGoogleMapView.defaultCenter
                hasAppliedInitialCamera = true
                mapView.moveCamera(GMSCameraUpdate.setTarget(fallbackCenter, zoom: 15))
                return
            }

            hasAppliedInitialCamera = true

            if coordinatesForBounds.count == 1, let coordinate = coordinatesForBounds.first {
                mapView.moveCamera(GMSCameraUpdate.setTarget(coordinate, zoom: 18))
                return
            }

            guard let bounds = bounds(for: coordinatesForBounds), bounds.isValid else {
                return
            }

            mapView.moveCamera(GMSCameraUpdate.fit(bounds))
        }

        private var fallbackCenterChanged: Bool {
            switch (lastFallbackCenter, parent.fallbackCenter) {
            case (nil, nil):
                return false
            case (.some, nil), (nil, .some):
                return true
            case let (.some(lhs), .some(rhs)):
                return lhs.latitude != rhs.latitude || lhs.longitude != rhs.longitude
            }
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onMapTap(coordinate)
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            parent.onMapLongPress(coordinate, mapView.projection.point(for: coordinate))
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            isCameraMoving = false
            syncClusters(on: mapView)
            cameraGestureTrace?.end(fields: ["zoom": position.zoom, "clusterRebuilds": clusterSyncCount])
            cameraGestureTrace = nil
            parent.onCameraIdle(StandardCampaignMapCamera(center: position.target, zoom: position.zoom))
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            isCameraMoving = true
            if gesture {
                cameraGestureTrace?.end(status: "interrupted")
                cameraGestureTrace = PerfTrace.begin("map_2d", "camera_gesture", fields: ["pins": parent.markers.count])
                parent.onUserMapInteraction()
            }
        }

        @objc func handleTripleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.onTripleTap()
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let cluster = marker.userData as? StandardCampaignCluster {
                parent.onUserMapInteraction()
                var bounds = GMSCoordinateBounds()
                cluster.coordinates.forEach { bounds = bounds.includingCoordinate($0) }
                if let camera = mapView.camera(for: bounds, insets: UIEdgeInsets(top: 72, left: 64, bottom: 72, right: 64)) {
                    mapView.animate(to: GMSCameraPosition(
                        target: camera.target,
                        zoom: min(18, max(mapView.camera.zoom + 1, camera.zoom))
                    ))
                }
                return true
            }
            guard let address = marker.userData as? MapLayerManager.AddressTapResult else {
                return false
            }

            let trace = PerfTrace.begin("map_2d", "marker_tap", fields: ["pins": parent.markers.count])
            parent.onMarkerTap(address)
            trace.end(status: "callback_returned")
            mapView.selectedMarker = nil
            return true
        }

        private func bounds(for coordinates: [CLLocationCoordinate2D]) -> GMSCoordinateBounds? {
            guard !coordinates.isEmpty else { return nil }

            var bounds = GMSCoordinateBounds()
            for coordinate in coordinates {
                bounds = bounds.includingCoordinate(coordinate)
            }
            return bounds
        }

    }
}
