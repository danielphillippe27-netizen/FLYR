import XCTest
@testable import FLYR

final class AddressStatusPersistedRPCTests: XCTestCase {

    func testUntouchedMapsToNoneForRPC() {
        XCTAssertEqual(AddressStatus.untouched.persistedRPCValue, "none")
        XCTAssertEqual(AddressStatus.delivered.persistedRPCValue, "delivered")
    }

    func testRecordedVisitEventTypeMapsToCanonicalSessionEventTypes() {
        XCTAssertEqual(SessionEventType.recordedVisitEventType(for: .delivered), .flyerLeft)
        XCTAssertEqual(SessionEventType.recordedVisitEventType(for: .talked), .conversation)
        XCTAssertEqual(SessionEventType.recordedVisitEventType(for: .appointment), .conversation)
        XCTAssertNil(SessionEventType.recordedVisitEventType(for: .none))
        XCTAssertNil(SessionEventType.recordedVisitEventType(for: .untouched))
    }

    func testAddressStatusRowDecodesCampaignAddressId() throws {
        let json = """
        [{
          "id": "11111111-1111-1111-1111-111111111111",
          "campaign_address_id": "22222222-2222-2222-2222-222222222222",
          "campaign_id": "33333333-3333-3333-3333-333333333333",
          "status": "delivered",
          "visit_count": 1,
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-01T00:00:00Z"
        }]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([AddressStatusRow].self, from: json)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].addressId.uuidString.lowercased(), "22222222-2222-2222-2222-222222222222")
    }

    func testAddressStatusRowDecodesLegacyAddressIdKey() throws {
        let json = """
        [{
          "id": "11111111-1111-1111-1111-111111111111",
          "address_id": "22222222-2222-2222-2222-222222222222",
          "campaign_id": "33333333-3333-3333-3333-333333333333",
          "status": "no_answer",
          "visit_count": 0,
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-01T00:00:00Z"
        }]
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([AddressStatusRow].self, from: json)
        XCTAssertEqual(rows[0].addressId.uuidString.lowercased(), "22222222-2222-2222-2222-222222222222")
    }

    func testAddressStatusRowDecodesAttributionFields() throws {
        let json = """
        [{
          "campaign_address_id": "22222222-2222-2222-2222-222222222222",
          "campaign_id": "33333333-3333-3333-3333-333333333333",
          "status": "talked",
          "visit_count": 4,
          "last_action_by": "44444444-4444-4444-4444-444444444444",
          "last_session_id": "55555555-5555-5555-5555-555555555555",
          "last_home_event_id": "66666666-6666-6666-6666-666666666666",
          "updated_at": "2026-04-15T18:45:00Z"
        }]
        """.data(using: .utf8)!

        let rows = try JSONDecoder.supabaseDates.decode([AddressStatusRow].self, from: json)
        XCTAssertEqual(rows[0].status, .talked)
        XCTAssertEqual(rows[0].lastActionBy?.uuidString.lowercased(), "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(rows[0].lastSessionId?.uuidString.lowercased(), "55555555-5555-5555-5555-555555555555")
        XCTAssertEqual(rows[0].lastHomeEventId?.uuidString.lowercased(), "66666666-6666-6666-6666-666666666666")
    }
}
