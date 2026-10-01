import XCTest
@testable import WolfGrid

@MainActor
final class WolfyEconomyStoreNotificationTests: XCTestCase {
    func testRestoringCachedSnapshotDoesNotNotifyWardrobeObservers() throws {
        let user = UUID()
        let workspace = UUID()
        let key = "wolfy.snapshot.\(workspace).\(user)"
        let snapshot = WolfySnapshot(
            rewards: nil,
            profile: WolfyWallet(xp: 0, coins: 0, happiness: 0, work_start: 9, work_end: 17, dnd: false),
            owned: [],
            equipped: [:],
            achievements: [],
            catalog: []
        )
        UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        var notifications = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .wolfyWardrobeDidChange,
            object: nil,
            queue: nil
        ) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let store = WolfyEconomyStore(user: user, workspace: workspace)
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(notifications, 0)

        store.snapshot = snapshot
        XCTAssertEqual(notifications, 1)
    }
}
