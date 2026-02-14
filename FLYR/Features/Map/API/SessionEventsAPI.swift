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
        metadata: [String: Any] = [:]
    ) async throws {
        let metaWrapped = metadata.mapValues { AnyCodable($0) }
        let params: [String: AnyCodable] = [
            "p_session_id": AnyCodable(sessionId.uuidString),
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
        lon: Double? = nil
    ) async throws {
        let buildingId = ""
        let latVal = lat ?? 0.0
        let lonVal = lon ?? 0.0
        let params: [String: AnyCodable] = [
            "p_session_id": AnyCodable(sessionId.uuidString),
            "p_building_id": AnyCodable(buildingId),
            "p_event_type": AnyCodable(eventType.rawValue),
            "p_lat": AnyCodable(latVal),
            "p_lon": AnyCodable(lonVal),
            "p_metadata": AnyCodable([String: AnyCodable]()),
        ]
        _ = try await client
            .rpc("rpc_complete_building_in_session", params: params)
            .execute()
    }
}
