import GRDB
import XCTest
@testable import WolfGrid

final class SessionChatTests: XCTestCase {
    func testDeliveredRealtimeMessageReplacesOptimisticMessageByClientId() {
        let clientId = UUID()
        let pending = message(id: "local:\(clientId)", clientId: clientId, state: .pending)
        let delivered = message(id: UUID().uuidString, clientId: clientId, state: .delivered)

        let merged = SessionChatMessageMerger.merge([pending], [delivered])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, delivered.id)
        XCTAssertEqual(merged.first?.deliveryState, .delivered)
    }

    func testLatePendingResponseCannotReplaceDeliveredRealtimeMessage() {
        let clientId = UUID()
        let delivered = message(id: UUID().uuidString, clientId: clientId, state: .delivered)
        let retrying = message(id: "local:\(clientId)", clientId: clientId, state: .retrying)

        XCTAssertEqual(SessionChatMessageMerger.merge([delivered], [retrying]), [delivered])
    }

    func testOfflineMigrationCreatesSessionChatTables() throws {
        let queue = try DatabaseQueue()
        try OfflineMigrations.migrator().migrate(queue)

        try queue.read { db in
            XCTAssertTrue(try db.tableExists("cached_session_chat_rooms"))
            XCTAssertTrue(try db.tableExists("cached_session_chat_messages"))
        }
    }

    func testCacheSeparatesAccountsEvenWhenTheyShareTheSameMessage() async throws {
        let queue = try DatabaseQueue()
        try OfflineMigrations.migrator().migrate(queue)
        let cache = SessionChatCacheRepository(dbQueue: queue)
        let owner = UUID(), other = UUID(), client = UUID()
        let pending = message(id: "local:\(client)", clientId: client, state: .pending)
        await cache.upsertMessages([pending], userId: owner)
        let hidden = await cache.fetchMessages(sessionId: pending.sessionId, userId: other)
        XCTAssertTrue(hidden.isEmpty)
        await cache.upsertMessages([pending], userId: other)
        await cache.delete(clientMessageId: client, userId: other)
        let retained = await cache.fetchPending(userId: owner)
        XCTAssertEqual(retained.count, 1)
    }

    func testSignOutPausesOnlyTheOriginatingAccountsQueue() async throws {
        let queue = try DatabaseQueue()
        try OfflineMigrations.migrator().migrate(queue)
        let cache = SessionChatCacheRepository(dbQueue: queue)
        let owner = UUID(), other = UUID(), client = UUID()
        let pending = message(id: "local:\(client)", clientId: client, state: .pending)
        await cache.upsertMessages([pending], userId: owner)
        await cache.upsertMessages([pending], userId: other)
        await cache.pausePending(userId: owner)
        let paused = await cache.fetchPending(userId: owner)
        let unaffected = await cache.fetchPending(userId: other)
        let visible = await cache.fetchMessages(sessionId: pending.sessionId, userId: owner)
        XCTAssertTrue(paused.isEmpty)
        XCTAssertEqual(unaffected.count, 1)
        XCTAssertEqual(visible.first?.deliveryState, .failed)
    }

    private func message(id: String, clientId: UUID, state: SessionChatDeliveryState) -> SessionChatMessage {
        SessionChatMessage(
            id: id,
            sessionId: UUID(),
            campaignId: UUID(),
            clientMessageId: clientId,
            type: .text,
            text: "hello",
            audioUrl: nil,
            durationMs: nil,
            createdAt: Date(),
            sender: SessionChatSender(id: UUID(), name: "Tester", avatarUrl: nil),
            deliveryState: state,
            localAudioPath: nil,
            errorMessage: nil
        )
    }
}
