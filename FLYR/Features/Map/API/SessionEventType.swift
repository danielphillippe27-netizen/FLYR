import Foundation

/// Event types for `session_events` and `rpc_complete_building_in_session` / outcome RPCs.
///
/// - Lifecycle + undo use `session_started` … `completion_undone` via `SessionEventsAPI`.
/// - Visit outcomes written through `record_campaign_*_outcome` use DB categories:
///   `flyer_left`, `conversation`, `address_tap` (see `recordedVisitEventType(for:)`).
enum SessionEventType: String, Codable, CaseIterable {
    case sessionStarted = "session_started"
    case sessionPaused = "session_paused"
    case sessionResumed = "session_resumed"
    case sessionEnded = "session_ended"
    /// Legacy rows / replay only; new writes use `flyerLeft` or `conversation`.
    case completedManual = "completed_manual"
    case completedAuto = "completed_auto"
    case completionUndone = "completion_undone"

    case flyerLeft = "flyer_left"
    case conversation = "conversation"
    case addressTap = "address_tap"

    /// Maps visit status to `p_session_event_type` / `session_events.event_type` for outcome RPCs.
    /// `nil` when no session event should be logged for this status.
    static func recordedVisitEventType(for status: AddressStatus) -> SessionEventType? {
        switch status {
        case .none, .untouched:
            return nil
        case .delivered:
            return .flyerLeft
        case .noAnswer, .talked, .appointment, .doNotKnock, .futureSeller, .hotLead:
            return .conversation
        }
    }

    /// Event types that count as a completed target for session replay (`completedBuildings`).
    static var replayCompletionEventTypeRawValues: [String] {
        [
            SessionEventType.flyerLeft.rawValue,
            SessionEventType.conversation.rawValue,
            SessionEventType.completedManual.rawValue,
            SessionEventType.completedAuto.rawValue,
        ]
    }
}
