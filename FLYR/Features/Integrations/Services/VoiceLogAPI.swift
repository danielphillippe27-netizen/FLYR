import Foundation
import Supabase

/// Calls FLYR backend POST /api/integrations/fub/voice-log: upload audio, get transcript + AI extraction + FUB push.
@MainActor
final class VoiceLogAPI {
    static let shared = VoiceLogAPI()

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private init() {}

    /// Upload voice recording and get transcript, AI JSON, and FUB results.
    /// - Parameters:
    ///   - audioURL: Local file URL of the recording (e.g. from VoiceRecorderManager).
    ///   - flyrEventId: UUID generated on device when recording started (idempotency).
    ///   - addressId: Campaign address ID.
    ///   - campaignId: Campaign ID.
    ///   - address: Address string for context.
    ///   - leadId: Optional field lead ID if one exists for this address.
    func submitVoiceLog(
        audioURL: URL,
        flyrEventId: UUID,
        addressId: UUID,
        campaignId: UUID,
        address: String,
        leadId: UUID? = nil
    ) async throws -> VoiceLogResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(baseURL)/api/integrations/fub/voice-log")!
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("flyr_event_id", flyrEventId.uuidString)
        appendField("address_id", addressId.uuidString)
        appendField("campaign_id", campaignId.uuidString)
        appendField("address", address)
        appendField("timezone", TimeZone.current.identifier)
        if let leadId = leadId {
            appendField("lead_id", leadId.uuidString)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"voice.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VoiceLogError.network("Invalid response.")
        }

        let decoder = JSONDecoder()

        if http.statusCode == 401 {
            throw VoiceLogError.unauthorized("Not authorized.")
        }
        if http.statusCode == 400 {
            if let err = try? decoder.decode(VoiceLogErrorResponse.self, from: data), let msg = err.error {
                throw VoiceLogError.server(msg)
            }
            throw VoiceLogError.server("Follow Up Boss not connected or invalid request.")
        }
        if http.statusCode == 422 {
            if let err = try? decoder.decode(VoiceLogErrorResponse.self, from: data) {
                throw VoiceLogError.transcription(err.error ?? "Could not transcribe or parse note.")
            }
            throw VoiceLogError.transcription("Could not transcribe or parse note.")
        }
        if http.statusCode == 502 {
            if let err = try? decoder.decode(VoiceLogErrorResponse.self, from: data) {
                throw VoiceLogError.fubPush(err.error ?? "Failed to push to Follow Up Boss.", transcript: err.transcript, aiJson: err.aiJson, fubResults: err.fubResults)
            }
            throw VoiceLogError.server("Failed to push to Follow Up Boss.")
        }
        if !(200...299).contains(http.statusCode) {
            if let err = try? decoder.decode(VoiceLogErrorResponse.self, from: data), let msg = err.error {
                throw VoiceLogError.server(msg)
            }
            throw VoiceLogError.server("Request failed (HTTP \(http.statusCode)).")
        }

        do {
            return try decoder.decode(VoiceLogResponse.self, from: data)
        } catch {
            throw VoiceLogError.server("Invalid response format from server.")
        }
    }
}

enum VoiceLogError: LocalizedError {
    case network(String)
    case unauthorized(String)
    case server(String)
    case transcription(String)
    case fubPush(String, transcript: String?, aiJson: VoiceLogAIJson?, fubResults: VoiceLogFUBResults?)

    var errorDescription: String? {
        switch self {
        case .network(let msg): return msg
        case .unauthorized(let msg): return msg
        case .server(let msg): return msg
        case .transcription(let msg): return msg
        case .fubPush(let msg, _, _, _): return msg
        }
    }
}
