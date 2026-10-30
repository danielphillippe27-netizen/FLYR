import XCTest
import GRDB
@testable import WolfGrid

final class RecordedReplayOutboxTests: XCTestCase {
    func testPendingLifecycleEventsDoNotBlockReplay() throws {
        let queue = try DatabaseQueue()
        let session = UUID()
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE sync_outbox (operation TEXT, payload_json TEXT, synced_at TEXT)")
            for event in ["session_started", "session_paused", "session_resumed", "session_ended"] {
                let payload = "{\"sessionId\":\"\(session.uuidString)\",\"eventType\":\"\(event)\"}"
                try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, NULL)", arguments: ["create_session_event", payload])
            }
            XCTAssertFalse(try OutboxRepository.hasUnsyncedReplayEvents(in: db, sessionId: session))
            let outcome = "{\"sessionId\":\"\(session.uuidString)\",\"eventType\":\"completion_undone\"}"
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, NULL)", arguments: ["create_session_event", outcome])
            XCTAssertTrue(try OutboxRepository.hasUnsyncedReplayEvents(in: db, sessionId: session))
        }
    }

    func testBlocksOnlyUnsyncedOutcomesForSelectedSession() throws {
        let queue = try DatabaseQueue()
        let session = UUID()
        let other = UUID()
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE sync_outbox (operation TEXT, payload_json TEXT, synced_at TEXT)")
            let selected = "{\"sessionId\":\"\(session.uuidString)\"}"
            let otherPayload = "{\"sessionId\":\"\(other.uuidString)\"}"
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, ?)", arguments: ["upsert_address_status", selected, "2026-01-01"])
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, NULL)", arguments: ["upsert_address_status", otherPayload])
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, NULL)", arguments: ["unrelated", selected])
            XCTAssertFalse(try OutboxRepository.hasUnsyncedReplayEvents(in: db, sessionId: session))
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, NULL)", arguments: ["create_session_event", "malformed"])
            XCTAssertTrue(try OutboxRepository.hasUnsyncedReplayEvents(in: db, sessionId: session))
            try db.execute(sql: "DELETE FROM sync_outbox WHERE payload_json = ?", arguments: ["malformed"])
            try db.execute(sql: "INSERT INTO sync_outbox VALUES (?, ?, NULL)", arguments: ["create_session_event", selected])
            XCTAssertTrue(try OutboxRepository.hasUnsyncedReplayEvents(in: db, sessionId: session))
        }
    }
}
