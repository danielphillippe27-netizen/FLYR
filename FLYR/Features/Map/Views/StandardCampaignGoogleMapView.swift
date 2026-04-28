import SwiftUI
import GoogleMaps
import CoreLocation
import UIKit

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
    }
}

struct StandardCampaignGoogleMapView: UIViewRepresentable {
    let campaignId: String
    let markers: [StandardCampaignMapMarker]
    let pathCoordinates: [CLLocationCoordinate2D]
    let showUserLocation: Bool
    let contentInsets: UIEdgeInsets
    let onReady: (() -> Void)?
    let onMarkerTap: (MapLayerManager.AddressTapResult) -> Void
    let onMapTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.mapType = .normal
        mapView.isBuildingsEnabled = false
        mapView.isIndoorEnabled = false
        mapView.isTrafficEnabled = false
        mapView.isMyLocationEnabled = showUserLocation
        mapView.padding = contentInsets
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.settings.compassButton = false
        mapView.settings.myLocationButton = false
        mapView.accessibilityElementsHidden = false

        DispatchQueue.main.async {
            onReady?()
        }

        return mapView
    }

    func updateUIView(_ uiView: GMSMapView, context: Context) {
        context.coordinator.parent = self
        uiView.padding = contentInsets
        uiView.isMyLocationEnabled = showUserLocation
        context.coordinator.syncMarkers(on: uiView)
        context.coordinator.syncPath(on: uiView)
        context.coordinator.updateCameraIfNeeded(on: uiView)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: StandardCampaignGoogleMapView
        private var markersByAddressId: [UUID: GMSMarker] = [:]
        private var markerModelsByAddressId: [UUID: StandardCampaignMapMarker] = [:]
        private var pathPolyline: GMSPolyline?
        private var lastCampaignId: String?
        private var hasAppliedInitialCamera = false

        init(parent: StandardCampaignGoogleMapView) {
            self.parent = parent
        }

        func syncMarkers(on mapView: GMSMapView) {
            let incomingByID = Dictionary(uniqueKeysWithValues: parent.markers.map { ($0.addressId, $0) })

            for (addressId, marker) in markersByAddressId where incomingByID[addressId] == nil {
                marker.map = nil
                markersByAddressId[addressId] = nil
                markerModelsByAddressId[addressId] = nil
            }

            for markerData in parent.markers {
                let marker = markersByAddressId[markerData.addressId] ?? GMSMarker()
                marker.position = markerData.coordinate
                marker.title = markerData.title
                marker.snippet = markerData.status.displayName
                marker.icon = GMSMarker.markerImage(with: markerColor(for: markerData.status))
                marker.userData = markerData.addressId.uuidString
                marker.tracksViewChanges = false
                marker.map = mapView
                markersByAddressId[markerData.addressId] = marker
                markerModelsByAddressId[markerData.addressId] = markerData
            }
        }

        func syncPath(on mapView: GMSMapView) {
            guard parent.pathCoordinates.count >= 2 else {
                pathPolyline?.map = nil
                pathPolyline = nil
                return
            }

            let path = GMSMutablePath()
            for coordinate in parent.pathCoordinates where CLLocationCoordinate2DIsValid(coordinate) {
                path.add(coordinate)
            }

            guard path.count() >= 2 else {
                pathPolyline?.map = nil
                pathPolyline = nil
                return
            }

            let polyline = pathPolyline ?? GMSPolyline()
            polyline.path = path
            polyline.strokeWidth = 4
            polyline.strokeColor = UIColor.white.withAlphaComponent(0.9)
            polyline.geodesic = true
            polyline.zIndex = 0
            polyline.map = mapView
            pathPolyline = polyline
        }

        func updateCameraIfNeeded(on mapView: GMSMapView) {
            if lastCampaignId != parent.campaignId {
                lastCampaignId = parent.campaignId
                hasAppliedInitialCamera = false
            }

            guard !hasAppliedInitialCamera else { return }
            guard !parent.markers.isEmpty else { return }

            hasAppliedInitialCamera = true

            if parent.markers.count == 1, let marker = parent.markers.first {
                let camera = GMSCameraPosition.camera(
                    withLatitude: marker.coordinate.latitude,
                    longitude: marker.coordinate.longitude,
                    zoom: 17
                )
                mapView.camera = camera
                return
            }

            var bounds = GMSCoordinateBounds()
            for marker in parent.markers {
                bounds = bounds.includingCoordinate(marker.coordinate)
            }

            mapView.moveCamera(GMSCameraUpdate.fit(bounds))
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let rawID = marker.userData as? String,
                  let addressId = UUID(uuidString: rawID),
                  let markerData = markerModelsByAddressId[addressId] else {
                return false
            }

            parent.onMarkerTap(markerData.address)
            return true
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onMapTap()
        }

        private func markerColor(for status: AddressStatus) -> UIColor {
            switch status {
            case .none, .untouched:
                return MapStatusColor.untouched
            case .noAnswer:
                return MapStatusColor.pendingVisited
            case .delivered:
                return .systemBlue
            case .talked:
                return MapStatusColor.touched
            case .appointment:
                return MapStatusColor.conversations
            case .doNotKnock:
                return MapStatusColor.doNotKnock
            case .futureSeller:
                return .systemTeal
            case .hotLead:
                return .systemRed
            }
        }
    }
}
