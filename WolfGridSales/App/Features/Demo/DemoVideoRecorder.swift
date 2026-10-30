import Foundation
import ReplayKit
import Photos

/// Records the app's demo playback and saves the resulting movie to Photos.
@MainActor
final class DemoVideoRecorder {
    static var lastResult: String?
    private var recording = false

    func start() async throws {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable, !recorder.isRecording else {
            throw NSError(domain: "DemoVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video recording is unavailable or another recording is already running."])
        }
        recorder.isMicrophoneEnabled = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startRecording { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        recording = true
    }

    func cancel() {
        guard recording else { return }
        recording = false
        RPScreenRecorder.shared().stopRecording { _, _ in }
    }

    func finish() async -> String {
        guard recording else { return "No replay video was recorded." }
        recording = false
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wolfgrid-replay-\(UUID().uuidString).mp4")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                return "Photos access was denied. The replay could not be saved."
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            try? FileManager.default.removeItem(at: url)
            return "Replay saved to Photos"
        } catch {
            return "Could not save replay: \(error.localizedDescription)"
        }
    }
}
