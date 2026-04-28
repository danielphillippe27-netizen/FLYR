import Foundation

struct VoiceRoomCredentials: Decodable, Equatable {
    let roomName: String
    let participantIdentity: String
    let participantName: String?
    let liveKitURL: String
    let token: String
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case roomName = "room_name"
        case roomNameCamel = "roomName"
        case participantIdentity = "participant_identity"
        case participantIdentityCamel = "participantIdentity"
        case participantName = "participant_name"
        case participantNameCamel = "participantName"
        case liveKitURL = "livekit_url"
        case liveKitURLCamel = "livekitURL"
        case token
        case expiresInSeconds = "expires_in_seconds"
        case expiresInSecondsCamel = "expiresInSeconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomName = try container.decodeIfPresent(String.self, forKey: .roomName)
            ?? container.decode(String.self, forKey: .roomNameCamel)
        participantIdentity = try container.decodeIfPresent(String.self, forKey: .participantIdentity)
            ?? container.decode(String.self, forKey: .participantIdentityCamel)
        participantName = try container.decodeIfPresent(String.self, forKey: .participantName)
            ?? container.decodeIfPresent(String.self, forKey: .participantNameCamel)
        liveKitURL = try container.decodeIfPresent(String.self, forKey: .liveKitURL)
            ?? container.decode(String.self, forKey: .liveKitURLCamel)
        token = try container.decode(String.self, forKey: .token)
        expiresInSeconds = try container.decodeIfPresent(Int.self, forKey: .expiresInSeconds)
            ?? container.decodeIfPresent(Int.self, forKey: .expiresInSecondsCamel)
            ?? 900
    }
}

enum VoiceMicrophonePermissionState: Equatable {
    case unknown
    case granted
    case denied
}
