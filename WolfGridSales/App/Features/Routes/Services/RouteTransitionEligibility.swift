import Foundation

/// Client-side mirror of server rules for assignment workflow buttons (UX only).
enum RouteAssignmentWorkflowAction: String, CaseIterable, Sendable {
    case accept
    case decline
    case start
    case complete
    case cancel
}

enum RouteTransitionEligibility: Sendable {
    static func eligibleActions(
        status: String,
        isAssignee: Bool,
        canManageRoutes: Bool
    ) -> Set<RouteAssignmentWorkflowAction> {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var actions = Set<RouteAssignmentWorkflowAction>()

        if isAssignee {
            switch s {
            case "assigned":
                actions.formUnion([.accept, .decline, .start])
            case "accepted":
                actions.insert(.start)
            case "in_progress":
                actions.insert(.complete)
            default:
                break
            }
        }

        if canManageRoutes, ["assigned", "accepted", "in_progress"].contains(s) {
            actions.insert(.cancel)
        }

        return actions
    }
}
