import XCTest
@testable import WolfGrid

final class LiveSessionCodeContractTests: XCTestCase {
    func testJoinResponseDecodesSnakeCaseContract() throws {
        let response = try decode("""
        {
          "success": true,
          "workspace_id": "workspace-1",
          "campaign_id": "campaign-1",
          "campaign_title": "Downtown",
          "session_id": "session-1",
          "access_scope": "campaign",
          "redirect": "dashboard"
        }
        """)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.workspaceId, "workspace-1")
        XCTAssertEqual(response.campaignId, "campaign-1")
        XCTAssertEqual(response.campaignTitle, "Downtown")
        XCTAssertEqual(response.sessionId, "session-1")
        XCTAssertEqual(response.accessScope, "campaign")
        XCTAssertEqual(response.redirect, "dashboard")
    }

    func testJoinResponseDecodesCamelCaseAndDefaultsRedirect() throws {
        let response = try decode("""
        {
          "success": true,
          "workspaceId": "workspace-2",
          "campaignId": "campaign-2",
          "campaignTitle": "North End",
          "sessionId": "session-2",
          "accessScope": "campaign"
        }
        """)

        XCTAssertEqual(response.workspaceId, "workspace-2")
        XCTAssertEqual(response.campaignId, "campaign-2")
        XCTAssertEqual(response.sessionId, "session-2")
        XCTAssertEqual(response.redirect, "dashboard")
    }

    private func decode(_ json: String) throws -> LiveSessionCodeJoinResponse {
        try JSONDecoder().decode(LiveSessionCodeJoinResponse.self, from: Data(json.utf8))
    }
}
