import Foundation
import Combine

/// Lightweight workspace context (id, name, role, reason). Populated from access state and invite accept. Persisted for scoped API calls.
@MainActor
final class WorkspaceContext: ObservableObject {
    static let shared = WorkspaceContext()

    private let workspaceIdKey = "flyr_workspace_id"
    private let workspaceNameKey = "flyr_workspace_name"
    private let workspaceRoleKey = "flyr_workspace_role"
    private let accessReasonKey = "flyr_access_reason"

    @Published private(set) var workspaceId: UUID?
    @Published private(set) var workspaceName: String?
    @Published private(set) var role: String?
    @Published private(set) var accessReason: String?

    private init() {
        loadFromStorage()
    }

    func update(from state: AccessStateResponse) {
        if let workspaceIdString = state.workspaceId,
           let parsedWorkspaceId = UUID(uuidString: workspaceIdString) {
            workspaceId = parsedWorkspaceId
        }
        workspaceName = state.workspaceName
        role = state.role
        accessReason = state.reason
        persist()
    }

    func update(workspaceId: UUID, name: String?, role: String?) {
        self.workspaceId = workspaceId
        self.workspaceName = name
        self.role = role
        self.accessReason = nil
        persist()
    }

    func clear() {
        workspaceId = nil
        workspaceName = nil
        role = nil
        accessReason = nil
        UserDefaults.standard.removeObject(forKey: workspaceIdKey)
        UserDefaults.standard.removeObject(forKey: workspaceNameKey)
        UserDefaults.standard.removeObject(forKey: workspaceRoleKey)
        UserDefaults.standard.removeObject(forKey: accessReasonKey)
    }

    private func persist() {
        if let id = workspaceId {
            UserDefaults.standard.set(id.uuidString, forKey: workspaceIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: workspaceIdKey)
        }
        UserDefaults.standard.set(workspaceName, forKey: workspaceNameKey)
        UserDefaults.standard.set(role, forKey: workspaceRoleKey)
        UserDefaults.standard.set(accessReason, forKey: accessReasonKey)
    }

    private func loadFromStorage() {
        if let s = UserDefaults.standard.string(forKey: workspaceIdKey), let id = UUID(uuidString: s) {
            workspaceId = id
        } else {
            workspaceId = nil
        }
        workspaceName = UserDefaults.standard.string(forKey: workspaceNameKey)
        role = UserDefaults.standard.string(forKey: workspaceRoleKey)
        accessReason = UserDefaults.standard.string(forKey: accessReasonKey)
    }
}
