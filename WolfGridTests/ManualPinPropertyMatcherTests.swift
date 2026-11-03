import XCTest
import CoreLocation
import GRDB
@testable import WolfGrid

final class ManualPinPropertyMatcherTests: XCTestCase {
    private let pin = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let canonical = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private func address(_ id: UUID, manual: Bool, street: String = "Belmar St E", unit: String? = nil,
                         longitude: Double = -83.00005) -> AddressFeature {
        AddressFeature(type: "Feature", id: id.uuidString,
            geometry: .init(type: "Point", coordinates: .init(point: [longitude, 42.00005])),
            properties: AddressProperties(id: id.uuidString, buildingGersId: manual ? nil : "roof", houseNumber: "405",
                unit: unit, streetName: street, locality: "Windsor", formatted: "405 \(street)",
                source: manual ? "manual_pin" : "campaign", featureType: manual ? "manual_pin" : "address",
                parcelId: "lot", hasBuildingLink: !manual, hasParcelLink: true))
    }
    private func geometry() -> MapFeatureGeoJSONGeometry {
        .init(type: "Polygon", coordinates: .init(polygon: [[[-83.0001,42],[-83,42],[-83,42.0001],[-83.0001,42.0001],[-83.0001,42]]]))
    }
    private func fixture(addresses: [AddressFeature]? = nil) throws -> CampaignMapEditSnapshot {
        let building = try JSONDecoder().decode(BuildingFeature.self, from: JSONSerialization.data(withJSONObject: [
            "type": "Feature", "id": "roof", "geometry": ["type": "Polygon", "coordinates": geometry().asPolygon!],
            "properties": ["id": "roof", "gers_id": "roof", "height": 4, "address_id": canonical.uuidString,
                           "address_ids": [canonical.uuidString], "address_count": 1]
        ]))
        let lotGeometry = MapFeatureGeoJSONGeometry(type: "Polygon", coordinates: .init(polygon: [
            [[-83.00015,41.99995],[-82.99995,41.99995],[-82.99995,42.00015],[-83.00015,42.00015],[-83.00015,41.99995]]
        ]))
        let parcel = ParcelFeature(type: "Feature", id: "lot", geometry: lotGeometry,
            properties: ParcelProperties(id: "lot", parcelId: "lot", externalId: nil, source: nil, areaSqm: nil,
                                         addressId: canonical.uuidString, addressIds: [canonical.uuidString]))
        return .init(buildings: [building], addresses: addresses ?? [address(pin, manual: true, street: "E Belmar Street"), address(canonical, manual: false)], parcels: [parcel])
    }
    private func matches(_ snapshot: CampaignMapEditSnapshot, state: CampaignMapEditState = .init()) -> [ManualPinPropertyMatcher.Match] {
        ManualPinPropertyMatcher.matches(addresses: snapshot.addresses, buildings: snapshot.buildings, parcels: snapshot.parcels, state: state)
    }

    func testPinAdoptsExistingAddressGeometryAndKeepsItsActivityIdentity() throws {
        let original = try fixture()
        let found = matches(original)
        XCTAssertEqual(found.count, 1)
        let changes = ManualPinPropertyMatcher.changes(for: found, unusedAddressIDs: [canonical], state: .init(), sourceRevision: "test")
        let state = CampaignMapEditState().applying(changes)
        try CampaignMapEdits.validateParcelAssignments(changes, state: .init(), addresses: original.addresses, parcels: original.parcels)
        let corrected = CampaignMapEdits.snapshot(buildings: original.buildings, addresses: original.addresses, parcels: original.parcels, state: state)
        XCTAssertEqual(corrected.addresses.count, 1)
        let kept = try XCTUnwrap(corrected.addresses.first)
        XCTAssertEqual(UUID(uuidString: kept.properties.id!), pin, "The ID carrying saved visits and contacts must survive")
        XCTAssertEqual(kept.properties.buildingGersId, "roof")
        XCTAssertEqual(kept.properties.parcelId, "lot")
        XCTAssertFalse(MapLayerManager.isManualPinAddressFeature(kept))
        XCTAssertEqual(corrected.buildings.first?.properties.addressUUIDs, [pin])
        XCTAssertEqual(Set(corrected.parcels.first?.properties.addressIds ?? []), [pin.uuidString.lowercased()])
        let undone = CampaignMapEdits.snapshot(buildings: original.buildings, addresses: original.addresses, parcels: original.parcels, state: .init())
        XCTAssertEqual(undone.addresses.count, 2)
        XCTAssertTrue(MapLayerManager.isManualPinAddressFeature(undone.addresses[0]))
    }

    func testUnverifiedSourceActivityNeverAllowsCoalescing() throws {
        let found = matches(try fixture())
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(ManualPinPropertyMatcher.changes(for: found, unusedAddressIDs: [], state: .init(), sourceRevision: nil).isEmpty)
    }

    func testLegacyParcelLinkedManualAddressAlsoNormalizes() throws {
        let original = try fixture()
        let field = original.addresses[0]
        let legacy = AddressFeature(type: field.type, id: field.id, geometry: field.geometry,
            properties: CampaignMapEdits.patch(field.properties, ["source": "manual", "feature_type": NSNull()]))
        XCTAssertFalse(MapLayerManager.isManualPinAddressFeature(legacy))
        let snapshot = try fixture(addresses: [legacy, original.addresses[1]])
        let found = matches(snapshot)
        XCTAssertEqual(found.count, 1)
        let changes = ManualPinPropertyMatcher.changes(for: found, unusedAddressIDs: [canonical], state: .init(), sourceRevision: nil)
        let corrected = CampaignMapEdits.snapshot(buildings: snapshot.buildings, addresses: snapshot.addresses, parcels: snapshot.parcels,
                                                 state: CampaignMapEditState().applying(changes))
        XCTAssertEqual(corrected.addresses.first?.properties.featureType, "address")
        XCTAssertEqual(corrected.buildings.first?.properties.addressUUIDs, [pin])
    }

    func testDifferentStreetUnitLocationOrHouseDoesNotMatch() throws {
        for manual in [address(pin, manual: true, street: "Belmar St W"),
                       address(pin, manual: true, unit: "2"),
                       address(pin, manual: true, longitude: -83.0002)] {
            XCTAssertTrue(matches(try fixture(addresses: [manual, address(canonical, manual: false)])).isEmpty)
        }
        let wrongHouse = CampaignMapEdits.patch(address(pin, manual: true).properties, ["house_number": "403", "formatted": "403 Belmar St E"])
        let manual = AddressFeature(type: "Feature", id: pin.uuidString, geometry: address(pin, manual: true).geometry, properties: wrongHouse)
        XCTAssertTrue(matches(try fixture(addresses: [manual, address(canonical, manual: false)])).isEmpty)
    }

    func testExplicitCorrectionsAndMultipleSavedPinsRemainUntouched() throws {
        let original = try fixture()
        var state = CampaignMapEditState()
        state.features[CampaignMapItem(.address, pin.uuidString).id] = .init(buildingLinkSet: true)
        XCTAssertTrue(matches(original, state: state).isEmpty)
        let extraPin = address(UUID(), manual: true)
        XCTAssertTrue(matches(try fixture(addresses: original.addresses + [extraPin])).isEmpty)
        let extraCanonical = address(UUID(), manual: false)
        XCTAssertTrue(matches(try fixture(addresses: original.addresses + [extraCanonical])).isEmpty)
    }

    func testMatchingUnitAndParcelOnlyPropertyAreSupported() throws {
        let original = try fixture(addresses: [address(pin, manual: true, unit: "2"), address(canonical, manual: false, unit: "2")])
        let found = ManualPinPropertyMatcher.matches(addresses: original.addresses, buildings: [], parcels: original.parcels, state: .init())
        XCTAssertEqual(found.count, 1)
        XCTAssertNil(found.first?.buildingID)
        XCTAssertEqual(found.first?.parcelID, "lot")
    }

    func testPropertyGeometryAllowsMissingOrDifferentLocalityMetadata() throws {
        let original = try fixture()
        let imported = original.addresses[1]
        let properties = CampaignMapEdits.patch(imported.properties, ["locality": "City of Windsor", "postal_code": "N9C"])
        let target = AddressFeature(type: "Feature", id: imported.id, geometry: imported.geometry, properties: properties)
        XCTAssertEqual(matches(try fixture(addresses: [original.addresses[0], target])).count, 1)
    }

    func testConflictingBuildingAndParcelGeometryRemainsAStandalonePin() throws {
        let original = try fixture()
        let lot = original.parcels[0]
        let wrongGeometry = MapFeatureGeoJSONGeometry(type: "Polygon", coordinates: .init(polygon: [
            [[-82,42],[-81.9,42],[-81.9,42.1],[-82,42.1],[-82,42]]
        ]))
        let wrongParcel = ParcelFeature(type: lot.type, id: lot.id, geometry: wrongGeometry, properties: lot.properties)
        let found = ManualPinPropertyMatcher.matches(addresses: original.addresses, buildings: original.buildings,
                                                     parcels: [wrongParcel], state: .init())
        XCTAssertTrue(found.isEmpty)
    }

    func testOfflineStatusesContactsAndPendingWritesProtectSourceRows() async throws {
        let db = try DatabaseQueue(path: ":memory:")
        try await db.write { db in
            try db.execute(sql: "CREATE TABLE cached_address_statuses (id TEXT, campaign_id TEXT, address_id TEXT, building_id TEXT, status TEXT, outcome TEXT, notes TEXT, payload_json TEXT, updated_at TEXT, dirty INTEGER)")
            try db.execute(sql: "CREATE TABLE cached_contacts (address_id TEXT)")
            try db.execute(sql: "CREATE TABLE sync_outbox (payload_json TEXT, synced_at TEXT)")
        }
        let repository = CampaignRepository(dbQueue: db)
        let contactID = UUID(), pendingID = UUID(), unusedID = UUID()
        try await db.write { db in
            try db.execute(sql: "INSERT INTO cached_address_statuses (id, campaign_id, address_id, status, dirty) VALUES ('status','campaign',?,'talked',1)", arguments: [canonical.uuidString])
            try db.execute(sql: "INSERT INTO cached_contacts VALUES (?)", arguments: [contactID.uuidString])
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?,NULL)", arguments: ["{\"addressId\":\"\(pendingID.uuidString)\"}"])
        }
        let unreferenced = try await repository.addressesWithoutLocalActivity(campaignId: "campaign", candidates: [canonical, contactID, pendingID, unusedID])
        XCTAssertEqual(unreferenced, [unusedID])
    }
}
