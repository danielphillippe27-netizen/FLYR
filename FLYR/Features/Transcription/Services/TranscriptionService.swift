import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - API responses

struct TranscribeResponse: Codable {
    let text: String
    let language: String?
    let summary: TranscriptionSummary?
}

struct SummarizeResponse: Codable {
    let summary: TranscriptionSummary
}

struct SummarizeRequest: Encodable {
    let text: String
    let context: String?
}

// MARK: - Transcription service

final class TranscriptionService: ObservableObject {
    private let baseURL: String
    private let tokenProvider: IdentityTokenProvider
    @Published private(set) var isBusy = false

    private static let maxUploadBytes = 25 * 1024 * 1024 // 25MB
    private static let transcribeTimeout: TimeInterval = 60
    private static let summarizeTimeout: TimeInterval = 30

    init(baseURL: String? = nil, tokenProvider: IdentityTokenProvider = KeychainIdentityTokenProvider()) {
        let url = baseURL ?? (Bundle.main.object(forInfoDictionaryKey: "TRANSCRIPTION_API_URL") as? String) ?? ""
        self.baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tokenProvider = tokenProvider
    }

    /// Returns "Authorization: Bearer <id_token>" for backend. Throws if not signed in or token unavailable.
    func getAuthHeader() async throws -> String {
        let token = try await tokenProvider.currentIdToken()
        return "Bearer \(token)"
    }

    // MARK: - Permissions

    func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func checkSpeechAuthorization() -> SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - On-device transcription (Apple Speech)

    func transcribeWithDevice(audioURL: URL, locale: Locale = .current) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.speechNotAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result else {
                    continuation.resume(throwing: TranscriptionError.speechNoResult)
                    return
                }
                if result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    // MARK: - Backend: improve accuracy (Whisper + summary)

    func improveAccuracy(audioURL: URL, language: String? = nil) async throws -> TranscribeResponse {
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/v1/transcribe") else {
            throw TranscriptionError.invalidURL
        }

        let data = try Data(contentsOf: audioURL)
        if data.count > Self.maxUploadBytes {
            throw TranscriptionError.fileTooLarge
        }

        let authHeader = try await getAuthHeader()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.transcribeTimeout

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        if let lang = language, !lang.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(lang)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw TranscriptionError.unauthorized
        }
        if http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(BackendErrorBody.self, from: responseData))?.error ?? String(data: responseData, encoding: .utf8) ?? "Request failed"
            throw TranscriptionError.backendError(statusCode: http.statusCode, message: message)
        }

        return try JSONDecoder().decode(TranscribeResponse.self, from: responseData)
    }

    // MARK: - Backend: generate summary

    func generateSummary(transcriptText: String, context: String? = nil) async throws -> TranscriptionSummary {
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/v1/summarize") else {
            throw TranscriptionError.invalidURL
        }

        let authHeader = try await getAuthHeader()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Self.summarizeTimeout
        request.httpBody = try JSONEncoder().encode(SummarizeRequest(text: transcriptText, context: context))

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw TranscriptionError.unauthorized
        }
        if http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(BackendErrorBody.self, from: responseData))?.error ?? String(data: responseData, encoding: .utf8) ?? "Request failed"
            throw TranscriptionError.backendError(statusCode: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(SummarizeResponse.self, from: responseData)
        return decoded.summary
    }
}

private struct BackendErrorBody: Codable {
    let error: String?
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case notSignedIn
    case idTokenUnavailable
    case speechNotAvailable
    case speechNoResult
    case invalidURL
    case invalidResponse
    case fileTooLarge
    case unauthorized
    case backendError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to use this feature."
        case .idTokenUnavailable:
            return "Session expired. Please sign in again."
        case .speechNotAvailable:
            return "Speech recognition is not available."
        case .speechNoResult:
            return "No transcript could be generated."
        case .invalidURL:
            return "Transcription service is not configured."
        case .invalidResponse:
            return "Invalid response from server."
        case .fileTooLarge:
            return "Audio file is too large (max 25 MB)."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .backendError(_, let message):
            return message
        }
    }
}
