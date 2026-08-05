import Foundation
import Supabase

@MainActor
final class SessionParticipantsService {
    static let shared = SessionParticipantsService()

    private let client = SupabaseManager.shared.client
    private let iso8601Formatter = ISO8601DateFormatter()

    private init() {}

    func upsertParticipant(
        sessionId: UUID,
        campaignId: UUID,
        userId: UUID,
        role: String
    ) async throws {
        let now = iso8601Formatter.string(from: Date())
        let payload: [String: AnyCodable] = [
            "session_id": AnyCodable(sessionId.uuidString),
            "campaign_id": AnyCodable(campaignId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "role": AnyCodable(role),
            "joined_at": AnyCodable(now),
            "left_at": AnyCodable(NSNull()),
            "last_seen_at": AnyCodable(now)
        ]

        _ = try await client
            .from("session_participants")
            .upsert(payload, onConflict: "session_id,user_id")
            .execute()
    }

    func upsertHostParticipant(
        sessionId: UUID,
        campaignId: UUID,
        userId: UUID
    ) async throws {
        try await upsertParticipant(
            sessionId: sessionId,
            campaignId: campaignId,
            userId: userId,
            role: "host"
        )
    }

    func markParticipantLeft(
        sessionId: UUID,
        userId: UUID
    ) async throws {
        let now = iso8601Formatter.string(from: Date())
        let payload: [String: AnyCodable] = [
            "left_at": AnyCodable(now),
            "last_seen_at": AnyCodable(now)
        ]

        _ = try await client
            .from("session_participants")
            .update(payload)
            .eq("session_id", value: sessionId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    func isMissingInfrastructure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("session_participants")
            && (message.contains("schema cache")
                || message.contains("does not exist")
                || message.contains("could not find the"))
    }
}
