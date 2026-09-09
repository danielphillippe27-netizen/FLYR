import Foundation
import Supabase
import Auth

@MainActor
final class FUBConnectionTestAPI {
    static let shared = FUBConnectionTestAPI()

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "WOLFGRID_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://sales.wolfgrid.app"
    }

    private init() {}

    func testConnection() async throws -> FUBTestResponse {
        try await post(path: "api/integrations/fub/test")
    }

    func testPush() async throws -> FUBTestResponse {
        try await post(path: "api/integrations/fub/test-push")
    }

    func syncCRM() async throws -> FUBSyncCRMResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        guard let url = URL(string: "\(baseURL)/api/leads/sync-crm") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(FUBSyncCRMResponse.self, from: data)
        guard (200...299).contains(http.statusCode) else {
            throw FUBConnectionTestError(message: decoded.error ?? "CRM sync failed.")
        }
        return decoded
    }

    private func post(path: String) async throws -> FUBTestResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(FUBTestResponse.self, from: data)
        guard (200...299).contains(http.statusCode) else {
            throw FUBConnectionTestError(message: decoded.error ?? "Follow Up Boss request failed.")
        }
        return decoded
    }
}

private struct FUBConnectionTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
