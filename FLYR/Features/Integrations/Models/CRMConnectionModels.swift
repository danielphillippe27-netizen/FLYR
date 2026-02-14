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
