import Foundation
import Supabase

@MainActor
final class LiveSessionVoiceAPI {
    static let shared = LiveSessionVoiceAPI()

    private let defaultVoiceAPIURL = "https://backend-api-routes.vercel.app"

    private var baseURL: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "FLYR_VOICE_API_URL") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        if let configuredInvitesURL = Bundle.main.object(forInfoDictionaryKey: "FLYR_INVITES_API_URL") as? String,
           !configuredInvitesURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configuredInvitesURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return defaultVoiceAPIURL
    }

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    func joinSessionVoice(sessionId: UUID, campaignId: UUID) async throws -> VoiceRoomCredentials {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(baseURL)/api/live-sessions/voice/join")!
        let requestPayload = [
            "session_id": sessionId.uuidString,
            "campaign_id": campaignId.uuidString
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestPayload)

        print("📡 [LiveSessionVoiceAPI] POST \(url.absoluteString)")
        print("📡 [LiveSessionVoiceAPI] session_id=\(sessionId.uuidString)")
        print("📡 [LiveSessionVoiceAPI] campaign_id=\(campaignId.uuidString)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("❌ [LiveSessionVoiceAPI] No HTTPURLResponse returned")
            throw LiveSessionVoiceAPIError.network("No connection.")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        print("📡 [LiveSessionVoiceAPI] status=\(http.statusCode)")
        print("📡 [LiveSessionVoiceAPI] body=\(responseBody)")

        switch http.statusCode {
        case 200...299:
            return try decoder.decode(VoiceRoomCredentials.self, from: data)
        case 401:
            throw LiveSessionVoiceAPIError.unauthorized
        case 403:
            throw LiveSessionVoiceAPIError.forbidden("Voice is only available to teammates in this live session.")
        case 404:
            throw LiveSessionVoiceAPIError.notFound("Session voice is unavailable for this live session.")
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LiveSessionVoiceAPIError.server(body.isEmpty ? "Unable to join voice right now." : body)
        }
    }
}

enum LiveSessionVoiceAPIError: LocalizedError {
    case network(String)
    case unauthorized
    case forbidden(String)
    case notFound(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .network(message), let .forbidden(message), let .notFound(message), let .server(message):
            return message
        case .unauthorized:
            return "Please sign in again."
        }
    }
}
