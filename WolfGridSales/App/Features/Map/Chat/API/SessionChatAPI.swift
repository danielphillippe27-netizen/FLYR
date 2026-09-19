import Foundation
import Supabase

final class SessionChatAPI {
    static let shared = SessionChatAPI()

    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    private var baseURL: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "WOLFGRID_INVITES_API_URL") as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let isSales = Bundle.main.bundleIdentifier?.lowercased().contains("sales") == true
        return isSales ? "https://sales.wolfgrid.app" : "https://wolfgrid.app"
    }

    private init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        decoder = JSONDecoder.supabaseDates
    }

    func fetchRooms(cursor: String? = nil) async throws -> SessionChatRoomsResponse {
        var components = URLComponents(string: "\(baseURL)/api/live-sessions/chat/rooms")!
        if let cursor { components.queryItems = [URLQueryItem(name: "cursor", value: cursor)] }
        return try await send(URLRequest(url: components.url!))
    }

    func fetchMessages(sessionId: UUID, cursor: String? = nil) async throws -> SessionChatMessagesResponse {
        var components = URLComponents(string: "\(baseURL)/api/live-sessions/chat/messages")!
        components.queryItems = [URLQueryItem(name: "sessionId", value: sessionId.uuidString)]
        if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(URLRequest(url: components.url!))
    }

    func sendText(sessionId: UUID, clientMessageId: UUID, text: String) async throws -> SessionChatSendResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...1_000).contains(trimmed.count) else {
            throw SessionChatAPIError.invalidMessage("Messages must contain between 1 and 1,000 characters.")
        }
        var request = URLRequest(url: URL(string: "\(baseURL)/api/live-sessions/chat/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode([
            "sessionId": sessionId.uuidString,
            "clientMessageId": clientMessageId.uuidString,
            "type": "text",
            "text": trimmed,
        ])
        return try await send(request)
    }

    func sendVoice(
        sessionId: UUID,
        clientMessageId: UUID,
        fileURL: URL,
        durationMs: Int
    ) async throws -> SessionChatSendResponse {
        guard (1_000...120_000).contains(durationMs) else {
            throw SessionChatAPIError.invalidMessage("Voice notes must be between 1 and 120 seconds.")
        }
        let audio = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard audio.count <= 4 * 1_024 * 1_024 else {
            throw SessionChatAPIError.invalidMessage("Voice notes must be no larger than 4 MB.")
        }
        let boundary = "WolfGridChat-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipart(name: "sessionId", value: sessionId.uuidString, boundary: boundary)
        body.appendMultipart(name: "clientMessageId", value: clientMessageId.uuidString, boundary: boundary)
        body.appendMultipart(name: "durationMs", value: String(durationMs), boundary: boundary)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"voice\"; filename=\"voice.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "\(baseURL)/api/live-sessions/chat/messages")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request)
    }

    func markRead(sessionId: UUID, lastReadMessageId: String?) async throws -> SessionChatReadResponse {
        var payload = ["sessionId": sessionId.uuidString]
        if let lastReadMessageId { payload["lastReadMessageId"] = lastReadMessageId }
        var request = URLRequest(url: URL(string: "\(baseURL)/api/live-sessions/chat/read")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)
        return try await send(request)
    }

    private func send<T: Decodable>(_ original: URLRequest) async throws -> T {
        let authSession = try await SupabaseManager.shared.client.auth.session
        var request = original
        request.setValue("Bearer \(authSession.accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SessionChatAPIError.server("No connection.")
        }
        guard (200...299).contains(http.statusCode) else {
            let apiError = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error
                ?? "Unable to complete the chat request."
            switch http.statusCode {
            case 401: throw SessionChatAPIError.unauthorized
            case 403: throw SessionChatAPIError.forbidden(apiError)
            case 409: throw SessionChatAPIError.roomEnded(apiError)
            default: throw SessionChatAPIError.server(apiError)
            }
        }
        return try decoder.decode(T.self, from: data)
    }
}

private struct APIErrorBody: Decodable { let error: String }

private extension Data {
    mutating func appendMultipart(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}

