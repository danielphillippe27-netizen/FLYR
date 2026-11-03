import XCTest
@testable import WolfGrid

@MainActor
final class FarmListLoadingTests: XCTestCase {
    private func farm(user: UUID) throws -> Farm {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "owner_id": user.uuidString, "name": "Cached Farm",
            "start_date": 0, "end_date": 100, "frequency": 1, "created_at": 0])
        return try JSONDecoder().decode(Farm.self, from: data)
    }

    func testCachedListSurvivesRemoteFailure() async throws {
        let user = UUID(), cached = try farm(user: UUID())
        let model = FarmViewModel(cachedLoader: { _, _ in [cached] },
            remoteLoader: { _ in throw URLError(.notConnectedToInternet) },
            countLoader: { $0 }, workspaceProvider: { nil })
        await model.loadFarms(userId: user)
        XCTAssertEqual(model.farms.map(\.id), [cached.id])
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testScopeSwitchDoesNotKeepAnotherUsersCachedFarms() async throws {
        let firstUser = UUID(), otherUser = UUID()
        let cached = try farm(user: firstUser)
        let model = FarmViewModel(cachedLoader: { user, _ in user == firstUser ? [cached] : [] },
            remoteLoader: { _ in throw URLError(.notConnectedToInternet) },
            countLoader: { $0 }, workspaceProvider: { nil })
        await model.loadFarms(userId: firstUser)
        XCTAssertEqual(model.farms.count, 1)
        await model.loadFarms(userId: otherUser)
        XCTAssertTrue(model.farms.isEmpty)
        XCTAssertNotNil(model.errorMessage)
    }

    func testFreshListReturnsBeforeCountRefreshCompletes() async throws {
        let user = UUID(), fresh = try farm(user: UUID())
        var finishCount: CheckedContinuation<Farm, Never>?
        let countStarted = expectation(description: "Count refresh starts separately")
        let model = FarmViewModel(cachedLoader: { _, _ in [] }, remoteLoader: { _ in [fresh] },
            countLoader: { farm in
                await withCheckedContinuation { continuation in
                    finishCount = continuation
                    countStarted.fulfill()
                }
            }, workspaceProvider: { nil })
        await model.loadFarms(userId: user)
        XCTAssertEqual(model.farms.map(\.id), [fresh.id])
        XCTAssertFalse(model.isLoading)
        await fulfillment(of: [countStarted], timeout: 2)
        finishCount?.resume(returning: fresh)
    }
}
