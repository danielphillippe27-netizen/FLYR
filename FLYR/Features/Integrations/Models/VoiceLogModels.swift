import Foundation

// MARK: - Voice Log AI JSON (strict schema from backend)

struct VoiceLogAIContact: Codable, Equatable {
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case email
        case phone
    }
}

struct VoiceLogAIAppointment: Codable, Equatable {
    let title: String
    let startAt: String
    let endAt: String
    let location: String?
    let inviteeEmail: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case location
        case inviteeEmail = "invitee_email"
    }
}

struct VoiceLogAIJson: Codable, Equatable {
    let summary: String
    let outcome: String
    let followUpAt: String?
    let nextAction: String
    let priority: String
    let appointment: VoiceLogAIAppointment?
    let contact: VoiceLogAIContact
    let tags: [String]
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case summary
        case outcome
        case followUpAt = "follow_up_at"
        case nextAction = "next_action"
        case priority
        case appointment
        case contact
        case tags
        case confidence
    }

    var isLowConfidence: Bool { confidence < 0.65 }
}

// MARK: - Voice Log API response

struct VoiceLogFUBResults: Codable, Equatable {
    let personId: Int?
    let noteId: Int?
    let taskId: Int?
    let appointmentId: Int?
    let skippedLowConfidence: Bool?
    let errors: [String]?

    enum CodingKeys: String, CodingKey {
        case personId
        case noteId
        case taskId
        case appointmentId
        case skippedLowConfidence
        case errors
    }
}

struct VoiceLogResponse: Codable {
    let transcript: String
    let aiJson: VoiceLogAIJson?
    let fubResults: VoiceLogFUBResults?

    enum CodingKeys: String, CodingKey {
        case transcript
        case aiJson = "ai_json"
        case fubResults = "fub_results"
    }
}

extension VoiceLogResponse {
    /// Returns true when backend already pushed to FUB (preview sheet can show "Done").
    var alreadyPushedToFUB: Bool {
        guard let r = fubResults else { return false }
        return (r.noteId != nil) && (r.errors?.isEmpty ?? true)
    }
}

struct VoiceLogErrorResponse: Codable {
    let error: String?
    let transcript: String?
    let aiJson: VoiceLogAIJson?
    let fubResults: VoiceLogFUBResults?

    enum CodingKeys: String, CodingKey {
        case error
        case transcript
        case aiJson = "ai_json"
        case fubResults = "fub_results"
    }
}
