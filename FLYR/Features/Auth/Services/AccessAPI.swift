import Foundation
import Supabase

/// Access gate and onboarding APIs: redirect, state, onboarding complete, Stripe checkout.
@MainActor
final class AccessAPI {
    static let shared = AccessAPI()

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    /// Base URL used for all API requests. Uses www when host is apex to avoid redirect stripping Authorization.
    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {}

    // MARK: - Helpers

    private func authHeaders() async throws -> [String: String] {
        let session = try await SupabaseManager.shared.client.auth.session
        return [
            "Authorization": "Bearer \(session.accessToken)",
            "Content-Type": "application/json"
        ]
    }

    private func execute<T: Decodable>(
        _ request: URLRequest,
        validStatuses: Set<Int> = [200],
        mapError: ((Int, Data) -> AccessAPIError)?
    ) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccessAPIError.network("No connection—try again.")
        }
        if let map = mapError, !validStatuses.contains(http.statusCode) {
            throw map(http.statusCode, data)
        }
        guard validStatuses.contains(http.statusCode) else {
            throw AccessAPIError.status(http.statusCode, data)
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - GET /api/access/redirect

    /// Returns where the user should go after auth. Requires valid session.
    func getRedirect() async throws -> AccessRedirectResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/access/redirect")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccessAPIError.network("No connection—try again.")
        }
        if http.statusCode == 401 {
            throw AccessAPIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw AccessAPIError.status(http.statusCode, data)
        }
        return try decoder.decode(AccessRedirectResponse.self, from: data)
    }

    // MARK: - GET /api/access/state

    /// Returns current workspace role, name, and hasAccess. Use for guards and member-inactive.
    func getState() async throws -> AccessStateResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/access/state")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccessAPIError.network("No connection—try again.")
        }
        if http.statusCode == 401 {
            throw AccessAPIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw AccessAPIError.status(http.statusCode, data)
        }
        return try decoder.decode(AccessStateResponse.self, from: data)
    }

    // MARK: - POST /api/onboarding/complete

    func completeOnboarding(_ body: OnboardingCompleteRequest) async throws -> OnboardingCompleteResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/onboarding/complete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccessAPIError.network("No connection—try again.")
        }
        if http.statusCode == 401 {
            throw AccessAPIError.unauthorized
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.displayMessage ?? "Invalid request."
            throw AccessAPIError.badRequest(msg)
        }
        guard (200...299).contains(http.statusCode) else {
            throw AccessAPIError.status(http.statusCode, data)
        }
        return try decoder.decode(OnboardingCompleteResponse.self, from: data)
    }

    // MARK: - GET /api/brokerages/search

    func searchBrokerages(query: String, limit: Int = 15) async throws -> [BrokerageSuggestion] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let session = try await SupabaseManager.shared.client.auth.session
        var components = URLComponents(string: "\(requestBaseURL)/api/brokerages/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw AccessAPIError.badRequest("Invalid brokerage search URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccessAPIError.network("No connection—try again.")
        }
        if http.statusCode == 401 {
            throw AccessAPIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw AccessAPIError.status(http.statusCode, data)
        }

        return try decoder.decode([BrokerageSuggestion].self, from: data)
    }

    // MARK: - POST /api/billing/stripe/checkout

    /// Creates Stripe Checkout Session. Returns URL to open in browser/WebView.
    func createCheckoutSession(plan: String, currency: String, priceId: String?) async throws -> URL {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/billing/stripe/checkout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = StripeCheckoutRequest(plan: plan, currency: currency, priceId: priceId)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AccessAPIError.network("No connection—try again.")
        }
        if http.statusCode == 401 {
            throw AccessAPIError.unauthorized
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.displayMessage ?? "Invalid request."
            throw AccessAPIError.badRequest(msg)
        }
        guard (200...299).contains(http.statusCode) else {
            throw AccessAPIError.status(http.statusCode, data)
        }
        let parsed = try decoder.decode(StripeCheckoutResponse.self, from: data)
        guard let checkoutURL = URL(string: parsed.url) else {
            throw AccessAPIError.badRequest("Invalid checkout URL.")
        }
        return checkoutURL
    }
}

// MARK: - Error body (generic message from API)

private struct ErrorBody: Codable {
    let message: String?
    let error: String?

    var displayMessage: String? { message ?? error }
}

// MARK: - Access API errors

enum AccessAPIError: LocalizedError {
    case network(String)
    case unauthorized
    case badRequest(String)
    case forbidden(String)
    case notFound(String)
    case server(String)
    case status(Int, Data)

    var errorDescription: String? {
        switch self {
        case .network(let msg), .badRequest(let msg), .forbidden(let msg), .notFound(let msg), .server(let msg):
            return msg
        case .unauthorized:
            return "Please sign in again."
        case .status(let code, _):
            return "Request failed (\(code))."
        }
    }
}
