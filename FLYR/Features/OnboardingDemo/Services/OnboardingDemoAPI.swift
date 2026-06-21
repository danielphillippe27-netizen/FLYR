import Foundation
import Supabase

final class OnboardingDemoAPI {
    static let shared = OnboardingDemoAPI()

    private init() {}

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

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO date: \(raw)")
        }
        return decoder
    }()

    private let encoder = JSONEncoder()

    func fetchState() async throws -> OnboardingDemoState {
        let url = URL(string: "\(requestBaseURL)/api/onboarding/demo/state")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let (data, http) = try await dataForAuthorizedRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw OnboardingDemoAPIError.status(http.statusCode)
        }
        return try decoder.decode(OnboardingDemoState.self, from: data)
    }

    func seed() async throws -> OnboardingDemoSeedResponse {
        let url = URL(string: "\(requestBaseURL)/api/onboarding/demo/seed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, http) = try await dataForAuthorizedRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw OnboardingDemoAPIError.status(http.statusCode)
        }
        return try decoder.decode(OnboardingDemoSeedResponse.self, from: data)
    }

    func patch(dismissed: Bool? = nil, completedChecklistItems: [String]? = nil) async throws -> OnboardingDemoState {
        let url = URL(string: "\(requestBaseURL)/api/onboarding/demo/state")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(OnboardingDemoPatchRequest(
            dismissed: dismissed,
            completedChecklistItems: completedChecklistItems
        ))
        let (data, http) = try await dataForAuthorizedRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw OnboardingDemoAPIError.status(http.statusCode)
        }
        return try decoder.decode(OnboardingDemoState.self, from: data)
    }

    private func dataForAuthorizedRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authedRequest = request
        let session = try await SupabaseManager.shared.client.auth.session
        authedRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authedRequest)
        guard let http = response as? HTTPURLResponse else {
            throw OnboardingDemoAPIError.network
        }
        guard http.statusCode == 401 else {
            return (data, http)
        }

        let refreshed = try await SupabaseManager.shared.client.auth.refreshSession()
        KeychainAuthStorage.saveSession(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken)
        authedRequest.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")

        let (retryData, retryResponse) = try await URLSession.shared.data(for: authedRequest)
        guard let retryHTTP = retryResponse as? HTTPURLResponse else {
            throw OnboardingDemoAPIError.network
        }
        return (retryData, retryHTTP)
    }
}

private struct OnboardingDemoPatchRequest: Encodable {
    let dismissed: Bool?
    let completedChecklistItems: [String]?
}

enum OnboardingDemoAPIError: LocalizedError {
    case network
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .network:
            return "No connection. Please try again."
        case .status(let code):
            return "Onboarding demo request failed (\(code))."
        }
    }
}
