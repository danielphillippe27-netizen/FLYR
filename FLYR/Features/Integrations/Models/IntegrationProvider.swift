import Foundation
import SwiftUI

func normalizedMondayBoardId(_ rawValue: String?) -> String? {
    guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty,
          trimmed != "0" else {
        return nil
    }
    return trimmed
}

func normalizedDisplayString(_ rawValue: String?) -> String? {
    guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

/// CRM integration provider types
enum IntegrationProvider: String, Codable, CaseIterable, Identifiable {
    case boldtrail = "boldtrail"
    case fub = "fub"
    case kvcore = "kvcore"
    case hubspot = "hubspot"
    case monday = "monday"
    case zapier = "zapier"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .boldtrail: return "BoldTrail / kvCORE"
        case .fub: return "Follow Up Boss"
        case .kvcore: return "KVCore"
        case .hubspot: return "HubSpot"
        case .monday: return "Monday.com"
        case .zapier: return "Zapier / Webhooks"
        }
    }
    
    var icon: String {
        switch self {
        case .boldtrail: return "person.crop.circle.badge.checkmark"
        case .fub: return "person.2.fill"
        case .kvcore: return "key.fill"
        case .hubspot: return "chart.bar.fill"
        case .monday: return "calendar"
        case .zapier: return "link"
        }
    }
    
    var logoName: String {
        switch self {
        case .boldtrail: return "kvcore_logo"
        case .fub: return "fub_logo"
        case .kvcore: return "kvcore_logo"
        case .hubspot: return "hubspot_logo"
        case .monday: return "monday_logo"
        case .zapier: return "zapier_logo"
        }
    }
    
    var description: String {
        switch self {
        case .boldtrail: return "Token-based BoldTrail / kvCORE lead sync"
        case .fub: return "Real estate CRM and lead management"
        case .kvcore: return "Real estate marketing platform"
        case .hubspot: return "Marketing, sales, and service platform"
        case .monday: return "Work management and collaboration"
        case .zapier: return "Automate workflows with webhooks"
        }
    }
    
    var connectionType: ConnectionType {
        switch self {
        case .boldtrail:
            return .token
        case .kvcore:
            return .apiKey
        case .fub, .hubspot, .monday:
            return .oauth
        case .zapier:
            return .webhook
        }
    }

    var syncLane: SyncLane {
        switch self {
        case .fub:
            return .native
        case .boldtrail, .kvcore, .hubspot, .monday:
            return .providerPipeline
        case .zapier:
            return .webhook
        }
    }
    
    enum ConnectionType {
        case token
        case apiKey
        case oauth
        case webhook
    }

    enum SyncLane {
        case native
        case providerPipeline
        case webhook
    }
}

/// User integration model matching database schema
struct UserIntegration: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let provider: IntegrationProvider
    let accessToken: String?
    let refreshToken: String?
    let apiKey: String?
    let webhookUrl: String?
    let expiresAt: Int?
    let accountId: String?
    let accountName: String?
    let selectedBoardId: String?
    let selectedBoardName: String?
    let providerConfig: MondayProviderConfig?
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case provider
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case apiKey = "api_key"
        case webhookUrl = "webhook_url"
        case expiresAt = "expires_at"
        case accountId = "account_id"
        case accountName = "account_name"
        case selectedBoardId = "selected_board_id"
        case selectedBoardName = "selected_board_name"
        case providerConfig = "provider_config"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        provider: IntegrationProvider,
        accessToken: String? = nil,
        refreshToken: String? = nil,
        apiKey: String? = nil,
        webhookUrl: String? = nil,
        expiresAt: Int? = nil,
        accountId: String? = nil,
        accountName: String? = nil,
        selectedBoardId: String? = nil,
        selectedBoardName: String? = nil,
        providerConfig: MondayProviderConfig? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.provider = provider
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.apiKey = apiKey
        self.webhookUrl = webhookUrl
        self.expiresAt = expiresAt
        self.accountId = normalizedDisplayString(accountId)
        self.accountName = normalizedDisplayString(accountName)
        self.selectedBoardId = normalizedMondayBoardId(selectedBoardId)
        self.selectedBoardName = normalizedMondayBoardId(selectedBoardId) == nil
            ? nil
            : normalizedDisplayString(selectedBoardName)
        self.providerConfig = providerConfig
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - UserIntegration Extensions

extension UserIntegration {
    /// Check if integration is connected (has required credentials)
    var isConnected: Bool {
        switch provider.connectionType {
        case .token, .apiKey:
            return apiKey != nil && !apiKey!.isEmpty
        case .oauth:
            return accessToken != nil && !accessToken!.isEmpty
        case .webhook:
            return webhookUrl != nil && !webhookUrl!.isEmpty
        }
    }
    
    /// Check if OAuth token is expired
    var isTokenExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Int(Date().timeIntervalSince1970) >= expiresAt
    }
    
    /// Get display text for connected status
    var connectionStatusText: String {
        if isConnected {
            switch provider.connectionType {
            case .token:
                return "Connected"
            case .apiKey:
                return "Connected"
            case .oauth:
                if provider == .monday && mondayNeedsBoardSelection {
                    return "Board Required"
                }
                if isTokenExpired {
                    return "Token Expired"
                }
                return "Connected"
            case .webhook:
                return "Webhook Active"
            }
        } else {
            return "Not Connected"
        }
    }

    var mondayNeedsBoardSelection: Bool {
        provider == .monday && isConnected && normalizedMondayBoardId(selectedBoardId) == nil
    }

    var mondayBoardLabel: String? {
        guard provider == .monday else { return nil }
        guard normalizedMondayBoardId(selectedBoardId) != nil else { return nil }
        return normalizedDisplayString(selectedBoardName)
    }

    func updatingMondayConnection(
        selectedBoardId: String? = nil,
        selectedBoardName: String? = nil,
        accountId: String? = nil,
        accountName: String? = nil,
        workspaceId: String? = nil,
        workspaceName: String? = nil,
        replaceBoardSelection: Bool = false
    ) -> UserIntegration {
        guard provider == .monday else { return self }

        let resolvedSelectedBoardId = replaceBoardSelection
            ? normalizedMondayBoardId(selectedBoardId)
            : normalizedMondayBoardId(selectedBoardId) ?? self.selectedBoardId
        let resolvedSelectedBoardName = replaceBoardSelection
            ? (resolvedSelectedBoardId == nil ? nil : normalizedDisplayString(selectedBoardName))
            : (normalizedMondayBoardId(selectedBoardId) != nil
                ? normalizedDisplayString(selectedBoardName) ?? self.selectedBoardName
                : self.selectedBoardName)
        let resolvedWorkspaceId = normalizedDisplayString(workspaceId) ?? providerConfig?.workspaceId
        let resolvedWorkspaceName = normalizedDisplayString(workspaceName) ?? providerConfig?.workspaceName
        let resolvedProviderConfig: MondayProviderConfig? = {
            guard resolvedWorkspaceId != nil || resolvedWorkspaceName != nil || providerConfig?.columnMapping != nil else {
                return providerConfig
            }
            return MondayProviderConfig(
                workspaceId: resolvedWorkspaceId,
                workspaceName: resolvedWorkspaceName,
                columnMapping: providerConfig?.columnMapping
            )
        }()

        return UserIntegration(
            id: id,
            userId: userId,
            provider: provider,
            accessToken: accessToken,
            refreshToken: refreshToken,
            apiKey: apiKey,
            webhookUrl: webhookUrl,
            expiresAt: expiresAt,
            accountId: normalizedDisplayString(accountId) ?? self.accountId,
            accountName: normalizedDisplayString(accountName) ?? self.accountName,
            selectedBoardId: resolvedSelectedBoardId,
            selectedBoardName: resolvedSelectedBoardName,
            providerConfig: resolvedProviderConfig,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

struct MondayProviderConfig: Codable, Equatable {
    let workspaceId: String?
    let workspaceName: String?
    let columnMapping: [String: MondayColumnMapping]?

    init(
        workspaceId: String? = nil,
        workspaceName: String? = nil,
        columnMapping: [String: MondayColumnMapping]? = nil
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.columnMapping = columnMapping
    }
}

struct MondayColumnMapping: Codable, Equatable {
    let columnId: String
    let columnTitle: String?
    let columnType: String?
    let strategy: String?

    init(
        columnId: String,
        columnTitle: String? = nil,
        columnType: String? = nil,
        strategy: String? = nil
    ) {
        self.columnId = columnId
        self.columnTitle = columnTitle
        self.columnType = columnType
        self.strategy = strategy
    }
}
