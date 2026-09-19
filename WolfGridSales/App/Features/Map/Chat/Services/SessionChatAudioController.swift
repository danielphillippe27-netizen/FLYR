import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class SessionChatAudioController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let shared = SessionChatAudioController()

    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var recordingURL: URL?
    @Published private(set) var microphoneDenied = false
    @Published private(set) var playingMessageId: String?
    @Published private(set) var playbackProgress: Double = 0

    private var recorder: AVAudioRecorder?
    private var player: AVPlayer?
    private var recordingTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruptionNotification),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruptionNotification),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func startRecording() async throws {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        let allowed: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: allowed = true
        case .denied: allowed = false
        case .undetermined:
            allowed = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default: allowed = false
        }
        guard allowed else {
            microphoneDenied = true
            throw SessionChatAPIError.invalidMessage("Microphone access is disabled. Enable it in Settings to record a voice note.")
        }
        microphoneDenied = false
        pausePlayback()
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let url = try Self.makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.prepareToRecord()
        guard recorder.record(forDuration: 120) else {
            throw SessionChatAPIError.server("Couldn’t start recording.")
        }
        self.recorder = recorder
        recordingURL = url
        recordingDuration = 0
        isRecording = true
        recordingTask?.cancel()
        recordingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, self.isRecording else { return }
                self.recordingDuration = min(120, self.recorder?.currentTime ?? 0)
                if self.recordingDuration >= 119.9 { self.stopRecording() }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        recordingDuration = min(120, recorder?.currentTime ?? recordingDuration)
        recorder?.stop()
        recorder = nil
        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func discardRecording() {
        stopRecording()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        recordingDuration = 0
    }

    func consumeRecording() -> (URL, Int)? {
        stopRecording()
        guard let url = recordingURL else { return nil }
        let durationMs = Int(recordingDuration * 1_000)
        recordingURL = nil
        recordingDuration = 0
        return (url, durationMs)
    }

    func togglePlayback(messageId: String, remoteURL: URL?, localPath: String?, durationMs: Int?) {
        if playingMessageId == messageId {
            pausePlayback()
            return
        }
        guard let url = localPath.map(URL.init(fileURLWithPath:)) ?? remoteURL else { return }
        pausePlayback()
        let player = AVPlayer(url: url)
        self.player = player
        playingMessageId = messageId
        playbackProgress = 0
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        let fallbackDuration = max(1, Double(durationMs ?? 1_000) / 1_000)
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.playingMessageId == messageId, let player = self.player else { return }
                let current = player.currentTime().seconds
                let actual = player.currentItem?.duration.seconds
                let total = actual?.isFinite == true ? actual! : fallbackDuration
                self.playbackProgress = min(1, max(0, current / max(total, 0.1)))
                if player.timeControlStatus != .playing && self.playbackProgress > 0.98 {
                    self.pausePlayback()
                }
            }
        }
    }

    func pausePlayback() {
        player?.pause()
        player = nil
        playbackTask?.cancel()
        playbackTask = nil
        playingMessageId = nil
        playbackProgress = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleInterruption() {
        if isRecording { stopRecording() }
        pausePlayback()
    }

    @objc private func handleInterruptionNotification() {
        handleInterruption()
    }

    private static func makeRecordingURL() throws -> URL {
        let root = OfflineDatabase.shared.storageDirectory
            .appendingPathComponent("SessionChatVoice", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        return root.appendingPathComponent("\(UUID().uuidString).m4a")
    }
}
