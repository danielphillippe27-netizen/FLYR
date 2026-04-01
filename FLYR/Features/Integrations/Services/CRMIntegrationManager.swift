import Foundation
import Supabase

/// Manages CRM integration connections (connect, disconnect, fetch)
actor CRMIntegrationManager {
    static let shared = CRMIntegrationManager()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }
    
    private init() {}

    private func invokeEdgeFunction(
        name: String,
        body: [String: Any]
    ) async throws -> Data {
        let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String
        let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
        let url = URL(string: "\(supabaseURLString)/functions/v1/\(name)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let session = try await client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "CRMIntegrationManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
        }

        return data
    }

    private func invokeBackendRoute(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        errorMessage: @escaping (_ statusCode: Int, _ data: Data) -> String
    ) async throws -> Data {
        let session = try await client.auth.session
        let url = URL(string: "\(requestBaseURL)\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: errorMessage(httpResponse.statusCode, data)]
            )
        }

        return data
    }

    private func mondayDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func mondayErrorMessage(
        statusCode: Int,
        data: Data,
        fallback: String
    ) -> String {
        let payload = decodeAPIErrorPayload(from: data)
        let rawMessage = [payload?.error, payload?.message]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        return normalizeMondayErrorMessage(rawMessage, statusCode: statusCode, fallback: fallback)
    }

    private func normalizeMondayErrorMessage(
        _ rawMessage: String?,
        statusCode: Int? = nil,
        fallback: String
    ) -> String {
        let extractedMessage = extractMondayErrorMessage(from: rawMessage) ?? rawMessage
        let normalized = extractedMessage?.lowercased() ?? ""
        if normalized.contains("board_id\\\":0") || normalized.contains("\"board_id\":0") {
            return "Selected Monday board was not saved correctly. Re-select the board and try again."
        }
        if normalized.contains("board does not exist") || normalized.contains("invalidboardidexception") {
            return "Selected Monday board can't accept new items. Re-select a writable parent board in Monday.com and try again."
        }
        if normalized.contains("subitems") || normalized.contains("sub items") {
            return "Selected Monday board is a subitems board. Choose the parent board instead."
        }

        if normalized.contains("requested function was not found") || normalized.contains("\"code\":\"not_found\"") {
            return fallback
        }

        if let extractedMessage,
           !extractedMessage.isEmpty,
           !extractedMessage.hasPrefix("{"),
           !extractedMessage.contains("\"code\"") {
            return extractedMessage
        }

        if statusCode == 401 {
            return "Your Monday.com session expired. Reconnect Monday.com and try again."
        }

        return fallback
    }

    private func decodeAPIErrorPayload(from data: Data) -> APIErrorPayload? {
        if let decoded = try? mondayDecoder().decode(APIErrorPayload.self, from: data) {
            return decoded
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return APIErrorPayload(
            error: stringValue(from: object["error"]),
            message: stringValue(from: object["message"]),
            code: stringValue(from: object["code"])
        )
    }

    private func extractMondayErrorMessage(from rawMessage: String?) -> String? {
        guard let trimmed = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if let graphQLError = extractMondayGraphQLErrorMessage(from: trimmed) {
            return graphQLError
        }

        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return trimmed
        }

        guard let data = trimmed.data(using: .utf8),
              let payload = decodeAPIErrorPayload(from: data) else {
            return trimmed
        }

        return [payload.error, payload.message, payload.code]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? trimmed
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            return stringValue(from: dictionary["message"])
                ?? stringValue(from: dictionary["error"])
                ?? stringValue(from: dictionary["code"])
        default:
            return nil
        }
    }

    private func extractMondayGraphQLErrorMessage(from rawMessage: String) -> String? {
        let prefix = "Monday.com GraphQL error:"
        guard rawMessage.hasPrefix(prefix) else { return nil }

        let payloadText = rawMessage.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payloadText.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = array.first else {
            return nil
        }

        let message = stringValue(from: first["message"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = stringValue(from: (first["extensions"] as? [String: Any])?["code"])
        let normalizedMessage = message?.lowercased() ?? ""
        let normalizedCode = code?.lowercased() ?? ""

        if normalizedMessage.contains("board_id\":0") || normalizedMessage.contains("board id\":0") {
            return "Selected Monday board was not saved correctly. Re-select the board and try again."
        }

        if normalizedMessage.contains("board does not exist") || normalizedCode == "invalidboardidexception" {
            return "Selected Monday board can't accept new items. Re-select a writable parent board in Monday.com and try again."
        }

        return message
    }
    
    // MARK: - Fetch Integrations
    
    func fetchIntegrations(userId: UUID) async throws -> [UserIntegration] {
        let response: [UserIntegration] = try await client
            .from("user_integrations")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Connect Integrations
    
    func connectFUB(userId: UUID, apiKey: String) async throws {
        throw NSError(
            domain: "CRMIntegrationManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Use the secure Follow Up Boss connect flow from Integrations."]
        )
    }
    
    func connectKVCore(userId: UUID, apiKey: String) async throws {
        let integrationData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId),
            "provider": AnyCodable("kvcore"),
            "api_key": AnyCodable(apiKey),
            "updated_at": AnyCodable(Date())
        ]
        
        try await client
            .from("user_integrations")
            .upsert(integrationData, onConflict: "user_id,provider")
            .execute()
    }
    
    func connectZapier(userId: UUID, webhookURL: String) async throws {
        let integrationData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId),
            "provider": AnyCodable("zapier"),
            "webhook_url": AnyCodable(webhookURL),
            "updated_at": AnyCodable(Date())
        ]
        
        try await client
            .from("user_integrations")
            .upsert(integrationData, onConflict: "user_id,provider")
            .execute()
    }
    
    // MARK: - OAuth Flows
    
    /// Complete OAuth flow after receiving authorization code
    func completeOAuthFlow(
        provider: IntegrationProvider,
        code: String,
        userId: UUID
    ) async throws {
        guard provider == .monday else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid provider for OAuth code exchange"]
            )
        }
        
        let body: [String: Any] = [
            "provider": provider.rawValue,
            "code": code,
            "user_id": userId.uuidString
        ]

        _ = try await invokeEdgeFunction(name: "oauth_exchange", body: body)
    }

    func fetchMondayBoards() async throws -> MondayBoardsResponse {
        let data = try await invokeBackendRoute(
            path: "/api/integrations/monday/boards",
            method: "GET"
        ) { statusCode, data in
            self.mondayErrorMessage(
                statusCode: statusCode,
                data: data,
                fallback: "Unable to load Monday boards right now. Please try again."
            )
        }
        return try mondayDecoder().decode(MondayBoardsResponse.self, from: data)
    }

    func fetchMondayStatus() async throws -> MondayStatusResponse {
        let data = try await invokeBackendRoute(
            path: "/api/integrations/monday/status",
            method: "GET"
        ) { statusCode, data in
            self.mondayErrorMessage(
                statusCode: statusCode,
                data: data,
                fallback: "Unable to refresh Monday.com settings right now. Please try again."
            )
        }
        return try mondayDecoder().decode(MondayStatusResponse.self, from: data)
    }

    func selectMondayBoard(board: MondayBoardSummary) async throws -> MondayBoardSelectionResponse {
        guard let boardId = normalizedMondayBoardId(board.id) else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Select a valid Monday board before testing sync."]
            )
        }

        let data = try await invokeBackendRoute(
            path: "/api/integrations/monday/select-board",
            method: "POST",
            body: [
                "boardId": boardId,
                "board_id": boardId,
                "boardName": normalizedDisplayString(board.name) as Any,
                "board_name": normalizedDisplayString(board.name) as Any,
                "workspaceId": normalizedDisplayString(board.workspaceId) as Any,
                "workspace_id": normalizedDisplayString(board.workspaceId) as Any,
                "workspaceName": normalizedDisplayString(board.workspaceName) as Any,
                "workspace_name": normalizedDisplayString(board.workspaceName) as Any
            ].compactMapValues { $0 }
        ) { statusCode, data in
            self.mondayErrorMessage(
                statusCode: statusCode,
                data: data,
                fallback: "Unable to save the Monday board right now. Please try again."
            )
        }
        return try mondayDecoder().decode(MondayBoardSelectionResponse.self, from: data)
    }

    func sendMondayTestLead(userId: UUID) async throws -> String {
        let integrations = try await fetchIntegrations(userId: userId)
        guard let mondayIntegration = integrations.first(where: { $0.provider == .monday && $0.isConnected }) else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Monday.com is not connected."]
            )
        }

        let mondayStatus = try? await fetchMondayStatus()
        let resolvedIsConnected = mondayStatus?.resolvedIsConnected ?? mondayIntegration.isConnected
        guard resolvedIsConnected else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Monday.com is not connected."]
            )
        }

        let resolvedBoardId = normalizedMondayBoardId(mondayStatus?.selectedBoardId)
            ?? normalizedMondayBoardId(mondayIntegration.selectedBoardId)
        guard resolvedBoardId != nil else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Select a Monday board before testing sync."]
            )
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let data = try await invokeEdgeFunction(name: "crm_sync", body: [
            "lead": [
                "id": UUID().uuidString,
                "name": "FLYR Monday Test Lead",
                "phone": "5555555555",
                "email": "test+\(timestamp)@flyrpro.app",
                "address": "123 Test St, Test City",
                "source": "FLYR iOS Monday Test",
                "notes": "Test lead from FLYR iOS Monday.com sync settings.",
                "created_at": ISO8601DateFormatter().string(from: Date())
            ],
            "user_id": userId.uuidString,
            "exclude_providers": ["fub", "boldtrail", "kvcore", "hubspot", "zapier"]
        ])

        let response = try mondayDecoder().decode(CRMSyncResponse.self, from: data)
        if response.synced.contains(where: Self.isMondayProvider) {
            return "Test lead sent to Monday.com."
        }

        if let failure = response.failed.first(where: { Self.isMondayProvider($0.provider) }) {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: normalizeMondayErrorMessage(
                        failure.error ?? failure.message,
                        fallback: "Unable to send a Monday.com test lead right now."
                    )
                ]
            )
        }

        if response.skipped.contains(where: Self.isMondayProvider) {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Monday.com sync was skipped. Reconnect Monday.com or re-select a board and try again."
                ]
            )
        }

        if let message = normalizeMondayResponseMessage(response.message) {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        throw NSError(
            domain: "CRMIntegrationManager",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Monday.com sync did not run. Reconnect Monday.com or select a board and try again."
            ]
        )
    }

    /// Calls backend `POST /api/integrations/hubspot/test` to verify the stored HubSpot token and scopes.
    func testHubSpotConnection() async throws -> String {
        let data = try await invokeBackendRoute(
            path: "/api/integrations/hubspot/test",
            method: "POST",
            body: [:]
        ) { statusCode, data in
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = obj["error"] as? String ?? obj["message"] as? String,
               !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return msg
            }
            return String(data: data, encoding: .utf8) ?? "Unable to test HubSpot right now. Please try again."
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let res = try decoder.decode(HubSpotTestResponse.self, from: data)
        if res.success == true {
            return res.message ?? "HubSpot connection is working."
        }
        throw NSError(
            domain: "CRMIntegrationManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: res.error ?? res.message ?? "HubSpot test failed."]
        )
    }
    
    // MARK: - Disconnect
    
    func disconnect(userId: UUID, provider: IntegrationProvider) async throws {
        if provider == .monday {
            _ = try await invokeBackendRoute(
                path: "/api/integrations/monday/disconnect",
                method: "POST"
            ) { statusCode, data in
                self.mondayErrorMessage(
                    statusCode: statusCode,
                    data: data,
                    fallback: "Unable to disconnect Monday.com right now. Please try again."
                )
            }
            return
        }

        if provider == .hubspot {
            _ = try await invokeBackendRoute(
                path: "/api/integrations/hubspot/disconnect",
                method: "POST",
                body: [:]
            ) { _, data in
                String(data: data, encoding: .utf8) ?? "Unable to disconnect HubSpot right now. Please try again."
            }
            return
        }

        try await client
            .from("user_integrations")
            .delete()
            .eq("user_id", value: userId)
            .eq("provider", value: provider.rawValue)
            .execute()
    }

    private func normalizeMondayResponseMessage(_ rawMessage: String?) -> String? {
        guard let trimmed = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.lowercased()
        if normalized == "sync completed" || normalized == "no integrations found" {
            return nil
        }

        return normalizeMondayErrorMessage(
            trimmed,
            fallback: "Unable to send a Monday.com test lead right now."
        )
    }

    private static func isMondayProvider(_ provider: String) -> Bool {
        let normalized = provider
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".com", with: "")
            .replacingOccurrences(of: " ", with: "")
        return normalized == "monday"
    }
}

private struct APIErrorPayload: Decodable {
    let error: String?
    let message: String?
    let code: String?
}

private struct CRMSyncResponse: Decodable {
    let message: String?
    let synced: [String]
    let skipped: [String]
    let failed: [CRMSyncFailure]

    enum CodingKeys: String, CodingKey {
        case message
        case synced
        case skipped
        case failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        synced = try container.decodeIfPresent([String].self, forKey: .synced) ?? []
        skipped = try container.decodeIfPresent([String].self, forKey: .skipped) ?? []
        failed = try container.decodeIfPresent([CRMSyncFailure].self, forKey: .failed) ?? []
    }
}

private struct CRMSyncFailure: Decodable {
    let provider: String
    let error: String?
    let message: String?
}
