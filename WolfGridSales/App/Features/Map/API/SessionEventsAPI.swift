import Foundation
import Supabase

/// API for logging session_events (building completions and lifecycle events)
@MainActor
final class SessionEventsAPI {
    static let shared = SessionEventsAPI()
    private let client = SupabaseManager.shared.client

    private init() {}

    /// Log a building completion or undo (uses RPC for atomic session + building_stats update)
    func logEvent(
        sessionId: UUID,
        buildingId: String,
        eventType: SessionEventType,
        lat: Double,
        lon: Double,
        metadata: [String: Any] = [:],
        clientMutationId: String? = nil
    ) async throws {
        var metadata = metadata
        if let clientMutationId {
            metadata["client_mutation_id"] = clientMutationId
        }
        let metaWrapped = metadata.mapValues { AnyCodable($0) }
        let params: [String: AnyCodable] = [
            "p_session_id": AnyCodable(sessionId),
            "p_building_id": AnyCodable(buildingId),
            "p_event_type": AnyCodable(eventType.rawValue),
            "p_lat": AnyCodable(lat),
            "p_lon": AnyCodable(lon),
            "p_metadata": AnyCodable(metaWrapped),
        ]
        _ = try await client
            .rpc("rpc_complete_building_in_session", params: params)
            .execute()
    }

    /// Log a lifecycle event (session_started, session_paused, session_resumed, session_ended) with no building
    func logLifecycleEvent(
        sessionId: UUID,
        eventType: SessionEventType,
        lat: Double? = nil,
        lon: Double? = nil,
        clientMutationId: String? = nil
    ) async throws {
        var metadata: [String: AnyCodable] = [:]
        if let clientMutationId {
            metadata["client_mutation_id"] = AnyCodable(clientMutationId)
        }
        // Use empty string for lifecycle events so PostgREST sends explicit TEXT (avoids uuid/text binding issues with null).
        let params: [String: AnyCodable] = [
            "p_session_id": AnyCodable(sessionId),
            "p_building_id": AnyCodable(""),
            "p_event_type": AnyCodable(eventType.rawValue),
            "p_lat": AnyCodable(lat as Any),
            "p_lon": AnyCodable(lon as Any),
            "p_metadata": AnyCodable(metadata),
        ]
        _ = try await client
            .rpc("rpc_complete_building_in_session", params: params)
            .execute()
    }
}
