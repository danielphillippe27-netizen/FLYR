import XCTest
import GRDB
@testable import WolfGrid

final class FarmMapPerformanceTests: XCTestCase {
    private struct FullFixture: Decodable { let bundle: CanonicalCampaignMapBundle }

    func testAtomicStatusSaveQueuesRevisionAndRollsBackOnFarmFailure() async throws {
        let queue = try DatabaseQueue()
        try OfflineMigrations.migrator().migrate(queue)
        let repository = CampaignRepository(dbQueue: queue)
        let campaignId = UUID(), addressId = UUID(), sessionId = UUID()
        let context = FarmExecutionContext(farmId: UUID(), farmName: "Test", touchId: UUID(),
            touchTitle: "Doors", touchDate: Date(), touchType: .doorKnock, campaignId: campaignId,
            cycleNumber: 1, cycleName: nil)
        func save(_ status: AddressStatus) async throws -> [AddressStatusRow] {
            try await repository.updateStatusLocally(addressIds: [addressId], campaignId: campaignId,
                buildingId: "house", status: status, notes: nil, occurredAt: Date(), sessionId: sessionId,
                farmExecutionContext: context) { revisions in
                AddressStatusOutboxPayload(campaignId: campaignId.uuidString, addressIds: [addressId.uuidString],
                    buildingId: "house", status: status.rawValue, notes: nil, sessionId: sessionId.uuidString,
                    sessionTargetId: "house", sessionEventType: nil, latitude: nil, longitude: nil,
                    occurredAt: OfflineDateCodec.string(from: Date()), farmExecutionContext: OfflineFarmExecutionPayload(context: context),
                    baseRevisions: revisions, overrideReason: nil)
            }
        }
        let first = try await save(.talked)
        XCTAssertEqual(first.first?.revision, 1)
        let second = try await save(.noAnswer)
        XCTAssertEqual(second.first?.revision, 2)
        try await queue.read { db in
            let entries = try OutboxEntry.fetchAll(db)
            XCTAssertEqual(entries.count, 2)
            let revisions = entries.compactMap { $0.decodedPayload(AddressStatusOutboxPayload.self)?.baseRevisions?[addressId.uuidString.lowercased()] }.sorted()
            XCTAssertEqual(revisions, [0, 1])
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_farm_touch_address_statuses"), 1)
        }
        try await queue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_test_farm_update BEFORE UPDATE ON cached_farm_touch_address_statuses BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        }
        do {
            _ = try await save(.hotLead)
            XCTFail("A farm write failure must fail the entire save")
        } catch { }
        try await queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 2)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM cached_address_statuses"), AddressStatus.noAnswer.rawValue)
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT status FROM cached_farm_touch_address_statuses"), AddressStatus.noAnswer.rawValue)
        }
    }

    func testLocalSessionTouchPersistsActivityAndSyncIntentTogether() throws {
        let queue = try DatabaseQueue()
        try OfflineMigrations.migrator().migrate(queue)
        let touch = FarmTouch(farmId: UUID(), cycleNumber: 2, date: Date(),
                              type: .doorKnock, mode: "doorknock", title: "Field session", campaignId: UUID())
        try queue.write { db in try FarmOfflineRepository.persistSessionTouch(touch, in: db) }
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT dirty FROM cached_farm_touches WHERE id = ?", arguments: [touch.id.uuidString]), 1)
            let entry = try XCTUnwrap(OutboxEntry.fetchOne(db, sql: "SELECT * FROM sync_outbox WHERE entity_id = ?", arguments: [touch.id.uuidString]))
            let queued = try XCTUnwrap(entry.decodedPayload(FarmTouchOutboxPayload.self))
            XCTAssertEqual(queued.touch.id, touch.id)
            XCTAssertEqual(queued.touch.cycleNumber, 2)
            XCTAssertEqual(entry.operation, OutboxOperation.createFarmTouch.rawValue)
        }
        enum TestFailure: Error { case interrupted }
        let interrupted = FarmTouch(farmId: UUID(), date: Date(), type: .flyer, mode: "flyer", title: "Interrupted")
        XCTAssertThrowsError(try queue.write { db in
            try FarmOfflineRepository.persistSessionTouch(interrupted, in: db)
            throw TestFailure.interrupted
        })
        try queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cached_farm_touches WHERE id = ?", arguments: [interrupted.id.uuidString]), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [interrupted.id.uuidString]), 0)
        }
    }

    func testFarmTouchModesUseServerValues() {
        let door = FarmTouch(farmId: UUID(), date: Date(), type: .doorKnock, mode: "door_knock", title: "Door Knock")
        let flyer = FarmTouch(farmId: UUID(), date: Date(), type: .flyer, mode: "flyer", title: "Flyer")
        let serverDoor = FarmTouch(farmId: UUID(), date: Date(), type: .doorKnock, mode: "doorknock", title: "Door Knock")
        XCTAssertEqual(door.persistedModeRawValue, "doorknock")
        XCTAssertEqual(flyer.persistedModeRawValue, "flyer")
        XCTAssertEqual(serverDoor.effectiveModeDisplayName, "Door Knock")
    }

    func testMapRevisionTracksOnlyAffectedCampaignContent() throws {
        let queue = try DatabaseQueue()
        try OfflineMigrations.migrator().migrate(queue)
        try queue.write { db in
            func revision(_ id: String) throws -> Int {
                try Int.fetchOne(db, sql: "SELECT revision FROM campaign_map_content_revisions WHERE campaign_id = ?", arguments: [id]) ?? 0
            }
            try db.execute(sql: "INSERT INTO cached_parcels(id, campaign_id, geometry_geojson) VALUES ('p', 'farm-a', '{}')")
            let first = try revision("farm-a")
            XCTAssertGreaterThan(first, 0)
            try db.execute(sql: "INSERT INTO cached_parcels(id, campaign_id, geometry_geojson) VALUES ('q', 'farm-b', '{}')")
            XCTAssertEqual(try revision("farm-a"), first)
            try db.execute(sql: "UPDATE cached_parcels SET campaign_id = 'farm-b' WHERE id = 'p'")
            XCTAssertGreaterThan(try revision("farm-a"), first)
            let moved = try revision("farm-b")
            try db.execute(sql: "DELETE FROM cached_parcels WHERE id = 'p'")
            XCTAssertGreaterThan(try revision("farm-b"), moved)
        }
    }

    func testLargeCachedMapDecodePreservesRecordOrderAndSkipsInvalidRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("map.sqlite").path
        var configuration = Configuration()
        configuration.journalMode = .wal
        let queue = try DatabaseQueue(path: path, configuration: configuration)
        try OfflineMigrations.migrator().migrate(queue)
        var readConfiguration = Configuration()
        readConfiguration.readonly = true
        let reader = try DatabaseQueue(path: path, configuration: readConfiguration)
        let repository = CampaignRepository(dbQueue: queue, metadataReadQueue: reader)
        let campaign = UUID().uuidString
        let geometry = MapFeatureGeoJSONGeometry(type: "Point", coordinates: .init(point: [-78.0, 44.0]))
        let ids = (0..<3001).map { _ in UUID().uuidString }
        try await queue.write { db in
            for id in ids {
                let address = AddressFeature(id: id, geometry: geometry, properties: .init(id: id, formatted: "Test address"))
                let payload = try XCTUnwrap(OfflineJSONCodec.encodeMapCache(address))
                try db.execute(sql: "INSERT INTO cached_addresses(id, campaign_id, payload_json) VALUES (?, ?, ?)", arguments: [id, campaign, payload])
            }
            try db.execute(sql: "INSERT INTO cached_addresses(id, campaign_id, payload_json) VALUES (?, ?, ?)", arguments: ["invalid", campaign, "not-json"])
        }
        let expected = try await queue.read { db in
            try String.fetchAll(db, sql: "SELECT payload_json FROM cached_addresses WHERE campaign_id = ?", arguments: [campaign])
                .compactMap { OfflineJSONCodec.decode(AddressFeature.self, from: $0)?.id }
        }
        let bundle = await repository.getCampaignMapBundle(campaignId: campaign)
        XCTAssertEqual(bundle?.addresses.features.compactMap(\.id), expected)
        XCTAssertEqual(expected.count, ids.count)
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM cached_addresses WHERE id = ?", arguments: [ids[0]])
        }
        let refreshed = await repository.getCampaignMapBundle(campaignId: campaign)
        XCTAssertEqual(refreshed?.addresses.features.count, ids.count - 1)
        XCTAssertFalse(refreshed?.addresses.features.contains { $0.id == ids[0] } ?? true)
    }

    func testCompactParcelLookupUsesExactGeometry() throws {
        let directory = URL(fileURLWithPath: "/tmp/wolfgrid-bowmanville-two-latest-tiles")
        let bundleURL = directory.appendingPathComponent("bundle-v3.json")
        let packURL = directory.appendingPathComponent("canonical-geometry.wgp")
        guard FileManager.default.fileExists(atPath: bundleURL.path),
              FileManager.default.fileExists(atPath: packURL.path) else {
            throw XCTSkip("The local Bowmanville performance fixture is not available.")
        }
        let campaign = try JSONDecoder().decode(CanonicalCompactCampaign.self, from: Data(contentsOf: bundleURL, options: .mappedIfSafe))
        let index = try CanonicalCompactFieldIndex(campaign: campaign, pack: CanonicalGeometryPack(url: packURL))
        for parcel in campaign.records.parcels.prefix(500) where parcel.coordinate.count >= 2 {
            guard let geometry = try index.geometry(featureId: parcel.featureId),
                  CanonicalParcelFieldGeometry.contains(parcel.coordinate, in: geometry),
                  let found = index.parcelContaining(longitude: parcel.coordinate[0], latitude: parcel.coordinate[1]) else { continue }
            XCTAssertEqual(found.featureId, parcel.featureId)
            return
        }
        XCTFail("The fixture should contain an unambiguous parcel at its stored coordinate.")
    }

    func testBowmanvilleCachedRecordsTenTimes() async throws {
        let url = URL(fileURLWithPath: "/tmp/wolfgrid-bowmanville-two-latest-tiles/fixture.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("The local Bowmanville performance fixture is not available.") }
        let fixture = try JSONDecoder.supabaseDates.decode(FullFixture.self, from: Data(contentsOf: url, options: .mappedIfSafe))
        let campaignId = UUID().uuidString
        let repository = CampaignRepository.shared
        let persisted = await repository.replaceCampaignMapBundle(campaignId: campaignId, bundle: fixture.bundle)
        XCTAssertTrue(persisted)
        guard persisted else { return }
        var measurements: [String] = []
        for iteration in 1...10 {
            // Simulate unrelated writes so each run exercises the disk decode path.
            await repository.updateDownloadState(campaignId: campaignId, status: "ready", progress: Double(iteration) / 10)
            let start = CFAbsoluteTimeGetCurrent()
            let bundle = await repository.getCampaignMapBundle(campaignId: campaignId)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            XCTAssertEqual(bundle?.addresses.features.count, fixture.bundle.addresses.features.count)
            XCTAssertEqual(bundle?.buildings.features.count, fixture.bundle.buildings.features.count)
            XCTAssertEqual(bundle?.parcels.features.count, fixture.bundle.parcels.features.count)
            XCTAssertEqual(Set(bundle?.addresses.features.compactMap(\.id) ?? []), Set(fixture.bundle.addresses.features.compactMap(\.id)))
            XCTAssertEqual(Set(bundle?.buildings.features.compactMap(\.id) ?? []), Set(fixture.bundle.buildings.features.compactMap(\.id)))
            XCTAssertEqual(Set(bundle?.parcels.features.compactMap(\.id) ?? []), Set(fixture.bundle.parcels.features.compactMap(\.id)))
            measurements.append("iteration=\(iteration) cached_records_ms=\(Int(elapsed * 1000))")
        }
        let attachment = XCTAttachment(string: measurements.joined(separator: "\n"))
        attachment.name = "Bowmanville cached-record timings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBowmanvilleCompactMapAndBuildingLookupTenTimes() throws {
        let directory = URL(fileURLWithPath: "/tmp/wolfgrid-bowmanville-two-latest-tiles")
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("bundle-v3.json").path) else {
            throw XCTSkip("The local Bowmanville performance fixture is not available.")
        }
        let data = try Data(contentsOf: directory.appendingPathComponent("bundle-v3.json"), options: .mappedIfSafe)
        let packURL = directory.appendingPathComponent("canonical-geometry.wgp")
        let building = "durham_buildings:167656"
        let address = "0003ab86-a6f9-4ae1-bca6-e6776f55b772"
        var measurements: [String] = []
        for iteration in 1...10 {
            let start = CFAbsoluteTimeGetCurrent()
            let campaign = try JSONDecoder().decode(CanonicalCompactCampaign.self, from: data)
            let index = try CanonicalCompactFieldIndex(campaign: campaign, pack: CanonicalGeometryPack(url: packURL))
            let loaded = CFAbsoluteTimeGetCurrent()
            let feature = try index.exactBuildingFeature(id: building)
            let addressFeature = index.addressFeature(id: address)
            let linked = index.addressIds(forBuilding: building)
            let tapped = CFAbsoluteTimeGetCurrent()
            XCTAssertNotNil(feature)
            XCTAssertNotNil(addressFeature)
            XCTAssertTrue(linked.contains(address))
            measurements.append("iteration=\(iteration) load_ms=\(Int((loaded-start)*1000)) lookup_ms=\(Int((tapped-loaded)*1000)) buildings=\(campaign.records.buildings.count) addresses=\(campaign.records.addresses.count) parcels=\(campaign.records.parcels.count)")
        }
        let attachment = XCTAttachment(string: measurements.joined(separator: "\n"))
        attachment.name = "Bowmanville ten-run timings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
