import Foundation
import Combine

/// Lightweight workspace context (id, name, industry, role, reason). Populated from access state and invite accept. Persisted for scoped API calls.
@MainActor
final class WorkspaceContext: ObservableObject {
    static let shared = WorkspaceContext()

    private let workspaceIdKey = "flyr_workspace_id"
    private let workspaceNameKey = "flyr_workspace_name"
    private let workspaceIndustryKey = "flyr_workspace_industry"
    private let workspaceRoleKey = "flyr_workspace_role"
    private let dashboardModeKey = "flyr_dashboard_mode"
    private let salespersonIdKey = "flyr_salesperson_id"
    private let salespersonDashboardEnabledKey = "flyr_salesperson_dashboard_enabled"
    private let accessReasonKey = "flyr_access_reason"
    private var activeUserScope: String?

    @Published private(set) var workspaceId: UUID?
    @Published private(set) var workspaceName: String?
    @Published private(set) var industry: String?
    @Published private(set) var role: String?
    @Published private(set) var dashboardMode: String?
    @Published private(set) var salespersonId: UUID?
    @Published private(set) var canUseSalespersonDashboard = false
    @Published private(set) var accessReason: String?

    var isSalespersonDashboardEnabled: Bool {
        Config.isSalesBuild && canUseSalespersonDashboard && dashboardMode == "salesperson"
    }

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
        let parsedWorkspaceId: UUID?
        if let workspaceIdString = state.workspaceId,
           let id = UUID(uuidString: workspaceIdString) {
            parsedWorkspaceId = id
            workspaceId = parsedWorkspaceId
        } else {
            parsedWorkspaceId = nil
            workspaceId = nil
        }
        let locallyEnabledSalespersonDashboard = Config.isDialerEnabled(
            workspaceID: parsedWorkspaceId,
            userEmail: AuthManager.shared.user?.email
        )
        let salespersonDashboardEnabled = Config.isSalesBuild
            && (state.canUseSalespersonDashboard || locallyEnabledSalespersonDashboard || parsedWorkspaceId != nil)
        workspaceName = state.workspaceName
        industry = state.industry
        role = state.role
        dashboardMode = salespersonDashboardEnabled ? "salesperson" : state.dashboardMode
        salespersonId = state.salespersonId.flatMap(UUID.init(uuidString:))
        canUseSalespersonDashboard = salespersonDashboardEnabled
        accessReason = state.reason
        persist()
    }

    func update(
        workspaceId: UUID,
        name: String?,
        role: String?,
        industry: String? = nil,
        dashboardMode: String? = nil,
        salespersonId: UUID? = nil,
        canUseSalespersonDashboard: Bool = false
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = name
        self.industry = industry ?? self.industry
        self.role = role
        self.dashboardMode = Config.isSalesBuild ? "salesperson" : dashboardMode
        self.salespersonId = salespersonId
        self.canUseSalespersonDashboard = Config.isSalesBuild || canUseSalespersonDashboard
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
        industry = nil
        role = nil
        dashboardMode = nil
        salespersonId = nil
        canUseSalespersonDashboard = false
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
        defaults.set(industry, forKey: scopedKey(workspaceIndustryKey))
        defaults.set(role, forKey: scopedKey(workspaceRoleKey))
        defaults.set(dashboardMode, forKey: scopedKey(dashboardModeKey))
        if let salespersonId {
            defaults.set(salespersonId.uuidString, forKey: scopedKey(salespersonIdKey))
        } else {
            defaults.removeObject(forKey: scopedKey(salespersonIdKey))
        }
        defaults.set(canUseSalespersonDashboard, forKey: scopedKey(salespersonDashboardEnabledKey))
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
        industry = defaults.string(forKey: scopedKey(workspaceIndustryKey))
        role = defaults.string(forKey: scopedKey(workspaceRoleKey))
        dashboardMode = defaults.string(forKey: scopedKey(dashboardModeKey))
        if let s = defaults.string(forKey: scopedKey(salespersonIdKey)), let id = UUID(uuidString: s) {
            salespersonId = id
        } else {
            salespersonId = nil
        }
        canUseSalespersonDashboard = Config.isSalesBuild
            ? workspaceId != nil
            : defaults.bool(forKey: scopedKey(salespersonDashboardEnabledKey)) && dashboardMode == "salesperson"
        accessReason = defaults.string(forKey: scopedKey(accessReasonKey))
    }

    private func migrateLegacyStorageIfNeeded() {
        guard activeUserScope != nil else { return }
        let defaults = UserDefaults.standard
        let hasScopedValues = defaults.object(forKey: scopedKey(workspaceIdKey)) != nil
            || defaults.object(forKey: scopedKey(workspaceNameKey)) != nil
            || defaults.object(forKey: scopedKey(workspaceIndustryKey)) != nil
            || defaults.object(forKey: scopedKey(workspaceRoleKey)) != nil
            || defaults.object(forKey: scopedKey(dashboardModeKey)) != nil
            || defaults.object(forKey: scopedKey(salespersonIdKey)) != nil
            || defaults.object(forKey: scopedKey(salespersonDashboardEnabledKey)) != nil
            || defaults.object(forKey: scopedKey(accessReasonKey)) != nil
        guard !hasScopedValues else { return }

        if let workspaceId = defaults.string(forKey: workspaceIdKey) {
            defaults.set(workspaceId, forKey: scopedKey(workspaceIdKey))
        }
        if let workspaceName = defaults.string(forKey: workspaceNameKey) {
            defaults.set(workspaceName, forKey: scopedKey(workspaceNameKey))
        }
        if let industry = defaults.string(forKey: workspaceIndustryKey) {
            defaults.set(industry, forKey: scopedKey(workspaceIndustryKey))
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
        defaults.removeObject(forKey: scopedKey(workspaceIndustryKey))
        defaults.removeObject(forKey: scopedKey(workspaceRoleKey))
        defaults.removeObject(forKey: scopedKey(dashboardModeKey))
        defaults.removeObject(forKey: scopedKey(salespersonIdKey))
        defaults.removeObject(forKey: scopedKey(salespersonDashboardEnabledKey))
        defaults.removeObject(forKey: scopedKey(accessReasonKey))
    }

    private func removeLegacyStoredValues() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: workspaceIdKey)
        defaults.removeObject(forKey: workspaceNameKey)
        defaults.removeObject(forKey: workspaceIndustryKey)
        defaults.removeObject(forKey: workspaceRoleKey)
        defaults.removeObject(forKey: dashboardModeKey)
        defaults.removeObject(forKey: salespersonIdKey)
        defaults.removeObject(forKey: salespersonDashboardEnabledKey)
        defaults.removeObject(forKey: accessReasonKey)
    }

    private func scopedKey(_ base: String) -> String {
        guard let activeUserScope, !activeUserScope.isEmpty else {
            return base
        }
        return "\(base):\(activeUserScope)"
    }
}
