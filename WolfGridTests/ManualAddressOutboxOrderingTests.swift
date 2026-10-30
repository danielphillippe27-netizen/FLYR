import XCTest
import GRDB
@testable import WolfGrid

final class ManualAddressOutboxOrderingTests: XCTestCase {
    func testStatusWaitsForAddressCreationEvenWhenCreationFails() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE sync_outbox (
                  id TEXT, client_mutation_id TEXT, entity_type TEXT, entity_id TEXT,
                  operation TEXT, operation_version INTEGER, payload_json TEXT, status TEXT,
                  dependency_key TEXT, created_at TEXT, attempted_at TEXT, synced_at TEXT,
                  retry_after TEXT, retry_count INTEGER, error_message TEXT, dead_lettered_at TEXT
                )
                """)
            func insert(_ id: String, _ entity: String, _ operation: String, _ payload: String) throws {
                try db.execute(sql: """
                    INSERT INTO sync_outbox
                      (id, entity_type, entity_id, operation, operation_version, payload_json,
                       status, dependency_key, created_at, retry_count)
                    VALUES (?, 'test', ?, ?, 1, ?, 'pending', ?, ?, 0)
                    """, arguments: [id, entity, operation, payload, id, id])
            }
            try insert("1", "campaign:address", "create_manual_address", "{\"campaignId\":\"campaign\",\"addressId\":\"address\",\"buildingId\":\"building\"}")
            try insert("2", "address", "upsert_address_status", "{\"campaignId\":\"CAMPAIGN\",\"addressIds\":[\"ADDRESS\"]}")
            try insert("3", "other", "upsert_address_status", "{\"campaignId\":\"campaign\",\"addressIds\":[\"other\"]}")

            func pending() throws -> [String] {
                try OutboxRepository.fetchPending(in: db, now: "9999", limit: 20).map(\.id)
            }
            XCTAssertEqual(try pending(), ["1", "3"])
            try db.execute(sql: "UPDATE sync_outbox SET status = 'dead_letter' WHERE id = '1'")
            XCTAssertEqual(try pending(), ["3"])
            try db.execute(sql: "UPDATE sync_outbox SET synced_at = 'done' WHERE id = '1'")
            XCTAssertEqual(try pending(), ["2", "3"])
        }
    }

    func testContactMetadataAndRemovalWaitButOtherHomesContinue() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE sync_outbox (
                  id TEXT, client_mutation_id TEXT, entity_type TEXT, entity_id TEXT,
                  operation TEXT, operation_version INTEGER, payload_json TEXT, status TEXT,
                  dependency_key TEXT, created_at TEXT, attempted_at TEXT, synced_at TEXT,
                  retry_after TEXT, retry_count INTEGER, error_message TEXT, dead_lettered_at TEXT
                )
                """)
            func insert(_ id: String, _ operation: String, _ payload: String) throws {
                try db.execute(sql: """
                    INSERT INTO sync_outbox
                      (id, entity_type, entity_id, operation, operation_version, payload_json,
                       status, dependency_key, created_at, retry_count)
                    VALUES (?, 'test', ?, ?, 1, ?, 'pending', ?, ?, 0)
                    """, arguments: [id, id, operation, payload, id, id])
            }
            let target = "{\"campaignId\":\"camp\",\"addressId\":\"addr\",\"buildingId\":\"building\"}"
            try insert("01", "create_manual_address", target)
            for (offset, operation) in ["upsert_contact", "upsert_address_capture_metadata", "unlink_address_from_building", "delete_address", "move_address", "delete_building"].enumerated() {
                try insert("1\(offset)", operation, target)
            }
            try insert("20", "upsert_contact", "{\"addressId\":\"other\"}")
            try insert("21", "upsert_address_status", "{\"campaignId\":\"other-campaign\",\"addressIds\":[\"addr\"]}")
            try insert("22", "upsert_address_status", "{\"campaignId\":\"camp\",\"addressIds\":[\"existing\",\"addr\"]}")
            try insert("23", "unrelated", "malformed")
            XCTAssertEqual(try OutboxRepository.fetchPending(in: db, now: "9999", limit: 50).map(\.id), ["01", "20", "21", "23"])
            try db.execute(sql: "UPDATE sync_outbox SET status = 'conflict' WHERE id = '01'")
            XCTAssertEqual(try OutboxRepository.fetchPending(in: db, now: "9999", limit: 50).map(\.id), ["20", "21", "23"])
            try db.execute(sql: "UPDATE sync_outbox SET synced_at = 'done' WHERE id = '01'")
            XCTAssertEqual(try OutboxRepository.fetchPending(in: db, now: "9999", limit: 50).count, 10)
        }
    }
}
