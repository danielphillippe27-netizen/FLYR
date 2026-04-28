import Foundation
import Supabase

/// Invite validation (no auth) and acceptance (auth). Use for join flow.
@MainActor
final class InviteService {
    static let shared = InviteService()
    private let legacyInvitesAPIHost = "backend-api-routes.vercel.app"

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    /// Uses `www` for authenticated requests so redirects do not drop Authorization headers.
    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    private var inviteBaseURL: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "FLYR_INVITES_API_URL") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = configured.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let components = URLComponents(string: trimmed),
               components.host?.lowercased() == "flyrpro.app" {
                return "https://www.flyrpro.app"
            }
            return trimmed
        }

        return "https://\(legacyInvitesAPIHost)"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractionalSecondsFormatter = ISO8601DateFormatter()
            fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]

            if let date = fractionalSecondsFormatter.date(from: value)
                ?? fallbackFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {}

    // MARK: - GET /api/invites/validate?token=... (no auth)

    /// Validates invite token. Call before sign-in to show workspace name and invited email.
    func validate(token: String) async throws -> InviteValidateResponse {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw InviteServiceError.badRequest("Token required.")
        }
        var components = URLComponents(string: "\(inviteBaseURL)/api/invites/validate")!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else {
            throw InviteServiceError.badRequest("Invalid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let session = try? await SupabaseManager.shared.client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

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
        return try decode(InviteValidateResponse.self, from: data, endpoint: "validate")
    }

    // MARK: - POST /api/invites/accept (auth required)

    /// Accepts invite. User must be signed in; email must match invite email (case-insensitive).
    func accept(token: String) async throws -> InviteAcceptResponse {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw InviteServiceError.badRequest("Token required.")
        }
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(inviteBaseURL)/api/invites/accept")!
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
        return try decode(InviteAcceptResponse.self, from: data, endpoint: "accept")
    }

    // MARK: - POST /api/invites/create (auth required)

    /// Creates a shareable campaign invite link for the active workspace-backed campaign.
    func createInvite(campaignId: UUID) async throws -> InviteCreateResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(inviteBaseURL)/api/invites/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            InviteCreateRequest(
                campaignId: campaignId.uuidString,
                sessionId: nil
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InviteServiceError.network("No connection—try again.")
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Invalid request."
            throw InviteServiceError.badRequest(msg)
        }
        if http.statusCode == 401 {
            throw InviteServiceError.unauthorized
        }
        if http.statusCode == 403 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "You do not have permission to invite people to this campaign."
            throw InviteServiceError.forbidden(msg)
        }
        if http.statusCode == 404 {
            let fallbackMessage: String
            if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               contentType.contains("text/html") {
                fallbackMessage = "Invite service is not live on the backend yet. Deploy backend-api-routes and try again."
            } else {
                fallbackMessage = "Campaign not found."
            }
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? fallbackMessage
            throw InviteServiceError.notFound(msg)
        }
        guard (200...299).contains(http.statusCode) else {
            throw InviteServiceError.server((try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Something went wrong.")
        }
        return try decode(InviteCreateResponse.self, from: data, endpoint: "create")
    }

    func createLiveSessionCode(sessionId: UUID) async throws -> LiveSessionCodeCreateResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(inviteBaseURL)/api/live-sessions/codes/create")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["session_id": sessionId.uuidString])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InviteServiceError.network("No connection—try again.")
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Unable to create a join code."
            throw InviteServiceError.badRequest(msg)
        }
        if http.statusCode == 401 {
            throw InviteServiceError.unauthorized
        }
        if http.statusCode == 403 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Only the host can create a session code."
            throw InviteServiceError.forbidden(msg)
        }
        if http.statusCode == 404 {
            let fallbackMessage: String
            if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               contentType.contains("text/html") {
                fallbackMessage = "Session code service is not live on the backend yet. Deploy backend-api-routes and try again."
            } else {
                fallbackMessage = "Live session not found."
            }
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? fallbackMessage
            throw InviteServiceError.notFound(msg)
        }
        guard (200...299).contains(http.statusCode) else {
            throw InviteServiceError.server((try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Something went wrong.")
        }
        return try decode(LiveSessionCodeCreateResponse.self, from: data, endpoint: "live-code-create")
    }

    func joinLiveSession(code: String) async throws -> LiveSessionCodeJoinResponse {
        let trimmedCode = sanitizeLiveSessionCode(code)
        guard !trimmedCode.isEmpty else {
            throw InviteServiceError.badRequest("Enter a session code.")
        }

        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(inviteBaseURL)/api/live-sessions/codes/join")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["code": trimmedCode])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw InviteServiceError.network("No connection—try again.")
        }
        if http.statusCode == 400 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "This session code has expired."
            throw InviteServiceError.badRequest(msg)
        }
        if http.statusCode == 401 {
            throw InviteServiceError.unauthorized
        }
        if http.statusCode == 403 {
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "You can’t join this live session."
            throw InviteServiceError.forbidden(msg)
        }
        if http.statusCode == 404 {
            let fallbackMessage: String
            if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               contentType.contains("text/html") {
                fallbackMessage = "Session code service is not live on the backend yet. Deploy backend-api-routes and try again."
            } else {
                fallbackMessage = "Invalid session code."
            }
            let msg = (try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? fallbackMessage
            throw InviteServiceError.notFound(msg)
        }
        guard (200...299).contains(http.statusCode) else {
            throw InviteServiceError.server((try? decoder.decode(InviteErrorBody.self, from: data))?.displayMessage ?? "Something went wrong.")
        }
        return try decode(LiveSessionCodeJoinResponse.self, from: data, endpoint: "live-code-join")
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        endpoint: String
    ) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[InviteService] \(endpoint) decode keyNotFound: \(key.stringValue) path=\(codingPathDescription(context.codingPath)) body=\(body)")
            throw InviteServiceError.server("The invite response was missing required data. Please try again.")
        } catch let DecodingError.valueNotFound(type, context) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[InviteService] \(endpoint) decode valueNotFound: \(type) path=\(codingPathDescription(context.codingPath)) body=\(body)")
            throw InviteServiceError.server("The invite response was incomplete. Please try again.")
        } catch let DecodingError.typeMismatch(type, context) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[InviteService] \(endpoint) decode typeMismatch: \(type) path=\(codingPathDescription(context.codingPath)) body=\(body)")
            throw InviteServiceError.server("The invite response was in an unexpected format. Please try again.")
        } catch let DecodingError.dataCorrupted(context) {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[InviteService] \(endpoint) decode dataCorrupted: \(context.debugDescription) path=\(codingPathDescription(context.codingPath)) body=\(body)")
            throw InviteServiceError.server("The invite response could not be read. Please try again.")
        } catch {
            throw error
        }
    }

    private func codingPathDescription(_ path: [CodingKey]) -> String {
        path.map(\.stringValue).joined(separator: ".")
    }

    private func sanitizeLiveSessionCode(_ code: String) -> String {
        code.uppercased().replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
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
