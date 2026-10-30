import XCTest
import MapboxMaps
@testable import WolfGrid

@MainActor
final class AddressLayerVisibilityTests: XCTestCase {
    private var emptyStyle: String {
        "{\"version\":8,\"name\":\"\(UUID().uuidString)\",\"sources\":{},\"layers\":[]}"
    }

    private func loadStyle(on map: MapView) async throws {
        let loaded = expectation(description: "Local Mapbox style loaded")
        var failure: Error?
        map.mapboxMap.loadStyle(emptyStyle) { error in
            failure = error
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 10)
        if let failure { throw failure }
    }

    private func assertVisibility(_ visible: Bool, on map: MapView,
                                  file: StaticString = #filePath, line: UInt = #line) {
        for id in [MapLayerManager.addressesLayerId, MapLayerManager.selectedAddressesLayerId] {
            XCTAssertTrue(map.mapboxMap.layerExists(withId: id), file: file, line: line)
            XCTAssertEqual(map.mapboxMap.layerProperty(for: id, property: "visibility").value as? String,
                           visible ? "visible" : "none", file: file, line: line)
        }
    }

    private func addresses(_ count: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "type": "FeatureCollection",
            "features": (0..<count).map { number in
                ["type": "Feature", "id": "address-\(number)",
                 "geometry": ["type": "Point", "coordinates": [-79.38 + Double(number) * 0.001, 43.65]],
                 "properties": ["id": "address-\(number)", "status": "untouched"]] as [String: Any]
            }
        ])
    }

    func testBaseMapCleanupPreservesCampaignTileNumberLayers() async throws {
        let map = MapView(frame: CGRect(x: 0, y: 0, width: 300, height: 400),
                          mapInitOptions: MapInitOptions(styleURI: nil))
        try await loadStyle(on: map)
        let mapbox = try XCTUnwrap(map.mapboxMap)
        try mapbox.addSource(GeoJSONSource(id: "label-test-source"))
        for id in ["basemap-house-number", "diamond-addresses-numbers", "diamond-buildings-address-numbers"] {
            try mapbox.addLayer(SymbolLayer(id: id, source: "label-test-source"))
        }
        MapTheme.hideBaseMapBuildingLayers(on: mapbox)
        MapTheme.hideBaseMapAddressNumberLayers(on: mapbox)
        XCTAssertEqual(mapbox.layerProperty(for: "basemap-house-number", property: "visibility").value as? String, "none")
        for id in ["diamond-addresses-numbers", "diamond-buildings-address-numbers"] {
            XCTAssertNotEqual(mapbox.layerProperty(for: id, property: "visibility").value as? String, "none")
        }
    }

    func testBuildingModeSurvivesLateAddressDataAndModeSwitches() async throws {
        let map = MapView(frame: CGRect(x: 0, y: 0, width: 300, height: 400),
                          mapInitOptions: MapInitOptions(styleURI: nil))
        try await loadStyle(on: map)
        let manager = MapLayerManager(mapView: map)
        manager.includeBuildingsLayer = false
        manager.includeAddressesLayer = true // Both families stay installed in the campaign map.
        manager.setAddressExtrusionVisibility(isVisible: false)
        manager.setupAddressesLayer()
        assertVisibility(false, on: map)
        manager.updateAddresses(try addresses(2))
        assertVisibility(false, on: map)

        manager.setAddressExtrusionVisibility(isVisible: true) // Pin mode (or mixed map editing).
        assertVisibility(true, on: map)
        manager.updateAddresses(try addresses(3))
        assertVisibility(true, on: map)

        manager.setAddressExtrusionVisibility(isVisible: false)
        manager.updateAddresses(try addresses(4))
        assertVisibility(false, on: map)
    }

    func testBuildingModeSurvivesStyleReload() async throws {
        let map = MapView(frame: CGRect(x: 0, y: 0, width: 300, height: 400),
                          mapInitOptions: MapInitOptions(styleURI: nil))
        try await loadStyle(on: map)
        let manager = MapLayerManager(mapView: map)
        manager.includeBuildingsLayer = false
        manager.includeAddressesLayer = true
        manager.setAddressExtrusionVisibility(isVisible: false)
        manager.setupAddressesLayer()
        manager.updateAddresses(try addresses(2))
        try await loadStyle(on: map)
        manager.setupAddressesLayer()
        assertVisibility(false, on: map)
        manager.updateAddresses(try addresses(3))
        assertVisibility(false, on: map)
    }
}
