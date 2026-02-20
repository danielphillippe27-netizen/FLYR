import Foundation

/// One support thread per user.
struct SupportThread: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var status: String
    var lastMessageAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case status
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }
}
