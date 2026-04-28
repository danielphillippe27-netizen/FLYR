import Foundation

enum VoiceConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case failed

    var statusLabel: String {
        switch self {
        case .idle:
            return "Voice Off"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting"
        case .failed:
            return "Voice Unavailable"
        }
    }

    var allowsTransmit: Bool {
        self == .connected
    }
}
