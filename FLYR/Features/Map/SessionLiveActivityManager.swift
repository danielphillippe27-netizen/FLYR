import Foundation

#if canImport(ActivityKit)
import ActivityKit

@MainActor
final class SessionLiveActivityManager {
    static let shared = SessionLiveActivityManager()

    /// Minimum interval between updates when state is unchanged (keeps lock screen timer in sync).
    private static let periodicRefreshInterval: TimeInterval = 30

    private var currentActivity: Activity<SessionLiveActivityAttributes>?
    private var lastState: SessionLiveActivityAttributes.ContentState?
    private var lastUpdateTime: Date?

    private init() {}

    func start(sessionID: String, state: SessionLiveActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = activity(for: sessionID) {
            currentActivity = existing
            await update(sessionID: sessionID, state: state)
            return
        }

        await end()

        let attributes = SessionLiveActivityAttributes(sessionID: sessionID)
        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try Activity.request(attributes: attributes, content: content)
            lastState = state
            lastUpdateTime = Date()
        } catch {
            print("⚠️ [SessionLiveActivityManager] Failed to start Live Activity: \(error)")
        }
    }

    func update(sessionID: String, state: SessionLiveActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let now = Date()
        let stateChanged = lastState != state
        let shouldPeriodicRefresh = lastUpdateTime.map { now.timeIntervalSince($0) >= Self.periodicRefreshInterval } ?? true
        guard stateChanged || shouldPeriodicRefresh else { return }

        if currentActivity?.attributes.sessionID != sessionID {
            currentActivity = activity(for: sessionID)
        }

        guard let activity = currentActivity else {
            await start(sessionID: sessionID, state: state)
            return
        }

        await activity.update(ActivityContent(state: state, staleDate: nil))
        lastState = state
        lastUpdateTime = now
    }

    func end() async {
        let activitiesToEnd = Activity<SessionLiveActivityAttributes>.activities
        currentActivity = nil
        lastState = nil

        for activity in activitiesToEnd {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func activity(for sessionID: String) -> Activity<SessionLiveActivityAttributes>? {
        Activity<SessionLiveActivityAttributes>.activities.first { $0.attributes.sessionID == sessionID }
            ?? Activity<SessionLiveActivityAttributes>.activities.first
    }
}
#else
@MainActor
final class SessionLiveActivityManager {
    static let shared = SessionLiveActivityManager()

    private init() {}

    func start(sessionID: String, state: SessionLiveActivityAttributes.ContentState) async {}
    func update(sessionID: String, state: SessionLiveActivityAttributes.ContentState) async {}
    func end() async {}
}
#endif
