import Foundation
import Supabase

/// Manages CRM integration connections (connect, disconnect, fetch)
actor CRMIntegrationManager {
    static let shared = CRMIntegrationManager()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
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
        let integrationData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId),
            "provider": AnyCodable("fub"),
            "api_key": AnyCodable(apiKey),
            "updated_at": AnyCodable(Date())
        ]
        
        try await client
            .from("user_integrations")
            .upsert(integrationData, onConflict: "user_id,provider")
            .execute()
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
        guard provider == .hubspot || provider == .monday else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid provider for OAuth"]
            )
        }
        
        // Call Supabase Edge Function to exchange code for tokens
        let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String
        let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
        let url = URL(string: "\(supabaseURLString)/functions/v1/oauth_exchange")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Get auth token
        let session = try await client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        
        // Encode request body
        let body: [String: Any] = [
            "provider": provider.rawValue,
            "code": code,
            "user_id": userId.uuidString
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(
                domain: "CRMIntegrationManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            )
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(
                domain: "CRMIntegrationManager",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "OAuth exchange failed: \(errorMessage)"]
            )
        }
    }
    
    // MARK: - Disconnect
    
    func disconnect(userId: UUID, provider: IntegrationProvider) async throws {
        try await client
            .from("user_integrations")
            .delete()
            .eq("user_id", value: userId)
            .eq("provider", value: provider.rawValue)
            .execute()
    }
}

