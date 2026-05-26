import XCTest
import CoreLocation
@testable import FLYR

final class ClientMapLinkerServiceTests: XCTestCase {
    func testContainmentLinkWinsForAddressInsideBuilding() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "building-1", ring: square(lon: -79.0, lat: 43.0, size: 0.001), street: "Main Street", house: "10")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: [
            address(id: "11111111-1111-1111-1111-111111111111", lon: -79.0, lat: 43.0, street: "Main St", house: "10")
        ])

        let summary = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: nil
        )

        XCTAssertEqual(summary.links.count, 1)
        XCTAssertEqual(summary.links.first?.buildingId, "building-1")
        XCTAssertEqual(summary.links.first?.matchType, "containment_verified")
        XCTAssertEqual(summary.progress.percent, 100)
    }

    func testParcelBridgeCanLinkNearbyAddressAndBuilding() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "building-2", ring: square(lon: -79.0004, lat: 43.0004, size: 0.00012), street: "Spruce Road", house: "22")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: [
            address(id: "22222222-2222-2222-2222-222222222222", lon: -79.0001, lat: 43.0001, street: "Spruce Rd", house: "22")
        ])
        let parcels = ParcelFeatureCollection(type: "FeatureCollection", features: [
            parcel(id: "parcel-1", ring: square(lon: -79.00025, lat: 43.00025, size: 0.001))
        ])

        let summary = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: parcels
        )

        XCTAssertEqual(summary.links.count, 1)
        XCTAssertEqual(summary.links.first?.matchType, "parcel_verified")
    }

    func testSemanticProximityLinksMatchingStreetAndHouseNumber() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "building-4", ring: square(lon: -79.00025, lat: 43.00025, size: 0.00008), street: "Queen Street", house: "44")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: [
            address(id: "44444444-4444-4444-4444-444444444444", lon: -79.0, lat: 43.0, street: "Queen St", house: "44")
        ])

        let summary = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: nil
        )

        XCTAssertEqual(summary.links.count, 1)
        XCTAssertEqual(summary.links.first?.buildingId, "building-4")
        XCTAssertEqual(summary.links.first?.matchType, "proximity_verified")
    }

    func testSemanticMismatchFallsBackToNearestValidBuilding() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "far-semantic-match", ring: square(lon: -79.001, lat: 43.001, size: 0.00008), street: "Pine Street", house: "50"),
            building(id: "nearest-mismatch", ring: square(lon: -79.00018, lat: 43.00018, size: 0.00008), street: "Elm Street", house: "99")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: [
            address(id: "55555555-5555-5555-5555-555555555555", lon: -79.0, lat: 43.0, street: "Pine St", house: "50")
        ])

        let summary = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: nil
        )

        XCTAssertEqual(summary.links.count, 1)
        XCTAssertEqual(summary.links.first?.buildingId, "nearest-mismatch")
        XCTAssertEqual(summary.links.first?.matchType, "proximity_fallback")
    }

    func testSingleUnitBuildingsAreNotReusedForAdjacentHomes() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "building-16", ring: square(lon: -79.0004, lat: 43.0000, size: 0.00008), street: "Bowsprit Ave", house: "16"),
            building(id: "building-18", ring: square(lon: -79.0002, lat: 43.0000, size: 0.00008), street: "Bowsprit Ave", house: "18"),
            building(id: "building-20", ring: square(lon: -79.0000, lat: 43.0000, size: 0.00008), street: "Bowsprit Ave", house: "20"),
            building(id: "building-22", ring: square(lon: -78.9998, lat: 43.0000, size: 0.00008), street: "Bowsprit Ave", house: "22"),
            building(id: "building-24", ring: square(lon: -78.9996, lat: 43.0000, size: 0.00008), street: "Bowsprit Ave", house: "24")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: [
            address(id: "16161616-1616-1616-1616-161616161616", lon: -79.0004, lat: 42.9998, street: "Bowsprit Ave", house: "16"),
            address(id: "18181818-1818-1818-1818-181818181818", lon: -79.0002, lat: 42.9998, street: "Bowsprit Ave", house: "18"),
            address(id: "20202020-2020-2020-2020-202020202020", lon: -79.0000, lat: 42.9998, street: "Bowsprit Ave", house: "20"),
            address(id: "22222222-2222-2222-2222-222222222222", lon: -78.9998, lat: 42.9998, street: "Bowsprit Ave", house: "22"),
            address(id: "24242424-2424-2424-2424-242424242424", lon: -78.9996, lat: 42.9998, street: "Bowsprit Ave", house: "24")
        ])

        let summary = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: nil
        )

        XCTAssertEqual(summary.links.count, 5)
        XCTAssertEqual(Set(summary.links.map(\.buildingId)).count, 5)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: summary.links.map { ($0.addressId, $0.buildingId) })[
                "20202020-2020-2020-2020-202020202020"
            ],
            "building-20"
        )
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: summary.links.map { ($0.addressId, $0.buildingId) })[
                "22222222-2222-2222-2222-222222222222"
            ],
            "building-22"
        )
    }

    func testEmptyAddressCampaignReportsCompleteProgress() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "building-empty", ring: square(lon: -79.0, lat: 43.0, size: 0.001), street: "Main Street", house: "10")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: [])

        let summary = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: nil
        )

        XCTAssertTrue(summary.links.isEmpty)
        XCTAssertEqual(summary.progress.percent, 100)
        XCTAssertFalse(summary.progress.isOptimizing)
    }

    func testProgressReportsInitialPartialAndComplete() async throws {
        let buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [
            building(id: "building-3", ring: square(lon: -79.0, lat: 43.0, size: 0.002), street: "King Street", house: "1")
        ])
        let addresses = AddressFeatureCollection(type: "FeatureCollection", features: (1...30).map {
            address(id: String(format: "33333333-3333-3333-3333-%012d", $0), lon: -79.0, lat: 43.0, street: "King St", house: "\($0)")
        })
        let collector = ProgressCollector()

        _ = await ClientMapLinkerService.shared.link(
            buildings: buildings,
            addresses: addresses,
            parcels: nil,
            progress: { progress in
                await collector.append(progress)
            }
        )

        let progressValues = await collector.values
        XCTAssertEqual(progressValues.first?.percent, 0)
        XCTAssertTrue(progressValues.contains(where: { $0.percent > 0 && $0.percent < 100 }))
        XCTAssertEqual(progressValues.last?.percent, 100)
    }

    private func building(id: String, ring: [[Double]], street: String, house: String) -> BuildingFeature {
        BuildingFeature(
            type: "Feature",
            id: id,
            geometry: geometry(type: "Polygon", coordinates: [ring]),
            properties: BuildingProperties(
                id: id,
                buildingId: id,
                addressId: nil,
                addressIds: [],
                gersId: id,
                height: 10,
                heightM: 10,
                minHeight: 0,
                isTownhome: false,
                unitsCount: 1,
                addressText: "\(house) \(street)",
                matchMethod: nil,
                featureStatus: nil,
                featureType: nil,
                status: "not_visited",
                scansToday: 0,
                scansTotal: 0,
                lastScanSecondsAgo: nil,
                houseNumber: house,
                streetName: street,
                confidence: nil,
                source: "test",
                addressCount: nil,
                areaSqm: 80,
                buildingType: "residential",
                qrScanned: false
            )
        )
    }

    private func address(id: String, lon: Double, lat: Double, street: String, house: String) -> AddressFeature {
        AddressFeature(
            type: "Feature",
            id: id,
            geometry: geometry(type: "Point", coordinates: [lon, lat]),
            properties: AddressProperties(
                id: id,
                gersId: id,
                buildingGersId: nil,
                houseNumber: house,
                streetName: street,
                postalCode: nil,
                locality: nil,
                formatted: "\(house) \(street)",
                source: "test"
            )
        )
    }

    private func parcel(id: String, ring: [[Double]]) -> ParcelFeature {
        ParcelFeature(
            type: "Feature",
            id: id,
            geometry: geometry(type: "Polygon", coordinates: [ring]),
            properties: ParcelProperties(
                id: id,
                parcelId: id,
                externalId: id,
                source: "test",
                areaSqm: 100
            )
        )
    }

    private func square(lon: Double, lat: Double, size: Double) -> [[Double]] {
        let half = size / 2
        return [
            [lon - half, lat - half],
            [lon + half, lat - half],
            [lon + half, lat + half],
            [lon - half, lat + half],
            [lon - half, lat - half]
        ]
    }

    private func geometry(type: String, coordinates: Any) -> MapFeatureGeoJSONGeometry {
        let object: [String: Any] = [
            "type": type,
            "coordinates": coordinates
        ]
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(MapFeatureGeoJSONGeometry.self, from: data)
    }
}

private actor ProgressCollector {
    private var storage: [ClientLinkingProgress] = []

    func append(_ progress: ClientLinkingProgress) {
        storage.append(progress)
    }

    var values: [ClientLinkingProgress] {
        storage
    }
}
