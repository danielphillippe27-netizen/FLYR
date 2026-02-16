import Foundation

// MARK: - CRM Connection (matches crm_connections table)

struct CRMConnection: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let provider: String
    let status: String
    let connectedAt: Date?
    let lastSyncAt: Date?
    let updatedAt: Date?
    let metadata: CRMConnectionMetadata?
    let errorReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case provider
        case status
        case connectedAt = "connected_at"
        case lastSyncAt = "last_sync_at"
        case updatedAt = "updated_at"
        case metadata
        case errorReason = "error_reason"
    }

    var isConnected: Bool { status == "connected" }
}

struct CRMConnectionMetadata: Codable, Equatable {
    let name: String?
    let company: String?
}

// MARK: - FUB Connect API (body: api_key only; backend uses JWT for user_id)

struct FUBConnectRequest: Encodable {
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }
}

struct FUBConnectResponse: Decodable {
    let connected: Bool
    let account: FUBAccount?
    let error: String?

    struct FUBAccount: Decodable {
        let name: String?
        let company: String?
    }
}

// MARK: - Push Lead (POST /api/integrations/fub/push-lead)

struct FUBPushLeadRequest: Encodable {
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let address: String?
    let city: String?
    let state: String?
    let zip: String?
    let message: String?
    let source: String?
    let sourceUrl: String?
    let campaignId: String?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, email, phone, address, city, state, zip
        case message, source, sourceUrl, campaignId, metadata
    }
}

struct FUBPushLeadResponse: Decodable {
    let success: Bool
    let message: String?
    let fubEventId: String?
    let error: String?
}

// MARK: - Sync CRM (POST /api/leads/sync-crm)

struct FUBSyncCRMResponse: Decodable {
    let success: Bool
    let message: String?
    let synced: Int?
    let error: String?
}

// MARK: - Status (GET /api/integrations/fub/status)

struct FUBStatusResponse: Decodable {
    let connected: Bool
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let lastSyncAt: String?
    let lastError: String?
    let error: String?
}

// MARK: - Test (POST /api/integrations/fub/test, test-push)

struct FUBTestResponse: Decodable {
    let success: Bool
    let message: String?
    let error: String?
}
