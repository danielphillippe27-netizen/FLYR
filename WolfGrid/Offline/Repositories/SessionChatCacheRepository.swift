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
    private let dbQueue = OfflineDatabase.shared.dbQueue
    private init() {}

    func upsertRooms(_ rooms: [SessionChatRoom]) async {
        let now = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for room in rooms {
                guard let payload = OfflineJSONCodec.encode(room) else { continue }
                try CachedSessionChatRoomRecord(
                    sessionId: room.sessionId.uuidString,
                    payloadJSON: payload,
                    updatedAt: now
                ).save(db)
            }
        }
    }

    func fetchRooms() async -> [SessionChatRoom] {
        (try? await dbQueue.read { db in
            try CachedSessionChatRoomRecord
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(SessionChatRoom.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func upsertMessages(_ messages: [SessionChatMessage]) async {
        let now = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for message in messages {
                guard let payload = OfflineJSONCodec.encode(message) else { continue }
                let existing = try CachedSessionChatMessageRecord
                    .filter(Column("client_message_id") == message.clientMessageId.uuidString)
                    .fetchOne(db)
                if let existing, existing.localId != message.id {
                    try CachedSessionChatMessageRecord.deleteOne(db, key: existing.localId)
                }
                try CachedSessionChatMessageRecord(
                    localId: message.id,
                    serverId: message.id.hasPrefix("local:") ? nil : message.id,
                    sessionId: message.sessionId.uuidString,
                    clientMessageId: message.clientMessageId.uuidString,
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

    func fetchMessages(sessionId: UUID) async -> [SessionChatMessage] {
        (try? await dbQueue.read { db in
            try CachedSessionChatMessageRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .order(Column("created_at"))
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(SessionChatMessage.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func fetchPending() async -> [SessionChatMessage] {
        (try? await dbQueue.read { db in
            try CachedSessionChatMessageRecord
                .filter(
                    Column("delivery_state") == SessionChatDeliveryState.pending.rawValue
                        || Column("delivery_state") == SessionChatDeliveryState.retrying.rawValue
                )
                .order(Column("created_at"))
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(SessionChatMessage.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func delete(clientMessageId: UUID) async {
        try? await dbQueue.write { db in
            _ = try CachedSessionChatMessageRecord
                .filter(Column("client_message_id") == clientMessageId.uuidString)
                .deleteAll(db)
        }
    }
}
