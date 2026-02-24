import Foundation
import Supabase

/// Service for support chat: get/create thread, fetch/send messages, subscribe to realtime.
final class SupportService {
    static let shared = SupportService()

    private let client = SupabaseManager.shared.client

    private init() {}

    // MARK: - Thread

    /// Get existing support thread for user, or create one. Uses RPC so creation succeeds regardless of RLS.
    func getOrCreateThread(userId: UUID) async throws -> SupportThread {
        // PostgREST returns a single object for RPC that returns one row, not an array.
        let thread: SupportThread = try await client
            .rpc("get_or_create_support_thread")
            .execute()
            .value
        return thread
    }

    // MARK: - Messages

    func fetchMessages(threadId: UUID) async throws -> [SupportMessage] {
        let list: [SupportMessage] = try await client
            .from("support_messages")
            .select()
            .eq("thread_id", value: threadId)
            .order("created_at", ascending: true)
            .execute()
            .value
        return list
    }

    func sendMessage(threadId: UUID, body: String, senderUserId: UUID) async throws -> SupportMessage {
        let insert = SupportMessageInsert(
            threadId: threadId,
            senderType: "user",
            senderUserId: senderUserId,
            body: body
        )
        let created: SupportMessage = try await client
            .from("support_messages")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
        return created
    }

    // MARK: - Realtime

    /// Subscribe to new messages in this thread. Caller must retain and later unsubscribe the returned channel.
    func subscribeMessages(threadId: UUID, onMessage: @escaping (SupportMessage) -> Void) async throws -> RealtimeChannel {
        let channel = client.realtime.channel("support-\(threadId.uuidString)")
        await channel.on(
            "postgres_changes",
            filter: ChannelFilter(
                event: "INSERT",
                schema: "public",
                table: "support_messages",
                filter: "thread_id=eq.\(threadId.uuidString)"
            )
        ) { [weak self] payload in
            guard let self = self,
                  let dict = payload as? [String: Any],
                  let newDict = dict["new"] as? [String: Any] else { return }
            if let msg = self.decodeMessage(from: newDict) {
                onMessage(msg)
            }
        }
        await channel.subscribe()
        return channel
    }

    private func decodeMessage(from dict: [String: Any]) -> SupportMessage? {
        guard let idStr = dict["id"] as? String, let id = UUID(uuidString: idStr),
              let threadIdStr = dict["thread_id"] as? String, let threadId = UUID(uuidString: threadIdStr),
              let senderType = dict["sender_type"] as? String,
              let body = dict["body"] as? String,
              let createdAtStr = dict["created_at"] as? String,
              let createdAt = Self.parseDate(createdAtStr) else {
            return nil
        }
        let senderUserId: UUID? = (dict["sender_user_id"] as? String).flatMap(UUID.init)
        return SupportMessage(
            id: id,
            threadId: threadId,
            senderType: senderType,
            senderUserId: senderUserId,
            body: body,
            createdAt: createdAt
        )
    }
}

// MARK: - Insert DTOs

private struct SupportMessageInsert: Encodable {
    let threadId: UUID
    let senderType: String
    let senderUserId: UUID?
    let body: String
    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case senderType = "sender_type"
        case senderUserId = "sender_user_id"
        case body
    }
}

// MARK: - Date parsing

private extension SupportService {
    static func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter.flyrSupport.date(from: string)
            ?? ISO8601DateFormatter.flyrSupportNoFraction.date(from: string)
    }
}

private extension ISO8601DateFormatter {
    static let flyrSupport: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let flyrSupportNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
