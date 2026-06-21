import AVFoundation
import CallKit
import Combine
import Foundation
import PushKit
import Supabase
import TelnyxRTC
import UIKit

struct SalespersonAudioRouteOption: Identifiable, Equatable {
    enum Kind: Equatable {
        case iPhone
        case speaker
        case bluetooth(inputUID: String)
    }

    let id: String
    let title: String
    let systemImage: String
    let kind: Kind
}

@MainActor
final class SalespersonVoiceCallService: NSObject, ObservableObject {
    static let shared = SalespersonVoiceCallService()

    @Published private(set) var activeCallLabel: String?
    @Published private(set) var registrationError: String?
    @Published private(set) var isRegisteredForIncomingCalls = false
    @Published private(set) var callPhase: VoiceCallPhase = .idle
    @Published private(set) var callStartedAt: Date?
    @Published private(set) var callConnectedAt: Date?
    @Published private(set) var isMuted = false
    @Published private(set) var audioRouteOptions: [SalespersonAudioRouteOption] = []
    @Published private(set) var selectedAudioRouteId: String = "iphone"

    private let client = SupabaseManager.shared.client
    private let callController = CXCallController()
    private let provider: CXProvider
    private let telnyxClient = TxClient()
    private var pushRegistry: PKPushRegistry?
    private var voipDeviceToken: Data?
    private var lastRegisteredDeviceToken: Data?
    private var lastRegisteredIdentity: String?
    private var lastRegisteredToken: String?
    private var isRegistering = false
    private var isConnectingClient = false
    private var activeCalls: [UUID: Call] = [:]
    private var pendingClientReadyContinuations: [CheckedContinuation<Void, Error>] = []
    private var pendingPushCompletion: (() -> Void)?

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "FLYR")
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportsVideo = false
        configuration.supportedHandleTypes = [.generic, .phoneNumber]
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
        telnyxClient.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioRouteDidChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        refreshAudioRoutes()
    }

    func start() {
        guard pushRegistry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        pushRegistry = registry
    }

    func refreshRegistrationIfNeeded(force: Bool = false) async {
        start()
        guard !isRegistering else { return }
        guard WorkspaceContext.shared.isSalespersonDashboardEnabled,
              WorkspaceContext.shared.workspaceId != nil else {
            return
        }

        isRegistering = true
        defer { isRegistering = false }

        do {
            let tokenResponse = try await fetchVoiceToken()
            guard force ||
                    lastRegisteredDeviceToken != voipDeviceToken ||
                    lastRegisteredIdentity != tokenResponse.identity ||
                    lastRegisteredToken != tokenResponse.token ||
                    !telnyxClient.isRegistered else {
                return
            }

            try await connect(tokenResponse: tokenResponse)
            lastRegisteredDeviceToken = voipDeviceToken
            lastRegisteredIdentity = tokenResponse.identity
            lastRegisteredToken = tokenResponse.token
            isRegisteredForIncomingCalls = true
            registrationError = tokenResponse.voipPushConfigured
                ? nil
                : "Telnyx iOS push credential is not confirmed. Outbound calls work, but background incoming calls require Telnyx APNs setup."
        } catch {
            isRegisteredForIncomingCalls = false
            registrationError = error.localizedDescription
            #if DEBUG
            print("Telnyx voice registration failed: \(error.localizedDescription)")
            #endif
        }
    }

    func endActiveCall() {
        guard let uuid = activeCalls.keys.first else { return }
        requestEndCall(uuid: uuid)
    }

    func startOutboundCall(
        label: String,
        callRequestId: String,
        destinationNumber: String? = nil,
        fromNumber: String? = nil
    ) async throws {
        try await prepareMicrophoneForCall()
        let tokenResponse = try await fetchVoiceToken()
        let destination = destinationNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !destination.isEmpty else {
            throw VoiceCallError.status(400, "A destination phone number is required for Telnyx iOS calling.")
        }

        try await connect(tokenResponse: tokenResponse)

        let uuid = UUID(uuidString: callRequestId) ?? UUID()
        let handle = CXHandle(type: .generic, value: label)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = false

        try await request(transaction: CXTransaction(action: startAction))

        activeCallLabel = label
        callPhase = .connecting
        callStartedAt = Date()
        callConnectedAt = nil
        isMuted = false
        provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())

        let call = try telnyxClient.newCall(
            callerName: "FLYR",
            callerNumber: fromNumber ?? tokenResponse.fromNumber ?? "",
            destinationNumber: destination,
            callId: uuid,
            clientState: makeTelnyxClientState(callRequestId: callRequestId, to: destination, from: fromNumber ?? tokenResponse.fromNumber),
            customHeaders: [
                "X-Call-Request-Id": callRequestId
            ],
            debug: false
        )
        activeCalls[uuid] = call
    }

    func setMuted(_ muted: Bool) {
        guard let uuid = activeCalls.keys.first else { return }
        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        callController.request(CXTransaction(action: action)) { error in
            #if DEBUG
            if let error {
                print("Mute request failed: \(error.localizedDescription)")
            }
            #endif
        }
    }

    func sendDTMF(_ digit: String) throws {
        let value = digit.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowedDigits = Set("0123456789*#ABCD")
        guard value.count == 1,
              let character = value.first,
              allowedDigits.contains(character) else {
            throw VoiceCallError.status(400, "Use one keypad digit at a time.")
        }
        guard let call = activeCalls.values.first else {
            throw VoiceCallError.status(400, "Start a call before using the keypad.")
        }
        guard callPhase == .connected else {
            throw VoiceCallError.status(400, "Wait for the call to connect before entering digits.")
        }
        call.dtmf(dtmf: value)
    }

    func refreshAudioRoutes() {
        let session = AVAudioSession.sharedInstance()
        var options: [SalespersonAudioRouteOption] = [
            SalespersonAudioRouteOption(
                id: "iphone",
                title: "iPhone",
                systemImage: "iphone",
                kind: .iPhone
            ),
            SalespersonAudioRouteOption(
                id: "speaker",
                title: "Speaker",
                systemImage: "speaker.wave.2.fill",
                kind: .speaker
            )
        ]

        let bluetoothInputs = (session.availableInputs ?? [])
            .filter { input in
                input.portType == .bluetoothHFP ||
                input.portType == .bluetoothA2DP ||
                input.portType == .bluetoothLE
            }
        for input in bluetoothInputs {
            options.append(
                SalespersonAudioRouteOption(
                    id: "bluetooth-\(input.uid)",
                    title: input.portName,
                    systemImage: "headphones",
                    kind: .bluetooth(inputUID: input.uid)
                )
            )
        }

        audioRouteOptions = options

        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInSpeaker }) {
            selectedAudioRouteId = "speaker"
        } else if let bluetoothInput = session.currentRoute.inputs.first(where: { input in
            input.portType == .bluetoothHFP ||
            input.portType == .bluetoothA2DP ||
            input.portType == .bluetoothLE
        }) {
            selectedAudioRouteId = "bluetooth-\(bluetoothInput.uid)"
        } else {
            selectedAudioRouteId = "iphone"
        }
    }

    func selectAudioRoute(_ option: SalespersonAudioRouteOption) {
        do {
            let session = AVAudioSession.sharedInstance()
            try configureVoiceAudioSession()

            switch option.kind {
            case .speaker:
                try session.setPreferredInput(nil)
                try session.overrideOutputAudioPort(.speaker)
            case .iPhone:
                if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtInMic)
                } else {
                    try session.setPreferredInput(nil)
                }
                try session.overrideOutputAudioPort(.none)
            case .bluetooth(let inputUID):
                guard let bluetoothInput = session.availableInputs?.first(where: { $0.uid == inputUID }) else {
                    throw VoiceCallError.status(400, "That audio route is no longer available.")
                }
                try session.overrideOutputAudioPort(.none)
                try session.setPreferredInput(bluetoothInput)
            }

            refreshAudioRoutes()
        } catch {
            registrationError = "Unable to switch audio route: \(error.localizedDescription)"
        }
    }

    private func fetchVoiceToken() async throws -> VoiceTokenResponse {
        guard let workspaceId = WorkspaceContext.shared.workspaceId else {
            throw VoiceCallError.missingWorkspace
        }
        guard var components = URLComponents(
            url: Config.backendAPIURL.appendingPathComponent("api/dialer/token"),
            resolvingAgainstBaseURL: false
        ) else {
            throw VoiceCallError.badURL
        }
        components.queryItems = [
            URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "tabId", value: "ios")
        ]
        guard let url = components.url else { throw VoiceCallError.badURL }
        guard let session = try? await client.auth.session else {
            throw VoiceCallError.status(401, "Sign in again to enable voice calling.")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let message = decodeTokenErrorMessage(from: data) ?? "Unable to get Telnyx voice token."
            throw VoiceCallError.status(http.statusCode, message)
        }

        do {
            let decoder = JSONDecoder.supabaseDates
            let tokenResponse = try decoder.decode(VoiceTokenResponse.self, from: data)
            if let provider = tokenResponse.provider, provider != "telnyx" {
                throw VoiceCallError.status(
                    400,
                    "Native iOS calling requires Telnyx. Backend returned \(provider)."
                )
            }
            guard tokenResponse.sdkTarget == nil || tokenResponse.sdkTarget == "telnyx-ios" else {
                throw VoiceCallError.status(400, "Backend returned a voice token for \(tokenResponse.sdkTarget ?? "another SDK").")
            }
            guard tokenResponse.requiresTelnyxVoiceSdk != false else {
                throw VoiceCallError.status(400, "Backend did not return a Telnyx iOS voice token.")
            }
            guard !tokenResponse.token.isEmpty else {
                throw VoiceCallError.status(500, "Telnyx token response did not include a token.")
            }
            try validateTelnyxToken(tokenResponse.token)
            return tokenResponse
        } catch let error as VoiceCallError {
            throw error
        } catch {
            #if DEBUG
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            print("Telnyx token decode failed. Body: \(body)")
            #endif
            throw VoiceCallError.status(500, "Telnyx token response was incomplete.")
        }
    }

    private func decodeTokenErrorMessage(from data: Data) -> String? {
        struct ErrorPayload: Decodable {
            let error: String?
            let message: String?
        }
        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           let message = [
            payload.error?.trimmingCharacters(in: .whitespacesAndNewlines),
            payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
           ].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            return message
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty, raw.count <= 240 else { return nil }
        let lowercasedRaw = raw.lowercased()
        guard !lowercasedRaw.contains("\"token\""), !raw.contains("eyJ") else { return nil }
        return raw
    }

    private func validateTelnyxToken(_ token: String) throws {
        guard let payload = TelnyxTokenPayload(token: token) else {
            throw VoiceCallError.status(500, "Backend returned an invalid Telnyx voice token.")
        }

        if let invalidReason = payload.telnyxAccessTokenInvalidReason {
            throw VoiceCallError.status(
                500,
                "Backend returned an invalid Telnyx voice token (\(invalidReason)). Check /api/dialer/token configuration."
            )
        }
    }

    private func connect(tokenResponse: VoiceTokenResponse) async throws {
        if telnyxClient.isRegistered, !isConnectingClient {
            return
        }

        if isConnectingClient {
            try await waitForClientReady()
            return
        }

        isConnectingClient = true
        let txConfig = makeTxConfig(tokenResponse: tokenResponse)
        do {
            try telnyxClient.connect(txConfig: txConfig)
            try await waitForClientReady()
        } catch {
            isConnectingClient = false
            pendingClientReadyContinuations.forEach { $0.resume(throwing: error) }
            pendingClientReadyContinuations.removeAll()
            throw error
        }
    }

    private func waitForClientReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingClientReadyContinuations.append(continuation)
        }
    }

    private func resolveClientReady() {
        isConnectingClient = false
        let continuations = pendingClientReadyContinuations
        pendingClientReadyContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func rejectClientReady(error: Error) {
        isConnectingClient = false
        let continuations = pendingClientReadyContinuations
        pendingClientReadyContinuations.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func makeTxConfig(tokenResponse: VoiceTokenResponse) -> TxConfig {
        TxConfig(
            token: tokenResponse.token,
            pushDeviceToken: voipDeviceToken?.telnyxHexString,
            pushEnvironment: telnyxPushEnvironment,
            enableMissedCallNotifications: true,
            logLevel: .none,
            reconnectClient: true,
            debug: false,
            forceRelayCandidate: false,
            enableQualityMetrics: false,
            sendWebRTCStatsViaSocket: false,
            reconnectTimeOut: 60,
            useTrickleIce: true
        )
    }

    private func prepareMicrophoneForCall() async throws {
        let granted = await requestMicrophonePermission()
        guard granted else {
            throw VoiceCallError.microphoneDenied
        }
        try configureVoiceAudioSession()
    }

    private func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }

        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureVoiceAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP, .allowAirPlay]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        refreshAudioRoutes()
    }

    @objc private func audioRouteDidChange() {
        refreshAudioRoutes()
    }

    private var telnyxPushEnvironment: PushEnvironment {
        #if DEBUG
        return .debug
        #else
        return .production
        #endif
    }

    private func makeTelnyxClientState(callRequestId: String, to: String?, from: String?) -> String? {
        let payload = TelnyxClientState(
            callRequestId: callRequestId,
            callRequestSnakeId: callRequestId,
            role: "lead",
            direction: "outbound",
            to: to,
            from: from
        )
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return data.base64EncodedString()
    }

    private func reportIncomingCall(call: Call) {
        guard let uuid = call.callInfo?.callId else { return }
        let from = incomingLabel(for: call)
        activeCalls[uuid] = call
        activeCallLabel = from
        callPhase = .connecting
        callStartedAt = Date()
        callConnectedAt = nil
        isMuted = call.isMuted

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: from)
        update.localizedCallerName = from
        update.supportsDTMF = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.hasVideo = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            Task { @MainActor in
                if let error {
                    self.registrationError = error.localizedDescription
                    self.activeCalls.removeValue(forKey: uuid)
                    self.callPhase = self.activeCalls.isEmpty ? .idle : self.callPhase
                }
                self.completePendingPushIfNeeded()
            }
        }
    }

    private func incomingLabel(for call: Call) -> String {
        let callerName = call.callInfo?.callerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let callerNumber = call.callInfo?.callerNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let callerName, !callerName.isEmpty { return callerName.replacingOccurrences(of: "client:", with: "") }
        if let callerNumber, !callerNumber.isEmpty { return callerNumber.replacingOccurrences(of: "client:", with: "") }
        return "Incoming FLYR call"
    }

    private func request(transaction: CXTransaction) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            callController.request(transaction) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func requestEndCall(uuid: UUID) {
        let action = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: action)) { error in
            #if DEBUG
            if let error {
                print("End call request failed: \(error.localizedDescription)")
            }
            #endif
        }
    }

    private func completePendingPushIfNeeded() {
        pendingPushCompletion?()
        pendingPushCompletion = nil
    }

    private func clearCall(uuid: UUID) {
        activeCalls.removeValue(forKey: uuid)
        if activeCalls.isEmpty {
            activeCallLabel = nil
            callPhase = .idle
            callStartedAt = nil
            callConnectedAt = nil
            isMuted = false
        }
    }
}

extension SalespersonVoiceCallService: PKPushRegistryDelegate {
    func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        voipDeviceToken = pushCredentials.token
        Task { await refreshRegistrationIfNeeded(force: true) }
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }
        voipDeviceToken = nil
        lastRegisteredDeviceToken = nil
        isRegisteredForIncomingCalls = false
        if telnyxClient.isConnected() {
            telnyxClient.disablePushNotifications()
        }
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        pendingPushCompletion = completion
        Task {
            do {
                let tokenResponse = try await fetchVoiceToken()
                guard let metadata = payload.dictionaryPayload["metadata"] as? [String: Any] else {
                    completePendingPushIfNeeded()
                    return
                }
                try telnyxClient.processVoIPNotification(
                    txConfig: makeTxConfig(tokenResponse: tokenResponse),
                    serverConfiguration: TxServerConfiguration(pushMetaData: metadata),
                    pushMetaData: metadata
                )
                reportIncomingPushPlaceholder(metadata: metadata)
            } catch {
                registrationError = error.localizedDescription
                completePendingPushIfNeeded()
            }
        }
    }

    private func reportIncomingPushPlaceholder(metadata: [String: Any]) {
        guard let callId = metadata["call_id"] as? String,
              let uuid = UUID(uuidString: callId) else {
            completePendingPushIfNeeded()
            return
        }

        let callerName = (metadata["caller_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let callerNumber = (metadata["caller_number"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let caller = callerName?.isEmpty == false ? callerName! : callerNumber?.isEmpty == false ? callerNumber! : "Incoming FLYR call"

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: caller)
        update.localizedCallerName = caller
        update.supportsDTMF = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.hasVideo = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            Task { @MainActor in
                if let error {
                    self.registrationError = error.localizedDescription
                }
                self.completePendingPushIfNeeded()
            }
        }
    }
}

extension SalespersonVoiceCallService: TxClientDelegate {
    func onSocketConnected() {}

    func onSocketDisconnected() {
        isRegisteredForIncomingCalls = false
    }

    func onClientError(error: Error) {
        registrationError = error.localizedDescription
        rejectClientReady(error: error)
    }

    func onClientReady() {
        isRegisteredForIncomingCalls = true
        resolveClientReady()
    }

    func onPushDisabled(success: Bool, message: String) {
        if success {
            isRegisteredForIncomingCalls = false
        } else {
            registrationError = message
        }
    }

    func onSessionUpdated(sessionId: String) {}

    func onCallStateUpdated(callState: CallState, callId: UUID) {
        switch callState {
        case .NEW, .CONNECTING, .RINGING:
            if callStartedAt == nil {
                callStartedAt = Date()
            }
            callPhase = .connecting
        case .ACTIVE, .HELD:
            if callStartedAt == nil {
                callStartedAt = Date()
            }
            if callConnectedAt == nil {
                callConnectedAt = Date()
            }
            callPhase = .connected
            if let call = activeCalls[callId] {
                isMuted = call.isMuted
            }
            provider.reportOutgoingCall(with: callId, connectedAt: Date())
        case .DONE:
            provider.reportCall(with: callId, endedAt: Date(), reason: .remoteEnded)
            clearCall(uuid: callId)
            callPhase = .ended
        case .RECONNECTING, .DROPPED:
            callPhase = .connecting
        }
    }

    func onIncomingCall(call: Call) {
        reportIncomingCall(call: call)
    }

    func onRemoteCallEnded(callId: UUID, reason: CallTerminationReason?) {
        let endedReason: CXCallEndedReason
        switch reason?.sipCode {
        case 486, 600:
            endedReason = .unanswered
        case 403, 404:
            endedReason = .failed
        default:
            endedReason = .remoteEnded
        }
        provider.reportCall(with: callId, endedAt: Date(), reason: endedReason)
        clearCall(uuid: callId)
        callPhase = .ended
        completePendingPushIfNeeded()
    }

    func onPushCall(call: Call) {
        if let uuid = call.callInfo?.callId {
            activeCalls[uuid] = call
            activeCallLabel = incomingLabel(for: call)
            callPhase = .connecting
            if callStartedAt == nil {
                callStartedAt = Date()
            }
            callConnectedAt = nil
            isMuted = call.isMuted
        }
    }
}

extension SalespersonVoiceCallService: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        for call in activeCalls.values {
            call.hangup()
        }
        activeCalls.removeAll()
        activeCallLabel = nil
        callPhase = .idle
        callStartedAt = nil
        callConnectedAt = nil
        isMuted = false
        telnyxClient.disconnect()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        do {
            try configureVoiceAudioSession()
        } catch {
            registrationError = "Unable to activate the microphone for Telnyx calling: \(error.localizedDescription)"
        }
        telnyxClient.enableAudioSession(audioSession: audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        telnyxClient.disableAudioSession(audioSession: audioSession)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            do {
                try await prepareMicrophoneForCall()
                telnyxClient.answerFromCallkit(answerAction: action)
                if callStartedAt == nil {
                    callStartedAt = Date()
                }
                callPhase = .connecting
            } catch {
                registrationError = error.localizedDescription
                action.fail()
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if activeCalls[action.callUUID] != nil || telnyxClient.isConnected() {
            telnyxClient.endCallFromCallkit(endAction: action, callId: action.callUUID)
            clearCall(uuid: action.callUUID)
            completePendingPushIfNeeded()
            return
        }

        action.fulfill()
        clearCall(uuid: action.callUUID)
        completePendingPushIfNeeded()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        activeCallLabel = action.handle.value
        callStartedAt = Date()
        callConnectedAt = nil
        callPhase = .connecting
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }
        if action.isMuted {
            call.muteAudio()
        } else {
            call.unmuteAudio()
        }
        isMuted = action.isMuted
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard let call = activeCalls[action.callUUID] else {
            action.fail()
            return
        }
        for digit in action.digits {
            call.dtmf(dtmf: String(digit))
        }
        action.fulfill()
    }
}

enum VoiceCallPhase: Equatable {
    case idle
    case connecting
    case connected
    case ended
}

private struct VoiceTokenResponse: Decodable {
    let provider: String?
    let sdkTarget: String?
    let token: String
    let identity: String
    let expiresAt: Date?
    let incomingAllowed: Bool?
    private let rawVoipPushConfigured: Bool?
    let telnyxTelephonyCredentialId: String?
    let requiresTelnyxVoiceSdk: Bool?
    let fromNumber: String?

    var voipPushConfigured: Bool {
        rawVoipPushConfigured ?? false
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case sdkTarget
        case token
        case identity
        case expiresAt
        case incomingAllowed
        case rawVoipPushConfigured = "voipPushConfigured"
        case telnyxTelephonyCredentialId
        case requiresTelnyxVoiceSdk
        case fromNumber
    }
}

private struct TelnyxClientState: Encodable {
    let callRequestId: String
    let callRequestSnakeId: String
    let role: String
    let direction: String
    let to: String?
    let from: String?

    enum CodingKeys: String, CodingKey {
        case callRequestId
        case callRequestSnakeId = "call_request_id"
        case role
        case direction
        case to
        case from
    }
}

private struct TelnyxTokenPayload: Decodable {
    let audience: String?
    let expiration: Date?
    let issuer: String?
    let embeddedToken: String?
    let tokenType: String?

    var telnyxAccessTokenInvalidReason: String? {
        if issuer != "telnyx_telephony" {
            return "iss is \(Self.claimDescription(issuer))"
        }
        if audience != "telnyx_telephony" {
            return "aud is \(Self.claimDescription(audience))"
        }
        if tokenType != "access" {
            return "typ is \(Self.claimDescription(tokenType))"
        }
        if embeddedToken?.isEmpty != false {
            return "tel_token is missing"
        }
        guard let expiration else {
            return "exp is missing"
        }
        if expiration <= Date() {
            return "token is expired"
        }
        return nil
    }

    init?(token: String) {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let decoded = try? JSONDecoder().decode(TelnyxTokenPayload.self, from: payloadData) else {
            return nil
        }

        self = decoded
    }

    private enum CodingKeys: String, CodingKey {
        case audience = "aud"
        case expiresAt = "exp"
        case issuer = "iss"
        case embeddedToken = "tel_token"
        case tokenType = "typ"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audience = try container.decodeIfPresent(String.self, forKey: .audience)
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        embeddedToken = try container.decodeIfPresent(String.self, forKey: .embeddedToken)
        tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)

        if let seconds = try container.decodeIfPresent(TimeInterval.self, forKey: .expiresAt) {
            expiration = Date(timeIntervalSince1970: seconds)
        } else {
            expiration = nil
        }
    }

    private static func claimDescription(_ value: String?) -> String {
        guard let value, !value.isEmpty else {
            return "missing"
        }
        return value
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        let normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingLength = (4 - normalized.count % 4) % 4
        let padded = normalized + String(repeating: "=", count: paddingLength)
        self.init(base64Encoded: padded)
    }

    var telnyxHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private enum VoiceCallError: LocalizedError {
    case missingWorkspace
    case badURL
    case microphoneDenied
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Salesperson workspace is not available."
        case .badURL:
            return "Unable to build the Telnyx voice request."
        case .microphoneDenied:
            return "Microphone access is required for Telnyx voice calls. Enable microphone permission for FLYR in iOS Settings."
        case .status(_, let message):
            return message
        }
    }
}
