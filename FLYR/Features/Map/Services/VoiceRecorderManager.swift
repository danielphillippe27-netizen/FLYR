import Foundation
import AVFoundation
import Combine

/// Records voice notes to a temporary m4a file for the Zero-Typing pipeline.
final class VoiceRecorderManager: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var permissionGranted: Bool?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startTime: Date?

    override init() {
        super.init()
    }

    /// Request microphone permission and return true if granted.
    func requestPermission() async -> Bool {
        let granted: Bool = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        await MainActor.run {
            self.permissionGranted = granted
        }
        return granted
    }

    /// Start recording to a temporary m4a file. Returns false if permission denied or setup fails.
    func startRecording() -> Bool {
        guard !isRecording else { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("⚠️ [VoiceRecorder] Session setup failed: \(error)")
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.prepareToRecord()
            recorder?.record()
            startTime = Date()
            recordingDuration = 0
            timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(handleTimerTick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer!, forMode: .common)
            isRecording = true
            return true
        } catch {
            print("⚠️ [VoiceRecorder] Start failed: \(error)")
            return false
        }
    }

    /// Stop recording and return the file URL, or nil if not recording or no file.
    func stopRecording() -> URL? {
        guard isRecording, let rec = recorder else { return nil }
        timer?.invalidate()
        timer = nil
        let url = rec.url
        rec.stop()
        recorder = nil
        startTime = nil
        isRecording = false
        recordingDuration = 0
        return url
    }

    @objc private func handleTimerTick() {
        guard let start = startTime else { return }
        recordingDuration = Date().timeIntervalSince(start)
    }
}
