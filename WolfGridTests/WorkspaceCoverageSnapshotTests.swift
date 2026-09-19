import XCTest
@testable import WolfGrid

final class WorkspaceCoverageSnapshotTests: XCTestCase {
    func testCoverageIsSeparateFromCampaignStatusAndUnitIdentity() throws {
        let door = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherUnit = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let json = """
        {"enabled":true,"canManage":false,"homes":[{"address_id":"\(door)","state":"visited_elsewhere","campaign_name":"North","rep_name":"Pat","visited_at":"2026-09-19T00:00:00Z"}]}
        """
        let snapshot = try JSONDecoder().decode(WorkspaceCoverageSnapshot.self, from: Data(json.utf8))
        XCTAssertTrue(snapshot.home(door)?.isLocked == true)
        XCTAssertNil(snapshot.home(otherUnit))
        XCTAssertFalse(snapshot.canManage)
        XCTAssertTrue(snapshot.home(door)?.message.contains("Pat in North") == true)
    }

    func testDisabledPolicyDoesNotExposeStaleHomeLock() throws {
        let door = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let json = """
        {"enabled":false,"canManage":true,"homes":[{"address_id":"\(door)","state":"visited_elsewhere"}]}
        """
        let snapshot = try JSONDecoder().decode(WorkspaceCoverageSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.home(door))
    }

    func testOverlapIsInformational() throws {
        let door = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let json = """
        {"enabled":true,"canManage":false,"homes":[{"address_id":"\(door)","state":"overlap","campaign_name":"North"}]}
        """
        let snapshot = try JSONDecoder().decode(WorkspaceCoverageSnapshot.self, from: Data(json.utf8))
        XCTAssertFalse(snapshot.home(door)?.isLocked == true)
        XCTAssertTrue(snapshot.home(door)?.message.contains("Coordinate") == true)
    }
}
