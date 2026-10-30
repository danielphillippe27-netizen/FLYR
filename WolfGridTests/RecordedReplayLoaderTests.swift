import XCTest
@testable import WolfGrid

@MainActor
final class RecordedReplayLoaderTests: XCTestCase {
    func testParsesRecordedStatusesAndUndo() throws {
        let address = UUID()
        let rows: [[String: Any]] = [
            ["event_type": "session_started", "created_at": "2026-01-01T12:00:00Z"],
            ["event_type": "conversation", "created_at": "2026-01-01T12:00:01.123Z", "address_id": address.uuidString, "metadata": ["address_status": "talked"]],
            ["event_type": "completion_undone", "created_at": "2026-01-01T12:00:02Z", "address_id": address.uuidString, "metadata": [:]]
        ]
        let visits = try RecordedReplayLoader.parseVisitRows(rows)
        XCTAssertEqual(visits.count, 2)
        XCTAssertEqual(visits.first?.addressID, address)
        XCTAssertEqual(visits.first?.status, "talked")
        XCTAssertEqual(visits.last?.status, AddressStatus.none.rawValue)
    }

    func testExpandsMultiAddressOutcomeWithoutLosingAnyHome() throws {
        let first = UUID()
        let second = UUID()
        let rows: [[String: Any]] = [[
            "event_type": "flyer_left", "created_at": "2026-01-01T12:00:01Z",
            "address_id": first.uuidString,
            "metadata": ["address_status": "delivered", "campaign_address_ids": [first.uuidString, second.uuidString]]
        ]]
        let visits = try RecordedReplayLoader.parseVisitRows(rows)
        XCTAssertEqual(visits.compactMap(\.addressID), [first, second])
        XCTAssertEqual(visits[0].timestamp, visits[1].timestamp)
    }

    func testRejectsInconsistentMultiAddressEvent() {
        let rows: [[String: Any]] = [[
            "event_type": "flyer_left", "created_at": "2026-01-01T12:00:01Z",
            "address_id": UUID().uuidString,
            "metadata": ["address_status": "delivered", "campaign_address_ids": [UUID().uuidString]]
        ]]
        XCTAssertThrowsError(try RecordedReplayLoader.parseVisitRows(rows))
    }

    func testRejectsConflictingOutcomesAtTheSameTimestamp() {
        let address = UUID().uuidString
        let rows: [[String: Any]] = [
            ["event_type": "conversation", "created_at": "2026-01-01T12:00:01Z", "address_id": address, "metadata": ["address_status": "talked"]],
            ["event_type": "completion_undone", "created_at": "2026-01-01T12:00:01Z", "address_id": address, "metadata": [:]]
        ]
        XCTAssertThrowsError(try RecordedReplayLoader.parseVisitRows(rows))
    }

    func testRejectsMissingStatusInsteadOfInventingAColor() {
        let rows: [[String: Any]] = [["event_type": "conversation", "created_at": "2026-01-01T12:00:01Z", "address_id": UUID().uuidString, "metadata": [:]]]
        XCTAssertThrowsError(try RecordedReplayLoader.parseVisitRows(rows))
    }
}
