import Combine
import Foundation

struct AssignmentBellScope: Equatable, Sendable {
    let userID: UUID
    let workspaceID: UUID
}

private struct AssignmentBellSnapshot: Codable, Equatable {
    var hasUnreadAssignment: Bool
    var observedAssignmentIDs: [UUID]
}

/// Persists the Home bell as a binary unread indicator for each user/workspace.
/// A newly observed pending assignment turns the badge on; viewing a loaded inbox turns it off.
@MainActor
final class AssignmentBellStore: ObservableObject {
    static let shared = AssignmentBellStore()

    @Published private(set) var hasUnreadAssignment = false

    var badgeCount: Int { hasUnreadAssignment ? 1 : 0 }

    private let defaults: UserDefaults
    private var activeScope: AssignmentBellScope?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func activate(_ scope: AssignmentBellScope) {
        activeScope = scope
        hasUnreadAssignment = snapshot(for: scope)?.hasUnreadAssignment ?? false
    }

    func deactivate() {
        activeScope = nil
        hasUnreadAssignment = false
    }

    /// Records a successful server response. Existing unread state is retained, while every
    /// assignment ID that has never been observed for this scope raises the badge exactly once.
    func recordPendingAssignments(_ assignmentIDs: Set<UUID>, for scope: AssignmentBellScope) {
        let previous = snapshot(for: scope)
        let observedIDs = Set(previous?.observedAssignmentIDs ?? [])
        let containsNewAssignment = !assignmentIDs.subtracting(observedIDs).isEmpty
        let nextObservedIDs = observedIDs.union(assignmentIDs)

        let next = AssignmentBellSnapshot(
            hasUnreadAssignment: (previous?.hasUnreadAssignment ?? false) || containsNewAssignment,
            observedAssignmentIDs: nextObservedIDs.sorted { $0.uuidString < $1.uuidString }
        )
        persist(next, for: scope)

        guard activeScope == scope else { return }
        hasUnreadAssignment = next.hasUnreadAssignment
    }

    func markCurrentAssignmentsRead() {
        guard let activeScope else { return }
        markAssignmentsRead(for: activeScope)
    }

    func markAssignmentsRead(for scope: AssignmentBellScope) {
        var current = snapshot(for: scope) ?? AssignmentBellSnapshot(
            hasUnreadAssignment: false,
            observedAssignmentIDs: []
        )
        current.hasUnreadAssignment = false
        persist(current, for: scope)
        guard activeScope == scope else { return }
        hasUnreadAssignment = false
    }

    private func snapshot(for scope: AssignmentBellScope) -> AssignmentBellSnapshot? {
        guard let data = defaults.data(forKey: storageKey(for: scope)) else { return nil }
        return try? JSONDecoder().decode(AssignmentBellSnapshot.self, from: data)
    }

    private func persist(_ snapshot: AssignmentBellSnapshot, for scope: AssignmentBellScope) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey(for: scope))
    }

    private func storageKey(for scope: AssignmentBellScope) -> String {
        "assignment_bell_v2:\(scope.userID.uuidString.lowercased()):\(scope.workspaceID.uuidString.lowercased())"
    }
}
