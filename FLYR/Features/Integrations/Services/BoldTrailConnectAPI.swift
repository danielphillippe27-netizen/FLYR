import Foundation
import Supabase

@MainActor
final class BoldTrailConnectAPI {
    static let shared = BoldTrailConnectAPI()

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

    func testConnection(apiToken: String? = nil) async throws -> BoldTrailConnectResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/boldtrail/test")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        if let apiToken {
            let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            request.httpBody = try JSONEncoder().encode(BoldTrailConnectRequest(apiToken: trimmed))
        }

        return try await perform(request, unauthorizedMessage: "Invalid token")
    }

    func connect(apiToken: String) async throws -> BoldTrailConnectResponse {
        let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BoldTrailConnectError.invalid("API token is required.")
        }

        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/boldtrail/connect")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(BoldTrailConnectRequest(apiToken: trimmed))

        return try await perform(request, unauthorizedMessage: "Invalid token")
    }

    func disconnect() async throws {
        let session = try await SupabaseManager.shared.client.auth.session
        do {
            try await performDisconnect(
                accessToken: session.accessToken,
                method: "POST",
                fallbackMethod: "DELETE"
            )
        } catch let error as BoldTrailConnectError {
            throw error
        } catch {
            throw BoldTrailConnectError.network("Unable to disconnect right now.")
        }
    }

    func fetchStatus() async throws -> BoldTrailStatusResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/boldtrail/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BoldTrailConnectError.network("Unable to fetch BoldTrail status.")
        }

        let decoded = try JSONDecoder().decode(BoldTrailStatusResponse.self, from: data)
        if http.statusCode == 401 {
            throw BoldTrailConnectError.auth(decoded.error ?? "Not authorized.")
        }
        if !(200...299).contains(http.statusCode) {
            throw BoldTrailConnectError.server(decoded.error ?? "Failed to fetch status.")
        }
        return decoded
    }

    private func perform(
        _ request: URLRequest,
        unauthorizedMessage: String
    ) async throws -> BoldTrailConnectResponse {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BoldTrailConnectError.network("Unable to connect to BoldTrail.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw BoldTrailConnectError.network("Unable to connect to BoldTrail.")
        }

        let decoded = try JSONDecoder().decode(BoldTrailConnectResponse.self, from: data)
        if http.statusCode == 401 {
            throw BoldTrailConnectError.auth(decoded.error ?? unauthorizedMessage)
        }
        if http.statusCode == 404 {
            throw BoldTrailConnectError.notConnected(decoded.error ?? "BoldTrail is not connected.")
        }
        if !(200...299).contains(http.statusCode) {
            throw BoldTrailConnectError.server(decoded.error ?? "BoldTrail request failed.")
        }
        if decoded.success == false || decoded.connected == false {
            throw BoldTrailConnectError.server(decoded.error ?? decoded.message ?? "BoldTrail request failed.")
        }
        return decoded
    }

    private func performDisconnect(
        accessToken: String,
        method: String,
        fallbackMethod: String? = nil
    ) async throws {
        let url = URL(string: "\(requestBaseURL)/api/integrations/boldtrail/disconnect")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw BoldTrailConnectError.network("Unable to disconnect right now.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw BoldTrailConnectError.network("Unable to disconnect right now.")
        }

        let decoded = try? JSONDecoder().decode(CRMDisconnectResponse.self, from: data)

        if http.statusCode == 405, let fallbackMethod {
            try await performDisconnect(accessToken: accessToken, method: fallbackMethod)
            return
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw BoldTrailConnectError.auth(decoded?.error ?? "Not authorized.")
        }
        if !(200...299).contains(http.statusCode) {
            throw BoldTrailConnectError.server(decoded?.error ?? decoded?.message ?? "Failed to disconnect BoldTrail.")
        }
    }
}

enum BoldTrailConnectError: LocalizedError {
    case invalid(String)
    case auth(String)
    case notConnected(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .auth(let message), .notConnected(let message), .network(let message), .server(let message):
            return message
        }
    }
}
