import XCTest
@testable import FLYR

final class RouteTransitionEligibilityTests: XCTestCase {
    func testAssigneeAssigned_canAcceptDeclineStart() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "assigned",
            isAssignee: true,
            canManageRoutes: false
        )
        XCTAssertEqual(actions, [.accept, .decline, .start])
    }

    func testAssigneeAccepted_canStart() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "accepted",
            isAssignee: true,
            canManageRoutes: false
        )
        XCTAssertEqual(actions, [.start])
    }

    func testAssigneeInProgress_canComplete() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "in_progress",
            isAssignee: true,
            canManageRoutes: false
        )
        XCTAssertEqual(actions, [.complete])
    }

    func testNonAssignee_cannotActUnlessManager() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "assigned",
            isAssignee: false,
            canManageRoutes: false
        )
        XCTAssertTrue(actions.isEmpty)
    }

    func testAdminCanCancelFromAssigned() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "assigned",
            isAssignee: false,
            canManageRoutes: true
        )
        XCTAssertEqual(actions, [.cancel])
    }

    func testAdminAssignee_combinesCancelWithAssigneeActions() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "in_progress",
            isAssignee: true,
            canManageRoutes: true
        )
        XCTAssertEqual(actions, [.complete, .cancel])
    }

    func testCompleted_noActions() {
        let actions = RouteTransitionEligibility.eligibleActions(
            status: "completed",
            isAssignee: true,
            canManageRoutes: true
        )
        XCTAssertTrue(actions.isEmpty)
    }
}
