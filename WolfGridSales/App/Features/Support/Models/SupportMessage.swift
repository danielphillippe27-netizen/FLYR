import Foundation

/// A single message in a support thread. sender_type: "user" | "support".
struct SupportMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let threadId: UUID
    let senderType: String
    let senderUserId: UUID?
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case senderType = "sender_type"
        case senderUserId = "sender_user_id"
        case body
        case createdAt = "created_at"
    }

    var isFromUser: Bool { senderType == "user" }
}
