import XCTest
import GRDB
import CoreLocation
@testable import WolfGrid

final class AutomaticBuildingLocationTests: XCTestCase {
    private func payload() -> ManualAddressCreateOutboxPayload {
        ManualAddressCreateOutboxPayload(
            campaignId: "campaign", addressId: UUID().uuidString,
            formatted: AutomaticBuildingLocation.placeholder,
            houseNumber: nil, streetName: nil, locality: nil, region: nil,
            postalCode: nil, country: nil, buildingId: "building",
            addressProvenance: AutomaticBuildingLocation.provenance,
            userConfirmed: false, parcelId: "parcel", campaignParcelId: "campaign-parcel",
            hasParcelLink: true, latitude: 43.9, longitude: -78.8
        )
    }

    func testGeocodingEnrichesDescriptionWithoutChangingIdentityOrPlacement() throws {
        let original = payload()
        let resolved = try XCTUnwrap(AutomaticBuildingLocation.resolvedPayload(
            original, thoroughfare: "  292 Northglen Boulevard  ", locality: "Clarington",
            region: "ON", postalCode: "L1C", country: "Canada"
        ))
        XCTAssertEqual(resolved.addressId, original.addressId)
        XCTAssertEqual(resolved.campaignId, original.campaignId)
        XCTAssertEqual(resolved.buildingId, original.buildingId)
        XCTAssertEqual(resolved.latitude, original.latitude)
        XCTAssertEqual(resolved.longitude, original.longitude)
        XCTAssertEqual(resolved.parcelId, original.parcelId)
        XCTAssertEqual(resolved.formatted, "292 Northglen Boulevard")
        XCTAssertEqual(resolved.houseNumber, "292")
        XCTAssertFalse(resolved.userConfirmed)
        XCTAssertEqual(resolved.addressProvenance, AutomaticBuildingLocation.resolvedProvenance)
    }

    func testRoadOrLocalityDoesNotBecomeAFabricatedHouseAddress() {
        for thoroughfare in [nil, "", "Northglen Boulevard", "Clarington", "292"] as [String?] {
            XCTAssertNil(AutomaticBuildingLocation.resolvedPayload(
                payload(), thoroughfare: thoroughfare,
                locality: nil, region: nil, postalCode: nil, country: nil
            ))
        }
    }

    @MainActor
    func testRapidTapsShareOneCreationAndFailedCreationCanBeRetried() async throws {
        let input = ManualAddressCreateInput(
            coordinate: CLLocationCoordinate2D(latitude: 43.9, longitude: -78.8),
            formatted: AutomaticBuildingLocation.placeholder,
            houseNumber: nil, streetName: nil, locality: nil, region: nil,
            postalCode: nil, country: nil, buildingId: "building",
            addressProvenance: AutomaticBuildingLocation.provenance, userConfirmed: false
        )
        let id = UUID()
        let response = ManualAddressCreateResponse(address: CampaignAddressResponse(
            id: id, houseNumber: nil, streetName: nil, formatted: input.formatted,
            locality: nil, region: nil, postalCode: nil, buildingGersId: input.buildingId
        ), linkedBuildingId: input.buildingId)
        let (stream, gate) = AsyncStream<Void>.makeStream()
        var count = 0
        let service = UnlinkedBuildingLocationService { _, _ in
            count += 1
            for await _ in stream { break }
            return response
        }
        let first = Task { try await service.create(campaignId: "campaign", input: input) }
        while count == 0 { await Task.yield() }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return try await service.create(campaignId: "CAMPAIGN", input: input)
        }
        while !secondStarted { await Task.yield() }
        await Task.yield()
        gate.yield(())
        gate.finish()
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult.address.id, secondResult.address.id)
        XCTAssertEqual(count, 1)

        var attempts = 0
        let retryService = UnlinkedBuildingLocationService { _, _ in
            attempts += 1
            if attempts == 1 { throw BuildingLinkError.fetchFailed }
            return response
        }
        do {
            _ = try await retryService.create(campaignId: "campaign", input: input)
            XCTFail("Expected local creation failure")
        } catch {}
        let retried = try await retryService.create(campaignId: "campaign", input: input)
        XCTAssertEqual(retried.address.id, id)
        XCTAssertEqual(attempts, 2)
    }

    private func makeQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE cached_addresses (
                  id TEXT PRIMARY KEY, campaign_id TEXT, building_id TEXT, address TEXT,
                  unit TEXT, city TEXT, province TEXT, postal_code TEXT, latitude REAL,
                  longitude REAL, payload_json TEXT, updated_at TEXT
                );
                CREATE TABLE cached_building_address_links (
                  id TEXT PRIMARY KEY, campaign_id TEXT, building_id TEXT, address_id TEXT,
                  confidence REAL, source TEXT, updated_at TEXT
                );
                CREATE TABLE sync_outbox (
                  id TEXT PRIMARY KEY, client_mutation_id TEXT, entity_type TEXT, entity_id TEXT,
                  operation TEXT, operation_version INTEGER, payload_json TEXT, status TEXT,
                  dependency_key TEXT, created_at TEXT, attempted_at TEXT, synced_at TEXT,
                  retry_after TEXT, retry_count INTEGER, error_message TEXT, dead_lettered_at TEXT
                );
                """)
        }
        return queue
    }

    func testLocationLinkAndCreationAreCommittedTogetherAndSurviveRefresh() async throws {
        let queue = try makeQueue()
        let repository = CampaignRepository(dbQueue: queue)
        let original = payload()
        let addressId = try XCTUnwrap(UUID(uuidString: original.addressId))
        let entry = try XCTUnwrap(OutboxRepository.makeEntry(
            entityType: "address", entityId: "campaign:\(addressId.uuidString.lowercased())",
            operation: .createManualAddress, payload: original
        ))
        let input = ManualAddressCreateInput(
            coordinate: CLLocationCoordinate2D(latitude: original.latitude, longitude: original.longitude),
            formatted: original.formatted, houseNumber: nil, streetName: nil,
            locality: nil, region: nil, postalCode: nil, country: nil,
            buildingId: original.buildingId, addressProvenance: original.addressProvenance,
            userConfirmed: false
        )
        try await repository.persistManualAddressLocally(campaignId: "campaign", addressId: addressId, input: input, outboxEntry: entry)
        await repository.upsertAddresses(campaignId: "campaign", features: [])
        let merged = await repository.mergingPendingAddressMutations(
            campaignId: "campaign", into: AddressFeatureCollection(type: "FeatureCollection", features: [])
        )
        XCTAssertEqual(merged.features.count, 1)
        let reopened = try await repository.cachedBuildingLocation(campaignId: "campaign", buildingId: "building")
        XCTAssertEqual(reopened?.response.address.id, addressId)
        XCTAssertEqual(reopened?.coordinate.latitude, original.latitude)
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_addresses"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_building_address_links"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 1)
        }
        // A failed outbox insert must roll the newly inserted location back.
        let anotherId = UUID()
        do {
            try await repository.persistManualAddressLocally(campaignId: "campaign", addressId: anotherId, input: input, outboxEntry: entry)
            XCTFail("Expected duplicate outbox row to abort the transaction")
        } catch {}
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_addresses"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_building_address_links"), 1)
        }

        // A stale download must not restore a location removed while its
        // creation is still pending.
        try queue.write { db in
            try db.execute(sql: "DELETE FROM cached_addresses")
            try db.execute(sql: "DELETE FROM cached_building_address_links")
        }
        await repository.upsertAddresses(campaignId: "campaign", features: merged.features)
        let removed = await repository.mergingPendingAddressMutations(campaignId: "campaign", into: merged)
        XCTAssertTrue(removed.features.isEmpty)
        let removedLocation = try await repository.cachedBuildingLocation(campaignId: "campaign", buildingId: "building")
        XCTAssertNil(removedLocation)
    }
}
