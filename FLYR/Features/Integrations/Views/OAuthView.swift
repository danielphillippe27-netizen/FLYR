import SwiftUI
import SafariServices
import AuthenticationServices
import Supabase

/// OAuth view wrapper using SFSafariViewController for in-app OAuth flows
struct OAuthView: View {
    let provider: IntegrationProvider
    let userId: UUID
    let onComplete: (Result<String, Error>) -> Void

    @State private var authURL: URL?
    @State private var didReportError = false

    var body: some View {
        Group {
            if let authURL {
                OAuthSafariView(url: authURL)
            } else {
                ProgressView("Opening \(provider.displayName)...")
                    .task {
                        await loadAuthURLIfNeeded()
                    }
            }
        }
    }

    private func loadAuthURLIfNeeded() async {
        guard authURL == nil else { return }
        do {
            authURL = try await OAuthURLBuilder.authURL(for: provider)
        } catch {
            guard !didReportError else { return }
            didReportError = true
            onComplete(.failure(error))
        }
    }
}

private struct OAuthSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safariVC = SFSafariViewController(url: url)
        safariVC.dismissButtonStyle = .close
        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

/// Helper to get OAuth URLs from environment/config
/// HubSpot OAuth uses backend `/api/integrations/hubspot/oauth/start`. Monday uses MONDAY_CLIENT_ID in Info.plist/xcconfig for the start URL step.
struct OAuthURLBuilder {
    enum OAuthBuildError: LocalizedError {
        case unsupportedProvider(String)
        case missingClientID(String)
        case invalidURL(String)
        
        var errorDescription: String? {
            switch self {
            case .unsupportedProvider(let provider):
                return "OAuth is not supported for \(provider)."
            case .missingClientID(let provider):
                return "Missing \(provider) OAuth client ID in app configuration."
            case .invalidURL(let provider):
                return "Failed to build a valid \(provider) OAuth URL."
            }
        }
    }
    
    static func authURL(for provider: IntegrationProvider) async throws -> URL {
        switch provider {
        case .hubspot:
            return try await HubSpotOAuthAPI.shared.fetchAuthorizeURL(platform: "ios")
        case .monday:
            return try await mondayAuthURL()
        default:
            throw OAuthBuildError.unsupportedProvider(provider.displayName)
        }
    }

    static func mondayAuthURL() async throws -> URL {
        try await MondayOAuthAPI.shared.fetchAuthorizeURL(platform: "ios")
    }
}

@MainActor
private final class HubSpotOAuthAPI {
    static let shared = HubSpotOAuthAPI()

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

    func fetchAuthorizeURL(platform: String = "ios") async throws -> URL {
        let session = try await SupabaseManager.shared.client.auth.session
        var components = URLComponents(string: "\(requestBaseURL)/api/integrations/hubspot/oauth/start")!
        var queryItems = [URLQueryItem(name: "platform", value: platform)]
        if let workspaceId = WorkspaceContext.shared.workspaceId?.uuidString {
            queryItems.append(URLQueryItem(name: "workspaceId", value: workspaceId))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OAuthURLBuilder.OAuthBuildError.invalidURL("HubSpot")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthURLBuilder.OAuthBuildError.invalidURL("HubSpot")
        }

        let decoder = JSONDecoder()
        let payload = try? decoder.decode(HubSpotOAuthStartResponse.self, from: data)

        guard (200...299).contains(http.statusCode) else {
            throw NSError(
                domain: "HubSpotOAuthAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: payload?.error ?? "Unable to start HubSpot OAuth."]
            )
        }

        guard let rawURL = payload?.authorizeURL, let authorizeURL = URL(string: rawURL) else {
            throw NSError(
                domain: "HubSpotOAuthAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: payload?.error ?? "HubSpot OAuth did not return an authorize URL."]
            )
        }

        return authorizeURL
    }
}

@MainActor
private final class MondayOAuthAPI {
    static let shared = MondayOAuthAPI()

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

    func fetchAuthorizeURL(platform: String = "ios") async throws -> URL {
        let session = try await SupabaseManager.shared.client.auth.session
        var components = URLComponents(string: "\(requestBaseURL)/api/integrations/monday/oauth/start")!
        var queryItems = [URLQueryItem(name: "platform", value: platform)]
        if let workspaceId = WorkspaceContext.shared.workspaceId?.uuidString {
            queryItems.append(URLQueryItem(name: "workspaceId", value: workspaceId))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw OAuthURLBuilder.OAuthBuildError.invalidURL("Monday.com")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthURLBuilder.OAuthBuildError.invalidURL("Monday.com")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try? decoder.decode(MondayOAuthStartResponse.self, from: data)

        guard (200...299).contains(http.statusCode) else {
            throw NSError(
                domain: "MondayOAuthAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: payload?.error ?? "Unable to start Monday.com OAuth."]
            )
        }

        guard let rawURL = payload?.authorizeURL, let authorizeURL = URL(string: rawURL) else {
            throw NSError(
                domain: "MondayOAuthAPI",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: payload?.error ?? "Monday.com OAuth did not return an authorize URL."]
            )
        }

        return authorizeURL
    }
}

private struct MondayOAuthStartResponse: Decodable {
    let success: Bool?
    let authorizeURL: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case authorizeURL = "authorizeUrl"
        case error
    }
}
