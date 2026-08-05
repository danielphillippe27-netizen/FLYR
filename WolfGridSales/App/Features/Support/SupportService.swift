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
    func subscribeMessages(
        threadId: UUID,
        onMessage: @escaping @Sendable (SupportMessage) -> Void
    ) async throws -> RealtimeChannelV2 {
        let channel = client.channel("support-\(threadId.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "support_messages",
            filter: .eq("thread_id", value: threadId.uuidString)
        )

        Task { [weak self] in
            guard let self else { return }
            for await insert in inserts {
                if let msg = self.decodeMessage(from: insert.record) {
                    onMessage(msg)
                }
            }
        }

        try await channel.subscribeWithError()
        return channel
    }

    private func decodeMessage(from record: [String: AnyJSON]) -> SupportMessage? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        return try? decoder.decode(SupportMessage.self, from: data)
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
