import Foundation
import Supabase

@MainActor
final class FUBOAuthAPI {
    static let shared = FUBOAuthAPI()

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    /// Use www when the configured API host is the apex domain so redirects do not strip Authorization.
    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    private init() {}

    func fetchAuthorizeURL(platform: String = "ios") async throws -> URL {
        let session = try await SupabaseManager.shared.client.auth.session
        var comps = URLComponents(string: "\(requestBaseURL)/api/integrations/fub/oauth/start")!
        comps.queryItems = [
            URLQueryItem(name: "platform", value: platform)
        ]
        guard let url = comps.url else {
            throw NSError(
                domain: "FUBOAuthAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth start URL."]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        #if DEBUG
        let tokenSuffix = String(session.accessToken.suffix(8))
        print("🔐 [FUB OAuth] Starting OAuth. baseURL=\(baseURL) requestBaseURL=\(requestBaseURL) platform=\(platform) userId=\(session.user.id.uuidString) tokenSuffix=\(tokenSuffix)")
        #endif

        let (data, http) = try await dataForAuthorizedRequest(request)

        #if DEBUG
        let responseBody = previewBody(data)
        let finalURL = http.url?.absoluteString ?? "<nil>"
        print("🌐 [FUB OAuth] /oauth/start status=\(http.statusCode) requestURL=\(url.absoluteString) finalURL=\(finalURL) body=\(responseBody)")
        #endif

        let payload = try? JSONDecoder().decode(FUBOAuthStartResponse.self, from: data)

        guard (200...299).contains(http.statusCode) else {
            let message = payload?.error ?? previewBody(data)
            throw NSError(
                domain: "FUBOAuthAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Unable to start OAuth flow." : message]
            )
        }

        guard let rawURL = payload?.authorizeURL, let authorizeURL = URL(string: rawURL) else {
            throw NSError(
                domain: "FUBOAuthAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: payload?.error ?? "OAuth start succeeded but no authorize URL was returned."]
            )
        }
        return authorizeURL
    }

    private func dataForAuthorizedRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authedRequest = request

        let (data, response) = try await URLSession.shared.data(for: authedRequest)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(
                domain: "FUBOAuthAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth response."]
            )
        }

        guard http.statusCode == 401 else {
            return (data, http)
        }

        #if DEBUG
        print("⚠️ [FUB OAuth] Initial /oauth/start request returned 401. Attempting session refresh. Body=\(previewBody(data))")
        #endif

        do {
            let refreshed = try await SupabaseManager.shared.client.auth.refreshSession()
            KeychainAuthStorage.saveSession(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken
            )
            authedRequest.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")

            let (retryData, retryResponse) = try await URLSession.shared.data(for: authedRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw NSError(
                    domain: "FUBOAuthAPI",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth retry response."]
                )
            }

            #if DEBUG
            print("🔁 [FUB OAuth] Retry /oauth/start status=\(retryHTTP.statusCode) finalURL=\(retryHTTP.url?.absoluteString ?? "<nil>") body=\(previewBody(retryData))")
            #endif

            return (retryData, retryHTTP)
        } catch {
            #if DEBUG
            print("❌ [FUB OAuth] Session refresh failed after 401: \(error.localizedDescription)")
            #endif
            return (data, http)
        }
    }

    private func previewBody(_ data: Data) -> String {
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "<empty>"
        }
        return String(trimmed.prefix(400))
    }
}

private struct FUBOAuthStartResponse: Codable {
    let success: Bool?
    let authorizeURL: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case authorizeURL = "authorizeUrl"
        case error
    }
}
