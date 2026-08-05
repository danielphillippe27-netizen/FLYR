import SwiftUI
import Speech

struct TranscriptionView: View {
    @StateObject private var recorder = VoiceRecorderManager()
    @StateObject private var service = TranscriptionService()
    @State private var state = TranscriptionState.empty()
    @State private var permissionDenied = false
    @State private var permissionMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recordSection
                transcriptSection
                summarySection
                actionsSection
                if let error = state.lastError {
                    errorBanner(error)
                }
            }
            .padding()
        }
        .navigationTitle("Voice note")
        .alert("Permission required", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(permissionMessage)
        }
    }

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording")
                .font(.headline)
            if recorder.isRecording {
                HStack(spacing: 12) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                        .font(.title2)
                    Text("\(Int(recorder.recordingDuration))s")
                        .font(.title3.monospacedDigit())
                    Spacer()
                    Button("Stop") {
                        stopAndTranscribe()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                Button(action: startRecording) {
                    Label("Record", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var transcriptSection: some View {
        Group {
            if !state.transcriptText.isEmpty || state.isTranscribingDevice || state.isImprovingAccuracy || state.isGeneratingSummary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Transcript")
                            .font(.headline)
                        Spacer()
                        Text(state.source.badgeLabel)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(state.source == .highAccuracy ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                            .cornerRadius(6)
                    }
                    if state.isTranscribingDevice {
                        ProgressView("Transcribing…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if state.isImprovingAccuracy {
                        ProgressView("Improving accuracy…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if state.isGeneratingSummary {
                        ProgressView("Generating summary…")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(state.transcriptText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.08))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        Group {
            if let summary = state.summary, !summary.title.isEmpty || !summary.keyPoints.isEmpty || !summary.actionItems.isEmpty || !summary.followUps.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Summary")
                        .font(.headline)
                    if !summary.title.isEmpty {
                        Text(summary.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    if !summary.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Key points")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            ForEach(summary.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                    Text(point)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    if !summary.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Action items")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            ForEach(summary.actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                    Text(item)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    if !summary.followUps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Follow-ups / names mentioned")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            ForEach(summary.followUps, id: \.self) { follow in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                    Text(follow)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.06))
                .cornerRadius(12)
            }
        }
    }

    private var actionsSection: some View {
        Group {
            if !state.transcriptText.isEmpty && state.audioFileURL != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button("Improve accuracy") {
                            improveAccuracy()
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isImprovingAccuracy || state.isGeneratingSummary || state.isTranscribingDevice)

                        Button("Use device transcript") {
                            revertToDeviceTranscript()
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.source == .device || state.deviceTranscriptText == nil)

                        Button("Generate summary") {
                            generateSummary()
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.transcriptText.isEmpty || state.isGeneratingSummary || state.isImprovingAccuracy || state.isTranscribingDevice)
                    }
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Dismiss") {
                state.lastError = nil
            }
            .font(.caption)
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .cornerRadius(8)
    }

    private func startRecording() {
        Task {
            let mic = await recorder.requestPermission()
            guard mic else {
                permissionMessage = "Microphone access is required to record."
                permissionDenied = true
                return
            }
            let speech = await service.requestSpeechPermission()
            guard speech else {
                permissionMessage = "Speech recognition is required for on-device transcription."
                permissionDenied = true
                return
            }
            _ = recorder.startRecording()
        }
    }

    private func stopAndTranscribe() {
        guard let url = recorder.stopRecording() else { return }
        state.audioFileURL = url
        state.createdAt = Date()
        state.lastError = nil
        state.transcriptText = ""
        state.deviceTranscriptText = nil
        state.source = .device
        state.summary = nil
        state.summarySource = nil
        state.summaryUpdatedAt = nil
        state.isTranscribingDevice = true

        Task {
            do {
                let text = try await service.transcribeWithDevice(audioURL: url)
                await MainActor.run {
                    state.transcriptText = text
                    state.deviceTranscriptText = text
                    state.source = .device
                    state.isTranscribingDevice = false
                }
            } catch {
                await MainActor.run {
                    state.lastError = error.localizedDescription
                    state.isTranscribingDevice = false
                }
            }
        }
    }

    private func improveAccuracy() {
        guard let url = state.audioFileURL else { return }
        state.isImprovingAccuracy = true
        state.lastError = nil

        Task {
            do {
                let response = try await service.improveAccuracy(audioURL: url)
                await MainActor.run {
                    state.transcriptText = response.text
                    state.source = .highAccuracy
                    if let s = response.summary {
                        state.summary = s
                        state.summarySource = .fromHighAccuracyTranscript
                        state.summaryUpdatedAt = Date()
                    }
                    state.isImprovingAccuracy = false
                }
            } catch {
                await MainActor.run {
                    state.lastError = error.localizedDescription
                    state.isImprovingAccuracy = false
                    // Keep existing device transcript on failure
                }
            }
        }
    }

    private func revertToDeviceTranscript() {
        if let device = state.deviceTranscriptText {
            state.transcriptText = device
        }
        state.source = .device
        state.summarySource = state.summary != nil ? .fromDeviceTranscript : nil
    }

    private func generateSummary() {
        guard !state.transcriptText.isEmpty else { return }
        state.isGeneratingSummary = true
        state.lastError = nil

        Task {
            do {
                let summary = try await service.generateSummary(transcriptText: state.transcriptText)
                await MainActor.run {
                    state.summary = summary
                    state.summarySource = state.source == .highAccuracy ? .fromHighAccuracyTranscript : .fromDeviceTranscript
                    state.summaryUpdatedAt = Date()
                    state.isGeneratingSummary = false
                }
            } catch {
                await MainActor.run {
                    state.lastError = error.localizedDescription
                    state.isGeneratingSummary = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TranscriptionView()
    }
}
