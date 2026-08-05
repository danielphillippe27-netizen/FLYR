import Foundation

struct VoiceParticipant: Identifiable, Equatable {
    let id: String
    let initials: String
    var isConnected: Bool
    var isVoiceEnabled: Bool
    var isSpeaking: Bool
    var isLocalUser: Bool
}

enum VoiceParticipantFormatter {
    static func initials(from displayName: String) -> String {
        let parts = displayName
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
        }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "??"
        }

        return String(trimmed.prefix(2)).uppercased()
    }
}
