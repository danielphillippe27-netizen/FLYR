import Foundation
import SwiftUI
import SafariServices
import Supabase

struct TeamWebHandoffResponse: Decodable {
    let code: String
    /// Backend sends ISO8601 string; we only need code for the URL so decode as string to avoid date-format issues.
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
    }
}

enum TeamWebHandoffError: LocalizedError {
    case missingSession
    case invalidBaseURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "Please sign in again."
        case .invalidBaseURL:
            return "Team onboarding is unavailable right now."
        case .invalidResponse:
            return "Could not start team onboarding."
        case .requestFailed(let message):
            return message
        }
    }
}

@MainActor
final class TeamWebHandoff {
    static let shared = TeamWebHandoff()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private init() {}

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    /// Base URL for the handoff API request only. Always uses www to avoid apex→www redirect stripping Authorization.
    private var handoffRequestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    func createTeamOnboardingURL() async throws -> URL {
        let session = try await SupabaseManager.shared.client.auth.session
        guard !session.accessToken.isEmpty else {
            throw TeamWebHandoffError.missingSession
        }

        let handoffURLString = "\(handoffRequestBaseURL)/api/auth/handoff"
        guard let handoffURL = URL(string: handoffURLString) else {
            throw TeamWebHandoffError.invalidBaseURL
        }

        var request = URLRequest(url: handoffURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        #if DEBUG
        print("🔗 Handoff: POST \(handoffURLString), user id=\(session.user.id), token length=\(session.accessToken.count)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TeamWebHandoffError.invalidResponse
        }

        #if DEBUG
        let authPresent = request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") ?? false
        print("🔗 Handoff: response status=\(http.statusCode), request had Authorization=\(authPresent)")
        #endif

        guard (200...299).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let apiMessage = payload?["error"] as? String
            let bodyText = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackBody = (bodyText?.isEmpty == false) ? bodyText! : "No response body"
            let message: String
            if http.statusCode == 401 {
                message = "Please sign in again."
            } else if let apiMessage = apiMessage, !apiMessage.isEmpty {
                message = apiMessage
            } else if http.statusCode == 405 {
                message = "Team setup on web is temporarily unavailable. Please try again later."
            } else {
                message = "Failed to continue on web (\(http.statusCode)): \(fallbackBody)"
            }
            throw TeamWebHandoffError.requestFailed(message)
        }

        let handoff: TeamWebHandoffResponse
        do {
            guard !data.isEmpty else {
                #if DEBUG
                print("🔗 Handoff: 200 but response body is empty")
                #endif
                throw TeamWebHandoffError.requestFailed("Team setup on web is temporarily unavailable. Please try again later.")
            }
            handoff = try decoder.decode(TeamWebHandoffResponse.self, from: data)
        } catch is DecodingError {
            #if DEBUG
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "?."
            print("🔗 Handoff: 200 but decode failed. Body snippet: \(snippet)")
            #endif
            throw TeamWebHandoffError.requestFailed("Team setup on web is temporarily unavailable. Please try again later.")
        }
        guard let onboardingBaseURL = URL(string: "\(baseURL)/onboarding/team"),
              var components = URLComponents(url: onboardingBaseURL, resolvingAgainstBaseURL: false) else {
            throw TeamWebHandoffError.invalidBaseURL
        }
        components.queryItems = [URLQueryItem(name: "code", value: handoff.code)]
        guard let onboardingURL = components.url else {
            throw TeamWebHandoffError.invalidBaseURL
        }
        return onboardingURL
    }
}

struct TeamWebHandoffSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safariVC = SFSafariViewController(url: url)
        safariVC.dismissButtonStyle = .close
        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
