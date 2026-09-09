import Foundation

enum SessionChatMessageType: String, Codable, Sendable {
    case text
    case voice
}

enum SessionChatDeliveryState: String, Codable, Sendable {
    case pending
    case retrying
    case failed
    case delivered
}

struct SessionChatSender: Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let avatarUrl: URL?
}

struct SessionChatMessage: Codable, Identifiable, Hashable, Sendable {
    var id: String
    let sessionId: UUID
    let campaignId: UUID
    let clientMessageId: UUID
    let type: SessionChatMessageType
    let text: String?
    var audioUrl: URL?
    let durationMs: Int?
    let createdAt: Date
    let sender: SessionChatSender
    var deliveryState: SessionChatDeliveryState?
    var localAudioPath: String?
    var errorMessage: String?

    var isDelivered: Bool { deliveryState == nil || deliveryState == .delivered }

    static func pendingText(
        sessionId: UUID,
        campaignId: UUID,
        clientMessageId: UUID,
        text: String,
        sender: SessionChatSender
    ) -> SessionChatMessage {
        SessionChatMessage(
            id: "local:\(clientMessageId.uuidString)",
            sessionId: sessionId,
            campaignId: campaignId,
            clientMessageId: clientMessageId,
            type: .text,
            text: text,
            audioUrl: nil,
            durationMs: nil,
            createdAt: Date(),
            sender: sender,
            deliveryState: .pending,
            localAudioPath: nil,
            errorMessage: nil
        )
    }
}

enum SessionChatMessageMerger {
    static func merge(_ lhs: [SessionChatMessage], _ rhs: [SessionChatMessage]) -> [SessionChatMessage] {
        var values = Dictionary(uniqueKeysWithValues: lhs.map { ($0.clientMessageId, $0) })
        for candidate in rhs {
            if let existing = values[candidate.clientMessageId],
               candidate.deliveryState != .delivered,
               existing.deliveryState == .delivered { continue }
            values[candidate.clientMessageId] = candidate
        }
        return values.values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.clientMessageId.uuidString < $1.clientMessageId.uuidString
        }
    }
}

struct SessionChatParticipant: Codable, Hashable, Sendable {
    let id: UUID
    let name: String
    let avatarUrl: URL?
    let role: String
    let isPresent: Bool
}

struct SessionChatRoom: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { sessionId }
    let sessionId: UUID
    let campaignId: UUID
    let workspaceId: UUID?
    let campaignName: String
    let startedAt: Date
    let endedAt: Date?
    let isActive: Bool
    let canSend: Bool
    let participants: [SessionChatParticipant]
    let participantCount: Int
    let latestMessage: SessionChatMessage?
    let latestMessageAt: Date
    var unreadCount: Int
}

struct SessionChatRoomsResponse: Decodable {
    let rooms: [SessionChatRoom]
    let nextCursor: String?
}

struct SessionChatMessagesResponse: Decodable {
    let messages: [SessionChatMessage]
    let nextCursor: String?
    let canSend: Bool
    let endedAt: Date?
    let unreadCount: Int
}

struct SessionChatSendResponse: Decodable {
    let message: SessionChatMessage
    let duplicate: Bool
}

struct SessionChatReadResponse: Decodable {
    let success: Bool
    let lastReadMessageId: String?
    let readAt: Date?
}

enum SessionChatAPIError: LocalizedError {
    case invalidMessage(String)
    case unauthorized
    case forbidden(String)
    case roomEnded(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .invalidMessage(message), let .forbidden(message), let .roomEnded(message), let .server(message):
            return message
        case .unauthorized:
            return "Please sign in again."
        }
    }
}
