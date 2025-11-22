import Foundation
import SwiftUI

/// CRM integration provider types
enum IntegrationProvider: String, Codable, CaseIterable, Identifiable {
    case fub = "fub"
    case kvcore = "kvcore"
    case hubspot = "hubspot"
    case monday = "monday"
    case zapier = "zapier"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .fub: return "Follow Up Boss"
        case .kvcore: return "KVCore"
        case .hubspot: return "HubSpot"
        case .monday: return "Monday.com"
        case .zapier: return "Zapier / Webhooks"
        }
    }
    
    var icon: String {
        switch self {
        case .fub: return "person.2.fill"
        case .kvcore: return "key.fill"
        case .hubspot: return "chart.bar.fill"
        case .monday: return "calendar"
        case .zapier: return "link"
        }
    }
    
    var logoName: String {
        switch self {
        case .fub: return "fub_logo"
        case .kvcore: return "kvcore_logo"
        case .hubspot: return "hubspot_logo"
        case .monday: return "monday_logo"
        case .zapier: return "zapier_logo"
        }
    }
    
    var description: String {
        switch self {
        case .fub: return "Real estate CRM and lead management"
        case .kvcore: return "Real estate marketing platform"
        case .hubspot: return "Marketing, sales, and service platform"
        case .monday: return "Work management and collaboration"
        case .zapier: return "Automate workflows with webhooks"
        }
    }
    
    var connectionType: ConnectionType {
        switch self {
        case .fub, .kvcore:
            return .apiKey
        case .hubspot, .monday:
            return .oauth
        case .zapier:
            return .webhook
        }
    }
    
    enum ConnectionType {
        case apiKey
        case oauth
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - UserIntegration Extensions

extension UserIntegration {
    /// Check if integration is connected (has required credentials)
    var isConnected: Bool {
        switch provider.connectionType {
        case .apiKey:
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
            case .apiKey:
                return "Connected"
            case .oauth:
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
}

