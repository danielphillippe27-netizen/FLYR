import Foundation
import AVFoundation
import Combine
import UIKit
import LiveKit

@MainActor
final class LiveSessionVoiceService: NSObject, ObservableObject {
    static let shared = LiveSessionVoiceService()

    @Published private(set) var connectionState: VoiceConnectionState = .idle
    @Published private(set) var participants: [VoiceParticipant] = []
    @Published private(set) var isTransmitting = false
    @Published private(set) var microphonePermission: VoiceMicrophonePermissionState = .unknown
    @Published private(set) var activeCampaignId: UUID?
    @Published private(set) var activeSessionId: UUID?
    @Published private(set) var lastErrorMessage: String?

    private var room: Room?
    private var reconnectTask: Task<Void, Never>?
    private var currentCredentials: VoiceRoomCredentials?
    private var didRequestDisconnect = false
    private var notificationObservers: [NSObjectProtocol] = []

    var shouldShowOverlay: Bool {
        activeSessionId != nil || connectionState != .idle || isTransmitting
    }

    private override init() {
        super.init()
        registerLifecycleObservers()
    }

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func connectIfNeeded(campaignId: UUID, sessionId: UUID) async {
        if activeCampaignId == campaignId,
           activeSessionId == sessionId,
           connectionState == .connected || connectionState == .connecting || connectionState == .reconnecting {
            return
        }

        reconnectTask?.cancel()
        didRequestDisconnect = false
        activeCampaignId = campaignId
        activeSessionId = sessionId
        connectionState = .connecting
        lastErrorMessage = nil

        if let existingRoom = room {
            await existingRoom.disconnect()
            room = nil
        }

        do {
            let credentials = try await LiveSessionVoiceAPI.shared.joinSessionVoice(
                sessionId: sessionId,
                campaignId: campaignId
            )
            currentCredentials = credentials

            let newRoom = Room(
                delegate: self,
                connectOptions: ConnectOptions(
                    autoSubscribe: true,
                    enableMicrophone: false
                ),
                roomOptions: RoomOptions()
            )
            room = newRoom

            try await newRoom.connect(
                url: credentials.liveKitURL,
                token: credentials.token,
                connectOptions: ConnectOptions(autoSubscribe: true, enableMicrophone: false),
                roomOptions: RoomOptions()
            )

            _ = try? await newRoom.localParticipant.setMicrophone(enabled: false)
            isTransmitting = false
            connectionState = .connected
            syncParticipants()
        } catch {
            connectionState = .failed
            lastErrorMessage = error.localizedDescription
            participants = []
        }
    }

    func disconnect() async {
        didRequestDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        await endPushToTalk()
        preserveParticipantDisplayStateForLocalDisconnect()

        if let room {
            await room.disconnect()
        }

        room = nil
        currentCredentials = nil
        activeCampaignId = nil
        activeSessionId = nil
        connectionState = .idle
        lastErrorMessage = nil
    }

    func beginPushToTalk() async {
        guard connectionState.allowsTransmit, let room else { return }

        let granted = await ensureMicrophonePermission()
        guard granted else {
            lastErrorMessage = "Microphone access is required for push-to-talk."
            return
        }

        do {
            try await room.localParticipant.setMicrophone(enabled: true)
            isTransmitting = true
            lastErrorMessage = nil
            HapticManager.rigid()
            syncParticipants()
        } catch {
            lastErrorMessage = "Couldn't start transmitting."
            isTransmitting = false
        }
    }

    func endPushToTalk() async {
        guard let room else {
            isTransmitting = false
            return
        }

        do {
            try await room.localParticipant.setMicrophone(enabled: false)
        } catch {
            print("⚠️ [LiveSessionVoice] Failed to mute local mic: \(error)")
        }

        isTransmitting = false
        syncParticipants()
    }

    func beginPushToTalk(campaignId: UUID?, sessionId: UUID?) async {
        if !connectionState.allowsTransmit {
            guard let campaignId, let sessionId else { return }
            await connectIfNeeded(campaignId: campaignId, sessionId: sessionId)
        }

        await beginPushToTalk()
    }

    private func ensureMicrophonePermission() async -> Bool {
        switch microphonePermission {
        case .granted:
            return true
        case .denied:
            return false
        case .unknown:
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
            microphonePermission = granted ? .granted : .denied
            return granted
        }
    }

    private func scheduleReconnectIfNeeded() {
        guard !didRequestDisconnect,
              let campaignId = activeCampaignId,
              let sessionId = activeSessionId else { return }
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.connectIfNeeded(campaignId: campaignId, sessionId: sessionId)
        }
    }

    private func syncParticipants() {
        guard let room else {
            participants = []
            return
        }

        var nextParticipants: [VoiceParticipant] = []

        if let identity = room.localParticipant.identity?.stringValue {
            nextParticipants.append(
                VoiceParticipant(
                    id: identity,
                    initials: VoiceParticipantFormatter.initials(from: room.localParticipant.name ?? "You"),
                    isConnected: true,
                    isVoiceEnabled: true,
                    isSpeaking: room.localParticipant.isSpeaking || isTransmitting,
                    isLocalUser: true
                )
            )
        }

        let remote = room.remoteParticipants.values
            .map { participant in
                (
                    name: participant.name ?? "Rep",
                    participant: VoiceParticipant(
                        id: participant.identity?.stringValue ?? UUID().uuidString,
                        initials: VoiceParticipantFormatter.initials(from: participant.name ?? "Rep"),
                        isConnected: true,
                        isVoiceEnabled: true,
                        isSpeaking: participant.isSpeaking,
                        isLocalUser: false
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.participant.isSpeaking != rhs.participant.isSpeaking {
                    return lhs.participant.isSpeaking && !rhs.participant.isSpeaking
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map(\.participant)

        nextParticipants.append(contentsOf: remote)
        participants = nextParticipants
    }

    private func preserveParticipantDisplayStateForLocalDisconnect() {
        guard !participants.isEmpty else { return }

        participants = participants.map { participant in
            var next = participant
            if participant.isLocalUser {
                next.isConnected = false
                next.isVoiceEnabled = false
                next.isSpeaking = false
            }
            return next
        }
    }

    private func registerLifecycleObservers() {
        let center = NotificationCenter.default

        notificationObservers.append(
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.endPushToTalk() }
            }
        )

        notificationObservers.append(
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.endPushToTalk() }
            }
        )
    }
}

extension LiveSessionVoiceService: @preconcurrency RoomDelegate {
    func roomDidConnect(_ room: Room) {
        Task { @MainActor in
            connectionState = .connected
            lastErrorMessage = nil
            syncParticipants()
        }
    }

    func room(_ room: Room, didUpdateConnectionState connectionState: LiveKit.ConnectionState, from oldConnectionState: LiveKit.ConnectionState) {
        Task { @MainActor in
            switch connectionState {
            case .connected:
                self.connectionState = .connected
            case .connecting:
                self.connectionState = .connecting
            case .reconnecting:
                self.connectionState = .reconnecting
            case .disconnected, .disconnecting:
                self.connectionState = didRequestDisconnect ? .idle : .failed
                if !didRequestDisconnect {
                    scheduleReconnectIfNeeded()
                }
            @unknown default:
                self.connectionState = .failed
            }
            syncParticipants()
        }
    }

    func roomIsReconnecting(_ room: Room) {
        Task { @MainActor in
            connectionState = .reconnecting
            syncParticipants()
        }
    }

    func roomDidReconnect(_ room: Room) {
        Task { @MainActor in
            connectionState = .connected
            syncParticipants()
        }
    }

    func room(_ room: Room, didFailToConnectWithError error: LiveKitError?) {
        Task { @MainActor in
            connectionState = .failed
            lastErrorMessage = error?.localizedDescription ?? "Voice unavailable."
            participants = []
        }
    }

    func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            isTransmitting = false
            if didRequestDisconnect {
                connectionState = .idle
                return
            }
            connectionState = .failed
            lastErrorMessage = error?.localizedDescription ?? "Voice disconnected."
            syncParticipants()
            scheduleReconnectIfNeeded()
        }
    }

    func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            syncParticipants()
        }
    }

    func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            syncParticipants()
        }
    }

    func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor in
            syncParticipants()
        }
    }
}
