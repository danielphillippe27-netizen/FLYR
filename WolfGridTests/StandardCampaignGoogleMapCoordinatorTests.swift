import XCTest
import GoogleMaps
import CoreLocation
@testable import WolfGrid

@MainActor
final class StandardCampaignGoogleMapCoordinatorTests: XCTestCase {
    private func map() throws -> GMSMapView {
        guard !Config.googleMapsAPIKey.isEmpty else { throw XCTSkip("Google Maps API key is required") }
        GMSServices.provideAPIKey(Config.googleMapsAPIKey)
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(latitude: 43.65, longitude: -79.38, zoom: 15)
        return GMSMapView(options: options)
    }

    private func markers(_ count: Int) -> [StandardCampaignMapMarker] {
        (0..<count).map { index in
            let id = UUID()
            return StandardCampaignMapMarker(
                addressId: id, coordinate: .init(latitude: 43.65, longitude: -79.38 + Double(index) * 0.000001),
                title: "\(index + 1) Test Street",
                address: .init(addressId: id, formatted: "\(index + 1) Test Street", gersId: nil,
                               buildingGersId: nil, houseNumber: nil, streetName: nil, source: "manual_pin"),
                status: .untouched)
        }
    }

    private func parent(_ markers: [StandardCampaignMapMarker],
                        userLocation: CLLocation? = nil,
                        userHeading: CLLocationDirection? = nil,
                        showUserLocation: Bool = false,
                        onTap: @escaping (MapLayerManager.AddressTapResult, CGPoint) -> Void = { _, _ in }) -> StandardCampaignGoogleMapView {
        StandardCampaignGoogleMapView(
            campaignId: "2d-performance-fixture", markers: markers, pathCoordinates: [], boundaryCoordinates: [],
            fallbackCenter: nil, initialCamera: nil, selectedCircleCenter: nil,
            showUserLocation: showUserLocation, userLocation: userLocation, userHeading: userHeading,
            followUserLocation: false, useSatelliteMap: false, useDarkMapStyle: false,
            contentInsets: .zero, onReady: nil, onMarkerTap: onTap, onMapTap: { _, _ in },
            onMapLongPress: { _, _ in }, onCameraIdle: { _ in }, onUserMapInteraction: {}, onTripleTap: {})
    }

    func testRepeatedViewUpdatesReuseGoogleOverlays() throws {
        let map = try map()
        let coordinator = parent(markers(1_000)).makeCoordinator()
        coordinator.syncMarkers(on: map)
        let creations = coordinator.clusterMarkerCreationCount
        XCTAssertGreaterThan(creations, 0)
        for _ in 0..<100 { coordinator.syncMarkers(on: map) }
        XCTAssertEqual(coordinator.clusterSyncCount, 1)
        XCTAssertEqual(coordinator.clusterMarkerCreationCount, creations)
    }

    func testZoomDoesNotRebuildUntilIdleAndStatusChangesStaySelectable() throws {
        let map = try map()
        var homes = markers(1_000)
        let tappedID = homes[0].addressId
        var selectedID: UUID?
        let coordinator = parent(homes) { address, _ in selectedID = address.addressId }.makeCoordinator()
        coordinator.syncMarkers(on: map)
        coordinator.mapView(map, willMove: true)
        homes[0] = StandardCampaignMapMarker(addressId: homes[0].addressId, coordinate: homes[0].coordinate,
            title: homes[0].title, address: homes[0].address, status: .talked)
        coordinator.parent = parent(homes) { address, _ in selectedID = address.addressId }
        coordinator.syncMarkers(on: map)
        XCTAssertEqual(coordinator.clusterSyncCount, 1)
        map.moveCamera(GMSCameraUpdate.zoom(to: 18))
        coordinator.mapView(map, idleAt: map.camera)
        XCTAssertEqual(coordinator.clusterSyncCount, 2)
        let marker = GMSMarker(position: homes[0].coordinate)
        marker.userData = homes[0].address
        XCTAssertTrue(coordinator.mapView(map, didTap: marker))
        XCTAssertEqual(selectedID, tappedID)
        XCTAssertNil(map.selectedMarker)
    }

    func testMarkerTapCallbackIsSynchronousAndDoesNotRecluster() throws {
        let map = try map()
        let homes = markers(1_000)
        var callbacks = 0
        let coordinator = parent(homes) { _, _ in callbacks += 1 }.makeCoordinator()
        coordinator.syncMarkers(on: map)
        let marker = GMSMarker(position: homes[0].coordinate)
        marker.userData = homes[0].address
        for _ in 0..<20 { XCTAssertTrue(coordinator.mapView(map, didTap: marker)) }
        XCTAssertEqual(callbacks, 20)
        XCTAssertEqual(coordinator.clusterSyncCount, 1)
    }
    func testCompassUpdatesReuseTheLocationDotAndDirectionPointer() throws {
        let map = try map()
        let location = CLLocation(latitude: 43.65, longitude: -79.38)
        let coordinator = parent([], userLocation: location, userHeading: 355, showUserLocation: true).makeCoordinator()
        coordinator.syncUserLocation(on: map)
        let dot = try XCTUnwrap(coordinator.userLocationMarker)
        let pointer = try XCTUnwrap(coordinator.userHeadingMarker)
        XCTAssertEqual(dot.title, "Your location")
        XCTAssertFalse(dot.isTappable)
        XCTAssertTrue(pointer.isFlat)
        XCTAssertFalse(map.isMyLocationEnabled)

        coordinator.parent = parent([], userLocation: location, userHeading: 5, showUserLocation: true)
        coordinator.syncUserLocation(on: map)
        XCTAssertTrue(coordinator.userLocationMarker === dot)
        XCTAssertTrue(coordinator.userHeadingMarker === pointer)
        XCTAssertEqual(pointer.rotation, 5, accuracy: 0.001)
        XCTAssertEqual(dot.position.latitude, location.coordinate.latitude, accuracy: 0.000001)
    }

    func testUnreliableHeadingAndHiddenLocationRemoveStaleOverlays() throws {
        let map = try map()
        let location = CLLocation(latitude: 43.65, longitude: -79.38)
        let coordinator = parent([], userLocation: location, userHeading: 90, showUserLocation: true).makeCoordinator()
        coordinator.syncUserLocation(on: map)
        coordinator.parent = parent([], userLocation: location, userHeading: .nan, showUserLocation: true)
        coordinator.syncUserLocation(on: map)
        XCTAssertNotNil(coordinator.userLocationMarker?.map)
        XCTAssertNil(coordinator.userHeadingMarker?.map)
        coordinator.parent = parent([])
        coordinator.syncUserLocation(on: map)
        XCTAssertNil(coordinator.userLocationMarker?.map)
        XCTAssertNil(coordinator.userHeadingMarker?.map)
        XCTAssertFalse(map.isMyLocationEnabled)
    }

}
