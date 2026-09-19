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
        googleAvailable: Bool,
        standardMode: Bool = false,
        preferred2D: Bool? = nil
    ) -> CampaignMapRendererDecision? {
        if let preferred2D {
            if preferred2D { return googleAvailable ? .google2D : (mapboxAvailable ? .mapbox3D : nil) }
            return mapboxAvailable ? .mapbox3D : (googleAvailable ? .google2D : nil)
        }
        // Standard renders immediately unless the user selects WolfGrid 3D.
        if standardMode { return googleAvailable ? .google2D : nil }
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
    var cardEngaged: Bool = false

    static func == (lhs: StandardCampaignMapMarker, rhs: StandardCampaignMapMarker) -> Bool {
        lhs.addressId == rhs.addressId
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.title == rhs.title
            && lhs.status == rhs.status
            && lhs.cardEngaged == rhs.cardEngaged
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

private enum StandardCampaignMarkerIcon {
    private static var cache: [String: UIImage] = [:]

    static func image(for status: AddressStatus, cardEngaged: Bool = false) -> UIImage {
        let key = status.rawValue + (cardEngaged ? "-card" : "")
        if let cached = cache[key] {
            return cached
        }

        let image = makeImage(
            fillColor: cardEngaged ? MapStatusColor.qrScanned : fillColor(for: status),
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
        let canvasSize = CGSize(width: 32, height: 32)
        let symbolRect = CGRect(x: 7, y: 7, width: 18, height: 18)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.28).cgColor)

            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 28, height: 28)).fill()
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            fillColor.setFill()
            UIBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 24, height: 24)).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
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
    let useSatelliteMap: Bool
    let useDarkMapStyle: Bool
    let contentInsets: UIEdgeInsets
    let onReady: (() -> Void)?
    let onMarkerTap: (MapLayerManager.AddressTapResult) -> Void
    let onMapTap: (CLLocationCoordinate2D) -> Void
    let onMapLongPress: (CLLocationCoordinate2D, CGPoint) -> Void
    let onCameraIdle: (StandardCampaignMapCamera) -> Void
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
        mapView.addGestureRecognizer(tripleTapGesture)

        DispatchQueue.main.async {
            context.coordinator.syncWolf(on: mapView)
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
        if uiView.padding != contentInsets { uiView.padding = contentInsets }
        let mapType: GMSMapViewType = useSatelliteMap ? .hybrid : .normal
        if uiView.mapType != mapType { uiView.mapType = mapType }
        if context.coordinator.lastTheme != [useSatelliteMap, useDarkMapStyle] {
            applyTheme(to: uiView)
            context.coordinator.lastTheme = [useSatelliteMap, useDarkMapStyle]
        }
        context.coordinator.syncWolf(on: uiView)
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
        var lastTheme: [Bool]?
        private var lastMarkerData: [UUID: StandardCampaignMapMarker] = [:]
        private var lastPath: [CLLocationCoordinate2D] = []
        private var lastBoundary: [CLLocationCoordinate2D] = []
        private var wolfMarker: GMSMarker?
        private static let wolfIcon: UIImage? = {
            guard let asset = UIImage(named: "WolfyStage1") else { return nil }
            return UIGraphicsImageRenderer(size: CGSize(width: 52, height: 52)).image { _ in
                UIColor.white.setFill()
                UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 50, height: 50)).fill()
                UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 46, height: 46)).addClip()
                asset.draw(in: CGRect(x: 3, y: 3, width: 46, height: 46))
            }
        }()

        func syncWolf(on mapView: GMSMapView) {
            guard parent.showUserLocation, let location = parent.userLocation,
                  CLLocationCoordinate2DIsValid(location.coordinate), let icon = Self.wolfIcon else {
                wolfMarker?.map = nil
                mapView.isMyLocationEnabled = parent.showUserLocation
                return
            }
            let marker = wolfMarker ?? GMSMarker()
            if wolfMarker == nil {
                marker.icon = icon
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                marker.title = "Wolfy · Your location"
                marker.isTappable = false
                marker.zIndex = 1000
                wolfMarker = marker
            }
            marker.position = location.coordinate
            marker.map = mapView
            mapView.isMyLocationEnabled = false
        }

        private func sameCoordinates(_ lhs: [CLLocationCoordinate2D], _ rhs: [CLLocationCoordinate2D]) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
                $0.0.latitude == $0.1.latitude && $0.0.longitude == $0.1.longitude
            }
        }

        private var markersByAddressId: [UUID: GMSMarker] = [:]
        private var pathPolyline: GMSPolyline?
        private var boundaryPolygon: GMSPolygon?
        private var tapCircle: GMSCircle?
        private var lastCampaignId: String?
        private var hasAppliedInitialCamera = false
        private var lastMarkerCount = 0
        private var lastFallbackCenter: CLLocationCoordinate2D?

        init(parent: StandardCampaignGoogleMapView) {
            self.parent = parent
        }

        func syncMarkers(on mapView: GMSMapView) {
            let incomingByID = Dictionary(parent.markers.filter { CLLocationCoordinate2DIsValid($0.coordinate) }.map { ($0.addressId, $0) }, uniquingKeysWith: { _, latest in latest })

            for (addressId, marker) in markersByAddressId where incomingByID[addressId] == nil {
                marker.map = nil
                markersByAddressId[addressId] = nil
            }

            for markerData in incomingByID.values {
                let marker = markersByAddressId[markerData.addressId] ?? {
                    let marker = GMSMarker(position: markerData.coordinate)
                    marker.map = mapView
                    markersByAddressId[markerData.addressId] = marker
                    return marker
                }()

                marker.userData = markerData.address
                guard lastMarkerData[markerData.addressId] != markerData else { continue }
                marker.position = markerData.coordinate
                marker.title = markerData.title
                marker.snippet = markerData.status.displayName
                marker.icon = StandardCampaignMarkerIcon.image(for: markerData.status, cardEngaged: markerData.cardEngaged)
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                marker.userData = markerData.address
                marker.appearAnimation = .none
            }
            lastMarkerData = incomingByID
        }

        func syncPath(on mapView: GMSMapView) {
            guard !sameCoordinates(lastPath, parent.pathCoordinates) else { return }
            lastPath = parent.pathCoordinates
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
            guard !sameCoordinates(lastBoundary, parent.boundaryCoordinates) else { return }
            lastBoundary = parent.boundaryCoordinates
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
            parent.onCameraIdle(StandardCampaignMapCamera(center: position.target, zoom: position.zoom))
        }

        @objc func handleTripleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            parent.onTripleTap()
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let address = marker.userData as? MapLayerManager.AddressTapResult else {
                return false
            }

            parent.onMarkerTap(address)
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
