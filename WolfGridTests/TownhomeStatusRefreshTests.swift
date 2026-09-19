import XCTest
@testable import WolfGrid

@MainActor
final class TownhomeStatusRefreshTests: XCTestCase {
    private func fixture(count: Int = 1, units: Int = 3) throws -> ([BuildingFeature], [AddressFeature], [String: [UUID]]) {
        var buildings: [BuildingFeature] = []
        var addresses: [AddressFeature] = []
        var links: [String: [UUID]] = [:]
        for index in 0..<count {
            let key = "townhome-\(index)"
            let ids = (0..<units).map { _ in UUID() }
            buildings.append(try makeBuildingFeature(gersId: key, isTownhome: units > 1, unitsCount: units, addressCount: units))
            links[key] = ids
            for (unit, id) in ids.enumerated() {
                addresses.append(try makeAddressFeature(id: id, buildingGersId: key,
                    houseNumber: "\(unit + 1)", formatted: "\(unit + 1) Test Street"))
            }
        }
        return (buildings, addresses, links)
    }

    func testStatusRefreshMatchesFullRebuildForEveryStatusAndReset() throws {
        let (buildings, addresses, links) = try fixture()
        let ids = try XCTUnwrap(links.values.first)
        var cached = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: [:]))
        for status: AddressStatus in [.talked, .noAnswer, .delivered, .appointment, .futureSeller, .hotLead, .doNotKnock, .untouched, .none] {
            let statuses: [UUID: AddressStatus] = [ids[0]: status, ids[1]: .noAnswer]
            cached = try XCTUnwrap(MapLayerManager.updatingTownhomeOverlayStatuses(in: cached, addressStatuses: statuses))
            let rebuilt = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
                buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: statuses))
            XCTAssertEqual(cached, rebuilt, "State refresh must preserve all geometry and sibling units for \(status)")
            XCTAssertEqual(MapLayerManager.updatingTownhomeOverlayStatuses(in: cached, addressStatuses: statuses), cached)
        }
    }

    func testCoverageLockAndUnlockMatchFullRebuild() throws {
        let (buildings, addresses, links) = try fixture()
        let id = try XCTUnwrap(links.values.first?.first)
        var cached = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: [id: .talked]))
        for covered: Set<UUID> in [[id], []] {
            cached = try XCTUnwrap(MapLayerManager.updatingTownhomeOverlayStatuses(in: cached,
                addressStatuses: [id: .talked], workspaceCoveredAddressIds: covered))
            XCTAssertEqual(cached, MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
                buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links,
                addressStatuses: [id: .talked], workspaceCoveredAddressIds: covered))
        }
    }

    func testInvalidSnapshotRequiresFullRebuild() {
        XCTAssertNil(MapLayerManager.updatingTownhomeOverlayStatuses(in: Data("invalid".utf8), addressStatuses: [:]))
    }

    func testOwnershipChangesMatchFullRebuild() throws {
        let (buildings, addresses, links) = try fixture()
        let id = try XCTUnwrap(links.values.first?.first)
        let actor = UUID()
        let rowData = try JSONSerialization.data(withJSONObject: [
            "address_id": id.uuidString, "campaign_id": UUID().uuidString,
            "status": "delivered", "last_action_by": actor.uuidString, "updated_at": 0
        ])
        let row = try JSONDecoder().decode(AddressStatusRow.self, from: rowData)
        let cached = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: [:]))
        for user in [actor, UUID()] {
            XCTAssertEqual(MapLayerManager.updatingTownhomeOverlayStatuses(in: cached,
                addressStatuses: [id: .delivered], addressStatusRows: [id: row], currentUserId: user),
                MapLayerManager.buildTownhomeStatusOverlayGeoJSON(buildings: buildings, addresses: addresses,
                    orderedAddressIdsByBuilding: links, addressStatuses: [id: .delivered],
                    addressStatusRows: [id: row], currentUserId: user))
        }
    }

    func testStatusRefreshUsesReplacementGeometryAndLinks() throws {
        let (buildings, addresses, links) = try fixture()
        let ids = try XCTUnwrap(links.values.first)
        let replacement = try makeBuildingFeature(gersId: "townhome-0", width: 35)
        let newLinks = ["townhome-0": Array(ids.prefix(2))]
        let original = MapLayerManager.buildTownhomeStatusOverlayGeoJSON(buildings: buildings,
            addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: [:])
        let newGeometry = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(buildings: [replacement],
            addresses: addresses, orderedAddressIdsByBuilding: newLinks, addressStatuses: [:]))
        XCTAssertNotEqual(original, newGeometry)
        XCTAssertEqual(MapLayerManager.updatingTownhomeOverlayStatuses(in: newGeometry, addressStatuses: [ids[0]: .talked]),
            MapLayerManager.buildTownhomeStatusOverlayGeoJSON(buildings: [replacement], addresses: addresses,
                orderedAddressIdsByBuilding: newLinks, addressStatuses: [ids[0]: .talked]))
    }

    func testWarmStatusRefreshBenchmark() throws {
        let (buildings, addresses, links) = try fixture(count: 150)
        let id = try XCTUnwrap(links.values.first?.first)
        let baseline = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: [:]))
        var fullTimes: [Double] = []
        var statusTimes: [Double] = []
        for _ in 0..<3 {
            let fullStart = Date()
            let full = MapLayerManager.buildTownhomeStatusOverlayGeoJSON(buildings: buildings, addresses: addresses,
                orderedAddressIdsByBuilding: links, addressStatuses: [id: .talked])
            fullTimes.append(Date().timeIntervalSince(fullStart) * 1000)
            let statusStart = Date()
            let updated = MapLayerManager.updatingTownhomeOverlayStatuses(in: baseline, addressStatuses: [id: .talked])
            statusTimes.append(Date().timeIntervalSince(statusStart) * 1000)
            XCTAssertEqual(updated, full)
        }
        print("STATUS_BENCHMARK full_ms=\(fullTimes) status_ms=\(statusTimes)")
    }

    func testDetachedHomeStatusRefreshBenchmark() throws {
        let (buildings, addresses, links) = try fixture(count: 150, units: 1)
        let id = try XCTUnwrap(links.values.first?.first)
        let baseline = try XCTUnwrap(MapLayerManager.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings, addresses: addresses, orderedAddressIdsByBuilding: links, addressStatuses: [:]))
        var fullTimes: [Double] = []
        var statusTimes: [Double] = []
        for _ in 0..<3 {
            let fullStart = Date()
            let full = MapLayerManager.buildTownhomeStatusOverlayGeoJSON(buildings: buildings, addresses: addresses,
                orderedAddressIdsByBuilding: links, addressStatuses: [id: .talked])
            fullTimes.append(Date().timeIntervalSince(fullStart) * 1000)
            let statusStart = Date()
            let updated = MapLayerManager.updatingTownhomeOverlayStatuses(in: baseline, addressStatuses: [id: .talked])
            statusTimes.append(Date().timeIntervalSince(statusStart) * 1000)
            XCTAssertEqual(updated, full)
        }
        print("DETACHED_STATUS_BENCHMARK full_ms=\(fullTimes) status_ms=\(statusTimes)")
    }
    private func makeBuildingFeature(
        gersId: String,
        width: Double = 20,
        depth: Double = 6,
        isTownhome: Bool = true,
        unitsCount: Int = 3,
        addressCount: Int? = 3,
        addressIds: [UUID] = [],
        houseNumber: String? = nil,
        streetName: String? = nil,
        isLinked: Bool? = nil
    ) throws -> BuildingFeature {
        var properties: [String: Any] = [
            "id": gersId,
            "gers_id": gersId,
            "height": 10,
            "height_m": 10,
            "min_height": 0,
            "is_townhome": isTownhome,
            "units_count": unitsCount,
            "status": "not_visited",
            "scans_today": 0,
            "scans_total": 0
        ]
        if let addressCount {
            properties["address_count"] = addressCount
        }
        if !addressIds.isEmpty {
            properties["address_ids"] = addressIds.map(\.uuidString)
        }
        if addressIds.count == 1 {
            properties["address_id"] = addressIds[0].uuidString
        }
        if let houseNumber {
            properties["house_number"] = houseNumber
        }
        if let streetName {
            properties["street_name"] = streetName
        }
        if let houseNumber, let streetName {
            properties["address_text"] = "\(houseNumber) \(streetName)"
        }
        if let isLinked {
            properties["is_linked"] = isLinked
        }

        let payload: [String: Any] = [
            "type": "Feature",
            "id": gersId,
            "geometry": [
                "type": "Polygon",
                "coordinates": [[
                    [-79.0, 43.0],
                    [-79.0 + width / 10000.0, 43.0],
                    [-79.0 + width / 10000.0, 43.0 + depth / 10000.0],
                    [-79.0, 43.0 + depth / 10000.0],
                    [-79.0, 43.0]
                ]]
            ],
            "properties": properties
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try JSONDecoder().decode(BuildingFeature.self, from: data)
    }

    private func makeAddressFeature(
        id: UUID,
        buildingGersId: String,
        houseNumber: String,
        streetName: String = "Richfield Square",
        formatted: String,
        coordinate: [Double] = [-79.0, 43.0],
        pinPlacement: String = ""
    ) throws -> AddressFeature {
        let payload: [String: Any] = [
            "type": "Feature",
            "id": id.uuidString,
            "geometry": [
                "type": "Point",
                "coordinates": coordinate
            ],
            "properties": [
                "id": id.uuidString,
                "building_gers_id": buildingGersId,
                "pin_placement": pinPlacement,
                "house_number": houseNumber,
                "street_name": streetName,
                "formatted": formatted
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try JSONDecoder().decode(AddressFeature.self, from: data)
    }


}
