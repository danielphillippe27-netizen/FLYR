import Foundation
import Supabase

/// Response from process-voice-note Edge Function on success.
struct VoiceNoteResult: Codable {
    let contactName: String?
    let leadStatus: String?
    let productInterest: String?
    let followUpDate: String?
    let aiSummary: String?
    let rawTranscript: String?

    enum CodingKeys: String, CodingKey {
        case contactName = "contact_name"
        case leadStatus = "lead_status"
        case productInterest = "product_interest"
        case followUpDate = "follow_up_date"
        case aiSummary = "ai_summary"
        case rawTranscript = "raw_transcript"
    }
}

/// Error response from Edge Function.
struct VoiceNoteErrorResponse: Codable {
    let error: String?
}

/// Calls the process-voice-note Edge Function: uploads audio, returns extracted data or error message.
/// (Currently unused: voice notes use on-device Apple transcription and save locally.)
enum VoiceNoteAPI {
    /// Save a voice note transcript to campaign_addresses (on-device flow; no Whisper/GPT).
    static func saveVoiceNoteToCampaign(transcript: String, addressId: UUID, campaignId: UUID) async throws {
        let client = SupabaseManager.shared.client
        let updateData: [String: AnyCodable] = [
            "raw_transcript": AnyCodable(transcript),
            "ai_summary": AnyCodable(transcript)
        ]
        _ = try await client
            .from("campaign_addresses")
            .update(updateData)
            .eq("id", value: addressId.uuidString)
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
    }

    static func processVoiceNote(
        audioFileURL: URL,
        addressId: UUID,
        campaignId: UUID
    ) async throws -> VoiceNoteResult {
        let session = try await SupabaseManager.shared.client.auth.session
        let base = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        guard let functionsURL = URL(string: "\(base)/functions/v1/process-voice-note") else {
            throw VoiceNoteError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: functionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioFileURL)
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"address_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(addressId.uuidString)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"campaign_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(campaignId.uuidString)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"voice.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        if let http = http, http.statusCode != 200 {
            let errorMessage = (try? JSONDecoder().decode(VoiceNoteErrorResponse.self, from: data))?.error
                ?? "Could not parse note, please try again."
            throw VoiceNoteError.serverError(statusCode: http.statusCode, message: errorMessage)
        }

        if let errResp = try? JSONDecoder().decode(VoiceNoteErrorResponse.self, from: data), let msg = errResp.error, !msg.isEmpty {
            throw VoiceNoteError.serverError(statusCode: 422, message: msg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(VoiceNoteResult.self, from: data)
    }
}

enum VoiceNoteError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request URL"
        case .serverError(_, let message): return message
        }
    }
}
