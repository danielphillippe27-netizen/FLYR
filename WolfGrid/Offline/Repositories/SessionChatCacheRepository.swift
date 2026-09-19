import Foundation
import GRDB

private struct CachedSessionChatRoomRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_session_chat_rooms"
    let sessionId: String
    let payloadJSON: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }
}

private struct CachedSessionChatMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_session_chat_messages"
    let localId: String
    let serverId: String?
    let sessionId: String
    let clientMessageId: String
    let payloadJSON: String
    let deliveryState: String
    let localAudioPath: String?
    let errorMessage: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case serverId = "server_id"
        case sessionId = "session_id"
        case clientMessageId = "client_message_id"
        case payloadJSON = "payload_json"
        case deliveryState = "delivery_state"
        case localAudioPath = "local_audio_path"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

final class SessionChatCacheRepository {
    static let shared = SessionChatCacheRepository()
    private let dbQueue: DatabaseQueue
    init(dbQueue: DatabaseQueue = OfflineDatabase.shared.dbQueue) { self.dbQueue = dbQueue }

    func upsertRooms(_ rooms: [SessionChatRoom], userId: UUID) async {
        let now = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for room in rooms {
                guard let payload = OfflineJSONCodec.encode(room) else { continue }
                try CachedSessionChatRoomRecord(
                    sessionId: userId.uuidString + ":" + room.sessionId.uuidString,
                    payloadJSON: payload,
                    updatedAt: now
                ).save(db)
            }
        }
    }

    func fetchRooms(userId: UUID) async -> [SessionChatRoom] {
        (try? await dbQueue.read { db in
            try CachedSessionChatRoomRecord
                .filter(Column("session_id").like(userId.uuidString + ":%"))
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(SessionChatRoom.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func upsertMessages(_ messages: [SessionChatMessage], userId: UUID) async {
        let now = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for message in messages {
                guard let payload = OfflineJSONCodec.encode(message) else { continue }
                let existing = try CachedSessionChatMessageRecord
                    .filter(Column("client_message_id") == userId.uuidString + ":" + message.clientMessageId.uuidString)
                    .fetchOne(db)
                if let existing, existing.localId != userId.uuidString + ":" + message.id {
                    try CachedSessionChatMessageRecord.deleteOne(db, key: existing.localId)
                }
                try CachedSessionChatMessageRecord(
                    localId: userId.uuidString + ":" + message.id,
                    serverId: message.id.hasPrefix("local:") ? nil : userId.uuidString + ":" + message.id,
                    sessionId: userId.uuidString + ":" + message.sessionId.uuidString,
                    clientMessageId: userId.uuidString + ":" + message.clientMessageId.uuidString,
                    payloadJSON: payload,
                    deliveryState: (message.deliveryState ?? .delivered).rawValue,
                    localAudioPath: message.localAudioPath,
                    errorMessage: message.errorMessage,
                    createdAt: OfflineDateCodec.string(from: message.createdAt),
                    updatedAt: now
                ).save(db)
            }
        }
    }

    func fetchMessages(sessionId: UUID, userId: UUID) async -> [SessionChatMessage] {
        (try? await dbQueue.read { db in
            try CachedSessionChatMessageRecord
                .filter(Column("session_id") == userId.uuidString + ":" + sessionId.uuidString)
                .order(Column("created_at"))
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(SessionChatMessage.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func fetchPending(userId: UUID) async -> [SessionChatMessage] {
        (try? await dbQueue.read { db in
            try CachedSessionChatMessageRecord
                .filter(Column("session_id").like(userId.uuidString + ":%"))
                .filter(
                    Column("delivery_state") == SessionChatDeliveryState.pending.rawValue
                        || Column("delivery_state") == SessionChatDeliveryState.retrying.rawValue
                )
                .order(Column("created_at"))
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(SessionChatMessage.self, from: $0.payloadJSON) }
        }) ?? []
    }

    /// Preserve the original sender's drafts, but require an explicit retry after sign-out.
    func pausePending(userId: UUID) async {
        try? await dbQueue.write { db in
            let rows = try CachedSessionChatMessageRecord
                .filter(Column("session_id").like(userId.uuidString + ":%"))
                .filter(Column("delivery_state") == "pending" || Column("delivery_state") == "retrying")
                .fetchAll(db)
            for row in rows {
                guard var message = OfflineJSONCodec.decode(SessionChatMessage.self, from: row.payloadJSON) else { continue }
                message.deliveryState = .failed
                message.errorMessage = "Account changed. Sign in as the original sender to retry."
                guard let payload = OfflineJSONCodec.encode(message) else { continue }
                try db.execute(sql: "UPDATE cached_session_chat_messages SET delivery_state = 'failed', payload_json = ?, error_message = ? WHERE local_id = ?",
                    arguments: [payload, message.errorMessage, row.localId])
            }
        }
    }

    func delete(clientMessageId: UUID, userId: UUID) async {
        try? await dbQueue.write { db in
            _ = try CachedSessionChatMessageRecord
                .filter(Column("client_message_id") == userId.uuidString + ":" + clientMessageId.uuidString)
                .deleteAll(db)
        }
    }
}
