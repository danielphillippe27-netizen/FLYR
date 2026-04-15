import Foundation
import Supabase

/// Calls backend POST /api/integrations/fub/connect with Bearer JWT and api_key only.
/// Backend verifies FUB key and stores encrypted key; never call FUB from the app.
@MainActor
final class FUBConnectAPI {
    static let shared = FUBConnectAPI()

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

    /// Connect Follow Up Boss: send trimmed api_key to backend. Backend uses JWT for user_id.
    /// - Returns: On success, account name/company. On failure throws with a user-facing message.
    func connect(apiKey: String) async throws -> FUBConnectResponse.FUBAccount {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else {
            throw FUBConnectError.localInvalid("API key looks too short.")
        }

        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/fub/connect")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(FUBConnectRequest(apiKey: trimmed))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FUBConnectError.network("No connection—try again.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw FUBConnectError.network("No connection—try again.")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if http.statusCode == 401 || http.statusCode == 400 {
            if let body = try? decoder.decode(FUBConnectResponse.self, from: data), let msg = body.error, !msg.isEmpty {
                throw FUBConnectError.authFailed(msg)
            }
            throw FUBConnectError.authFailed("That key isn't valid.")
        }

        guard (200...299).contains(http.statusCode) else {
            if let body = try? decoder.decode(FUBConnectResponse.self, from: data), let msg = body.error {
                throw FUBConnectError.server(msg)
            }
            throw FUBConnectError.network("No connection—try again.")
        }

        let parsed = try decoder.decode(FUBConnectResponse.self, from: data)
        guard parsed.connected, let account = parsed.account else {
            throw FUBConnectError.authFailed(parsed.error ?? "That key isn't valid.")
        }
        return account
    }

    /// Disconnect FUB via backend (server-side only; wipes secrets).
    func disconnect() async throws {
        let session = try await SupabaseManager.shared.client.auth.session
        do {
            try await performDisconnect(
                accessToken: session.accessToken,
                method: "POST",
                fallbackMethod: "DELETE"
            )
        } catch let error as FUBConnectError {
            throw error
        } catch {
            throw FUBConnectError.network("No connection—try again.")
        }
    }

    private func performDisconnect(
        accessToken: String,
        method: String,
        fallbackMethod: String? = nil
    ) async throws {
        let url = URL(string: "\(requestBaseURL)/api/integrations/fub/disconnect")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FUBConnectError.network("No connection—try again.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw FUBConnectError.network("No connection—try again.")
        }

        let body = try? JSONDecoder().decode(CRMDisconnectResponse.self, from: data)

        if http.statusCode == 405, let fallbackMethod {
            try await performDisconnect(accessToken: accessToken, method: fallbackMethod)
            return
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw FUBConnectError.authFailed(body?.error ?? "Not authorized")
        }
        if !(200...299).contains(http.statusCode) {
            throw FUBConnectError.server(body?.error ?? body?.message ?? "Failed to disconnect")
        }
    }
}

enum FUBConnectError: LocalizedError {
    case localInvalid(String)
    case authFailed(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .localInvalid(let msg), .authFailed(let msg), .network(let msg), .server(let msg):
            return msg
        }
    }
}
