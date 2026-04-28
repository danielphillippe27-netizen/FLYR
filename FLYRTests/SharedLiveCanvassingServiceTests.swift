import XCTest
@testable import FLYR

final class SharedLiveCanvassingServiceTests: XCTestCase {

    func testFreshnessTransitionsFromLiveToStaleToExpired() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let live = SharedLiveCanvassingReducer.freshness(
            for: now.addingTimeInterval(-20),
            now: now
        )
        let stale = SharedLiveCanvassingReducer.freshness(
            for: now.addingTimeInterval(-75),
            now: now
        )
        let expired = SharedLiveCanvassingReducer.freshness(
            for: now.addingTimeInterval(-220),
            now: now
        )

        XCTAssertEqual(live, .live)
        XCTAssertEqual(stale, .stale)
        XCTAssertEqual(expired, .expired)
    }

    func testMergePresencePrefersLatestUpdate() {
        let userId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let campaignId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let older = CampaignPresenceRow(
            campaignId: campaignId,
            userId: userId,
            sessionId: nil,
            latitude: 43.1,
            longitude: -79.1,
            updatedAt: Date(timeIntervalSince1970: 100),
            status: .active
        )
        let newer = CampaignPresenceRow(
            campaignId: campaignId,
            userId: userId,
            sessionId: nil,
            latitude: 43.2,
            longitude: -79.2,
            updatedAt: Date(timeIntervalSince1970: 200),
            status: .paused
        )

        var merged = SharedLiveCanvassingReducer.mergePresence(older, into: [:])
        merged = SharedLiveCanvassingReducer.mergePresence(newer, into: merged)
        merged = SharedLiveCanvassingReducer.mergePresence(older, into: merged)

        XCTAssertEqual(merged[userId]?.latitude, 43.2)
        XCTAssertEqual(merged[userId]?.longitude, -79.2)
        XCTAssertEqual(merged[userId]?.status, .paused)
    }

    func testTeammateJoinAndLeaveUpdates() {
        let selfId = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let teammateId = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let campaignId = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let now = Date(timeIntervalSince1970: 500)

        let directory: [UUID: SharedCanvassingMember] = [
            teammateId: SharedCanvassingMember(
                userId: teammateId,
                role: "member",
                displayName: "Jamie Rep",
                email: nil,
                avatarURL: nil,
                createdAt: now
            )
        ]

        let joined = CampaignPresenceRow(
            campaignId: campaignId,
            userId: teammateId,
            sessionId: nil,
            latitude: 43.4,
            longitude: -79.4,
            updatedAt: now,
            status: .active
        )
        let left = CampaignPresenceRow(
            campaignId: campaignId,
            userId: teammateId,
            sessionId: nil,
            latitude: 43.4,
            longitude: -79.4,
            updatedAt: now.addingTimeInterval(10),
            status: .inactive
        )

        var presence = SharedLiveCanvassingReducer.mergePresence(joined, into: [:])
        var teammates = SharedLiveCanvassingReducer.teammates(
            from: presence,
            directory: directory,
            currentUserId: selfId,
            currentSessionId: nil,
            now: now
        )
        XCTAssertEqual(teammates.count, 1)
        XCTAssertEqual(teammates.first?.displayName, "Jamie Rep")

        presence = SharedLiveCanvassingReducer.mergePresence(left, into: presence)
        teammates = SharedLiveCanvassingReducer.teammates(
            from: presence,
            directory: directory,
            currentUserId: selfId,
            currentSessionId: nil,
            now: now.addingTimeInterval(10)
        )
        XCTAssertTrue(teammates.isEmpty)
    }

    func testTeammatesAreScopedToActiveSession() {
        let selfId = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        let teammateId = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        let otherTeammateId = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
        let campaignId = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
        let activeSessionId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let otherSessionId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let now = Date(timeIntervalSince1970: 500)

        let directory: [UUID: SharedCanvassingMember] = [
            teammateId: SharedCanvassingMember(
                userId: teammateId,
                role: "member",
                displayName: "Jamie Rep",
                email: nil,
                avatarURL: nil,
                createdAt: now
            ),
            otherTeammateId: SharedCanvassingMember(
                userId: otherTeammateId,
                role: "member",
                displayName: "Alex Rep",
                email: nil,
                avatarURL: nil,
                createdAt: now
            )
        ]

        let sameSession = CampaignPresenceRow(
            campaignId: campaignId,
            userId: teammateId,
            sessionId: activeSessionId,
            latitude: 43.4,
            longitude: -79.4,
            updatedAt: now,
            status: .active
        )
        let otherSession = CampaignPresenceRow(
            campaignId: campaignId,
            userId: otherTeammateId,
            sessionId: otherSessionId,
            latitude: 43.5,
            longitude: -79.5,
            updatedAt: now,
            status: .active
        )

        let presence = [
            teammateId: sameSession,
            otherTeammateId: otherSession
        ]

        let teammates = SharedLiveCanvassingReducer.teammates(
            from: presence,
            directory: directory,
            currentUserId: selfId,
            currentSessionId: activeSessionId,
            now: now
        )

        XCTAssertEqual(teammates.map(\.userId), [teammateId])
    }

    func testMergeHomeStatePrefersNewestUpdate() throws {
        let olderJSON = """
        {
          "campaign_address_id": "11111111-1111-1111-1111-111111111111",
          "campaign_id": "22222222-2222-2222-2222-222222222222",
          "status": "delivered",
          "updated_at": "2026-04-15T10:00:00Z"
        }
        """.data(using: .utf8)!

        let newerJSON = """
        {
          "campaign_address_id": "11111111-1111-1111-1111-111111111111",
          "campaign_id": "22222222-2222-2222-2222-222222222222",
          "status": "talked",
          "updated_at": "2026-04-15T10:05:00Z"
        }
        """.data(using: .utf8)!

        let older = try JSONDecoder.supabaseDates.decode(AddressStatusRow.self, from: olderJSON)
        let newer = try JSONDecoder.supabaseDates.decode(AddressStatusRow.self, from: newerJSON)

        var merged = SharedLiveCanvassingReducer.mergeHomeState(older, into: [:])
        merged = SharedLiveCanvassingReducer.mergeHomeState(newer, into: merged)
        merged = SharedLiveCanvassingReducer.mergeHomeState(older, into: merged)

        XCTAssertEqual(merged[older.addressId]?.status, .talked)
        XCTAssertEqual(merged[older.addressId]?.updatedAt, newer.updatedAt)
    }

    func testNonFatalJoinOutcomeContinuesSolo() {
        struct JoinFailure: LocalizedError {
            var errorDescription: String? { "membership check failed" }
        }

        let outcome = SharedLiveCanvassingReducer.nonFatalJoinOutcome(for: JoinFailure())
        XCTAssertEqual(outcome, .continueSolo(reason: "membership check failed"))
    }
}
