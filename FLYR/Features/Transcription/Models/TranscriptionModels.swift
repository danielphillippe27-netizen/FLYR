import Foundation

// MARK: - Transcript source

enum TranscriptSource: String, Codable {
    case device = "device"
    case highAccuracy = "highAccuracy"

    var badgeLabel: String {
        switch self {
        case .device: return "On-device"
        case .highAccuracy: return "High accuracy"
        }
    }
}

// MARK: - Summary source

enum SummarySource: String, Codable {
    case fromDeviceTranscript = "fromDeviceTranscript"
    case fromHighAccuracyTranscript = "fromHighAccuracyTranscript"
}

// MARK: - Summary model

struct TranscriptionSummary: Codable, Equatable {
    var title: String
    var keyPoints: [String]
    var actionItems: [String]
    var followUps: [String]

    static let empty = TranscriptionSummary(
        title: "",
        keyPoints: [],
        actionItems: [],
        followUps: []
    )
}

// MARK: - Transcription state

struct TranscriptionState {
    var transcriptText: String
    /// Stored when we get device transcript so "Use device transcript" can revert.
    var deviceTranscriptText: String?
    var source: TranscriptSource
    var audioFileURL: URL?
    var createdAt: Date
    var summary: TranscriptionSummary?
    var summarySource: SummarySource?
    var summaryUpdatedAt: Date?
    var isTranscribingDevice: Bool
    var isImprovingAccuracy: Bool
    var isGeneratingSummary: Bool
    var lastError: String?

    static func empty(audioURL: URL? = nil) -> TranscriptionState {
        TranscriptionState(
            transcriptText: "",
            deviceTranscriptText: nil,
            source: .device,
            audioFileURL: audioURL,
            createdAt: Date(),
            summary: nil,
            summarySource: nil,
            summaryUpdatedAt: nil,
            isTranscribingDevice: false,
            isImprovingAccuracy: false,
            isGeneratingSummary: false,
            lastError: nil
        )
    }
}
