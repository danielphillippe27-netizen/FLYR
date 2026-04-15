import XCTest
@testable import FLYR

final class MondayBoardSelectionTests: XCTestCase {

    func testMondayStatusTreatsZeroBoardIdAsMissing() throws {
        let data = """
        {
          "connected": true,
          "selectedBoardId": 0,
          "selectedBoardName": "CRM Board"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MondayStatusResponse.self, from: data)

        XCTAssertTrue(decoded.resolvedIsConnected == true)
        XCTAssertNil(decoded.selectedBoardId)
        XCTAssertNil(decoded.selectedBoardName)
    }

    func testMondayBoardSelectionResponseDropsZeroBoardId() throws {
        let data = """
        {
          "success": true,
          "selectedBoardId": "0",
          "selectedBoardName": "CRM Board"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MondayBoardSelectionResponse.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.selectedBoardId)
        XCTAssertNil(decoded.selectedBoardName)
    }

    func testMondayIntegrationRequiresBoardWhenStoredIdIsZero() {
        let integration = UserIntegration(
            userId: UUID(),
            provider: .monday,
            accessToken: "token",
            selectedBoardId: "0",
            selectedBoardName: "CRM Board"
        )

        XCTAssertTrue(integration.isConnected)
        XCTAssertTrue(integration.mondayNeedsBoardSelection)
        XCTAssertNil(integration.mondayBoardLabel)
    }

    func testMondayBoardsResponseFiltersInvalidBoardIds() throws {
        let data = """
        {
          "boards": [
            { "id": "18406493698", "name": "CRM Board", "columns": [] },
            { "id": 0, "name": "Broken Board", "columns": [] }
          ],
          "selectedBoardId": "18406493698",
          "selectedBoardName": "CRM Board"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MondayBoardsResponse.self, from: data)

        XCTAssertEqual(
            decoded.boards.compactMap { board in
                let trimmed = board.id.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty || trimmed == "0" ? nil : trimmed
            },
            ["18406493698"]
        )
        XCTAssertEqual(decoded.selectedBoardId, "18406493698")
        XCTAssertEqual(decoded.selectedBoardName, "CRM Board")
    }
}
