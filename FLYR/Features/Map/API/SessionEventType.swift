import Foundation

/// Event types for session_events table (session recording)
enum SessionEventType: String, Codable, CaseIterable {
    case sessionStarted = "session_started"
    case sessionPaused = "session_paused"
    case sessionResumed = "session_resumed"
    case sessionEnded = "session_ended"
    case completedManual = "completed_manual"
    case completedAuto = "completed_auto"
    case completionUndone = "completion_undone"
}
