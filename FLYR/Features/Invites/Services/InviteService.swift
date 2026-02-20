import Foundation
import Supabase

/// Invite validation (no auth) and acceptance (auth). Use for join flow.
@MainActor
final class InviteService {
    static let shared = InviteService()

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = JSONEncoder()

    private init() {}

    // MARK: - GET /api/invites/validate?token=... (no auth)

    /// Validates invite token. Call before sign-in to show workspace name and invited email.
    func validate(token: String) async throws -> InviteValidateResponse {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw InviteServiceError.badRequest("Token required.")
        }
        var components = URLComponents(string: "\(baseURL)/api/invites/validate")!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else {
            throw InviteServiceError.badRequest("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InviteServiceError.network("No connection—try again.")
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "This invite has already been used or has expired."
            throw InviteServiceError.badRequest(msg)
        }
        if http.statusCode == 404 {
            throw InviteServiceError.notFound("Invalid or expired invite.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw InviteServiceError.status(http.statusCode)
        }
        return try decoder.decode(InviteValidateResponse.self, from: data)
    }

    // MARK: - POST /api/invites/accept (auth required)

    /// Accepts invite. User must be signed in; email must match invite email (case-insensitive).
    func accept(token: String) async throws -> InviteAcceptResponse {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw InviteServiceError.badRequest("Token required.")
        }
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(baseURL)/api/invites/accept")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(InviteAcceptRequest(token: token))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InviteServiceError.network("No connection—try again.")
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "This invite has already been used or has expired."
            throw InviteServiceError.badRequest(msg)
        }
        if http.statusCode == 401 {
            throw InviteServiceError.unauthorized
        }
        if http.statusCode == 403 {
            throw InviteServiceError.forbidden("This invite was sent to a different email address.")
        }
        if http.statusCode == 404 {
            throw InviteServiceError.notFound("Invalid or expired invite.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw InviteServiceError.server((try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Something went wrong.")
        }
        return try decoder.decode(InviteAcceptResponse.self, from: data)
    }
}

private struct InviteErrorBody: Codable {
    let message: String?
    let error: String?
    var displayMessage: String? { message ?? error }
}

enum InviteServiceError: LocalizedError {
    case network(String)
    case badRequest(String)
    case unauthorized
    case forbidden(String)
    case notFound(String)
    case server(String)
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .network(let msg), .badRequest(let msg), .forbidden(let msg), .notFound(let msg), .server(let msg):
            return msg
        case .unauthorized:
            return "Please sign in again."
        case .status(let code):
            return "Request failed (\(code))."
        }
    }
}
