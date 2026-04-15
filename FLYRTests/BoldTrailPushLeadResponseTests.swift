import XCTest
@testable import FLYR

final class BoldTrailPushLeadResponseTests: XCTestCase {

    func testDecodesSnakeCaseNumericRemoteContactId() throws {
        let data = """
        {
          "success": true,
          "message": "Lead synced",
          "remote_contact_id": 12345,
          "action": "created"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BoldTrailPushLeadResponse.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.message, "Lead synced")
        XCTAssertEqual(decoded.remoteContactId, "12345")
        XCTAssertEqual(decoded.action, "created")
    }

    func testDecodesStringSuccessAndFallbackIdFields() throws {
        let data = """
        {
          "success": "true",
          "message": "Updated",
          "contact_id": "abc-123",
          "action": "updated"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BoldTrailPushLeadResponse.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.remoteContactId, "abc-123")
        XCTAssertEqual(decoded.action, "updated")
    }
}
