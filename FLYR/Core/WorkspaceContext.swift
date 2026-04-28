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
    private var activeUserScope: String?

    @Published private(set) var workspaceId: UUID?
    @Published private(set) var workspaceName: String?
    @Published private(set) var role: String?
    @Published private(set) var accessReason: String?

    private init() {}

    func activate(userId: UUID?) {
        let normalizedUserId = userId?.uuidString.lowercased()
        guard activeUserScope != normalizedUserId else { return }
        activeUserScope = normalizedUserId
        guard normalizedUserId != nil else {
            clearInMemory()
            return
        }
        migrateLegacyStorageIfNeeded()
        loadFromStorage()
    }

    func update(from state: AccessStateResponse) {
        if let workspaceIdString = state.workspaceId,
           let parsedWorkspaceId = UUID(uuidString: workspaceIdString) {
            workspaceId = parsedWorkspaceId
        } else {
            workspaceId = nil
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
        clearInMemory()
        removeScopedStoredValues()
        removeLegacyStoredValues()
    }

    private func clearInMemory() {
        workspaceId = nil
        workspaceName = nil
        role = nil
        accessReason = nil
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let id = workspaceId {
            defaults.set(id.uuidString, forKey: scopedKey(workspaceIdKey))
        } else {
            defaults.removeObject(forKey: scopedKey(workspaceIdKey))
        }
        defaults.set(workspaceName, forKey: scopedKey(workspaceNameKey))
        defaults.set(role, forKey: scopedKey(workspaceRoleKey))
        defaults.set(accessReason, forKey: scopedKey(accessReasonKey))
        removeLegacyStoredValues()
    }

    private func loadFromStorage() {
        let defaults = UserDefaults.standard
        if let s = defaults.string(forKey: scopedKey(workspaceIdKey)), let id = UUID(uuidString: s) {
            workspaceId = id
        } else {
            workspaceId = nil
        }
        workspaceName = defaults.string(forKey: scopedKey(workspaceNameKey))
        role = defaults.string(forKey: scopedKey(workspaceRoleKey))
        accessReason = defaults.string(forKey: scopedKey(accessReasonKey))
    }

    private func migrateLegacyStorageIfNeeded() {
        guard activeUserScope != nil else { return }
        let defaults = UserDefaults.standard
        let hasScopedValues = defaults.object(forKey: scopedKey(workspaceIdKey)) != nil
            || defaults.object(forKey: scopedKey(workspaceNameKey)) != nil
            || defaults.object(forKey: scopedKey(workspaceRoleKey)) != nil
            || defaults.object(forKey: scopedKey(accessReasonKey)) != nil
        guard !hasScopedValues else { return }

        if let workspaceId = defaults.string(forKey: workspaceIdKey) {
            defaults.set(workspaceId, forKey: scopedKey(workspaceIdKey))
        }
        if let workspaceName = defaults.string(forKey: workspaceNameKey) {
            defaults.set(workspaceName, forKey: scopedKey(workspaceNameKey))
        }
        if let role = defaults.string(forKey: workspaceRoleKey) {
            defaults.set(role, forKey: scopedKey(workspaceRoleKey))
        }
        if let accessReason = defaults.string(forKey: accessReasonKey) {
            defaults.set(accessReason, forKey: scopedKey(accessReasonKey))
        }
    }

    private func removeScopedStoredValues() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: scopedKey(workspaceIdKey))
        defaults.removeObject(forKey: scopedKey(workspaceNameKey))
        defaults.removeObject(forKey: scopedKey(workspaceRoleKey))
        defaults.removeObject(forKey: scopedKey(accessReasonKey))
    }

    private func removeLegacyStoredValues() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: workspaceIdKey)
        defaults.removeObject(forKey: workspaceNameKey)
        defaults.removeObject(forKey: workspaceRoleKey)
        defaults.removeObject(forKey: accessReasonKey)
    }

    private func scopedKey(_ base: String) -> String {
        guard let activeUserScope, !activeUserScope.isEmpty else {
            return base
        }
        return "\(base):\(activeUserScope)"
    }
}
