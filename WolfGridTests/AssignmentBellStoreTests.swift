import Foundation
import Testing
@testable import WolfGrid

@MainActor
struct AssignmentBellStoreTests {
    @Test func firstPendingAssignmentShowsBinaryBadge() {
        let defaults = makeDefaults()
        let scope = AssignmentBellScope(userID: UUID(), workspaceID: UUID())
        let store = AssignmentBellStore(defaults: defaults)

        store.activate(scope)
        store.recordPendingAssignments([UUID()], for: scope)

        #expect(store.hasUnreadAssignment)
        #expect(store.badgeCount == 1)
    }

    @Test func readStatePersistsAcrossStoreRecreation() {
        let defaults = makeDefaults()
        let scope = AssignmentBellScope(userID: UUID(), workspaceID: UUID())
        let assignmentID = UUID()

        let firstStore = AssignmentBellStore(defaults: defaults)
        firstStore.activate(scope)
        firstStore.recordPendingAssignments([assignmentID], for: scope)
        firstStore.markCurrentAssignmentsRead()

        let relaunchedStore = AssignmentBellStore(defaults: defaults)
        relaunchedStore.activate(scope)
        relaunchedStore.recordPendingAssignments([assignmentID], for: scope)

        #expect(!relaunchedStore.hasUnreadAssignment)
        #expect(relaunchedStore.badgeCount == 0)
    }

    @Test func laterAssignmentShowsOneAgain() {
        let defaults = makeDefaults()
        let scope = AssignmentBellScope(userID: UUID(), workspaceID: UUID())
        let firstAssignmentID = UUID()
        let store = AssignmentBellStore(defaults: defaults)

        store.activate(scope)
        store.recordPendingAssignments([firstAssignmentID], for: scope)
        store.markCurrentAssignmentsRead()
        store.recordPendingAssignments([firstAssignmentID, UUID()], for: scope)

        #expect(store.hasUnreadAssignment)
        #expect(store.badgeCount == 1)
    }

    @Test func persistedUnreadSurvivesWithoutAnotherSuccessfulRefresh() {
        let defaults = makeDefaults()
        let scope = AssignmentBellScope(userID: UUID(), workspaceID: UUID())

        let firstStore = AssignmentBellStore(defaults: defaults)
        firstStore.activate(scope)
        firstStore.recordPendingAssignments([UUID()], for: scope)

        let relaunchedStore = AssignmentBellStore(defaults: defaults)
        relaunchedStore.activate(scope)

        #expect(relaunchedStore.hasUnreadAssignment)
        #expect(relaunchedStore.badgeCount == 1)
    }

    @Test func staleRefreshDoesNotRenotifyAnAssignmentThatWasAlreadyViewed() {
        let defaults = makeDefaults()
        let scope = AssignmentBellScope(userID: UUID(), workspaceID: UUID())
        let earlierAssignmentID = UUID()
        let viewedAssignmentID = UUID()
        let store = AssignmentBellStore(defaults: defaults)

        store.activate(scope)
        store.recordPendingAssignments([earlierAssignmentID], for: scope)
        store.markCurrentAssignmentsRead()
        store.recordPendingAssignments([earlierAssignmentID, viewedAssignmentID], for: scope)
        store.markCurrentAssignmentsRead()

        // An older in-flight response arrives, followed by the current response again.
        store.recordPendingAssignments([earlierAssignmentID], for: scope)
        store.recordPendingAssignments([earlierAssignmentID, viewedAssignmentID], for: scope)

        #expect(!store.hasUnreadAssignment)
        #expect(store.badgeCount == 0)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AssignmentBellStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
