import Combine
import Foundation
import Supabase

@MainActor
final class SessionChatStore: ObservableObject {
    static let shared = SessionChatStore()

    @Published private(set) var rooms: [SessionChatRoom] = []
    @Published private(set) var messagesBySession: [UUID: [SessionChatMessage]] = [:]
    @Published private(set) var loadingRooms = false
    @Published private(set) var loadingSessions: Set<UUID> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var nextMessageCursorBySession: [UUID: String] = [:]

    private let api = SessionChatAPI.shared
    private let cache = SessionChatCacheRepository.shared
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?
    private var networkCancellable: AnyCancellable?
    private var foregroundSessionId: UUID?
    private var startedUserId: UUID?
    private var sendingIDs: Set<UUID> = []

    var totalUnreadCount: Int { rooms.reduce(0) { $0 + $1.unreadCount } }

    private init() {
        networkCancellable = NetworkMonitor.shared.$isOnline
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in await self?.flushPending() }
            }
    }

    func unreadCount(sessionId: UUID) -> Int {
        rooms.first(where: { $0.sessionId == sessionId })?.unreadCount ?? 0
    }

    func resetForAccountChange() async {
        let previousUser = startedUserId
        rooms=[];messagesBySession=[:];nextMessageCursorBySession=[:]
        foregroundSessionId=nil;startedUserId=nil;loadingRooms=false;loadingSessions=[];errorMessage=nil
        if let previousUser { await cache.pausePending(userId: previousUser) }
        await stopRealtime()
    }

    func start() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        if startedUserId != userId {
            await resetForAccountChange()
            startedUserId = userId
            await subscribeRealtime(userId: userId)
        }
        await loadRooms()
        if NetworkMonitor.shared.isOnline { await flushPending() }
    }

    func loadRooms() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        loadingRooms = true
        let cached = await cache.fetchRooms(userId: userId)
        guard userId == AuthManager.shared.user?.id else { return }
        if rooms.isEmpty { rooms = sortRooms(cached) }
        guard NetworkMonitor.shared.isOnline else {
            loadingRooms = false
            return
        }
        do {
            let response = try await api.fetchRooms()
            guard userId == AuthManager.shared.user?.id else { return }
            rooms = sortRooms(response.rooms)
            await cache.upsertRooms(response.rooms, userId: userId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loadingRooms = false
    }

    func loadMessages(sessionId: UUID, refresh: Bool = false) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        loadingSessions.insert(sessionId)
        let cached = await cache.fetchMessages(sessionId: sessionId, userId: userId)
        guard userId == AuthManager.shared.user?.id else { return }
        if messagesBySession[sessionId] == nil || refresh {
            messagesBySession[sessionId] = merge(messagesBySession[sessionId] ?? [], cached)
        }
        guard NetworkMonitor.shared.isOnline else {
            loadingSessions.remove(sessionId)
            return
        }
        do {
            let response = try await api.fetchMessages(sessionId: sessionId)
            guard userId == AuthManager.shared.user?.id else { return }
            nextMessageCursorBySession[sessionId] = response.nextCursor
            let delivered = response.messages.map { message -> SessionChatMessage in
                var copy = message
                copy.deliveryState = .delivered
                return copy
            }
            let merged = merge(messagesBySession[sessionId] ?? [], delivered)
            messagesBySession[sessionId] = merged
            await cache.upsertMessages(merged, userId: userId)
            errorMessage = nil
            if foregroundSessionId == sessionId { await markRead(sessionId: sessionId) }
        } catch {
            errorMessage = error.localizedDescription
        }
        loadingSessions.remove(sessionId)
    }

    func loadOlderMessages(sessionId: UUID) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard NetworkMonitor.shared.isOnline,
              let cursor = nextMessageCursorBySession[sessionId],
              !loadingSessions.contains(sessionId) else { return }
        loadingSessions.insert(sessionId)
        do {
            let response = try await api.fetchMessages(sessionId: sessionId, cursor: cursor)
            guard userId == AuthManager.shared.user?.id else { return }
            let delivered = response.messages.map { message -> SessionChatMessage in
                var copy = message
                copy.deliveryState = .delivered
                return copy
            }
            let merged = merge(messagesBySession[sessionId] ?? [], delivered)
            messagesBySession[sessionId] = merged
            nextMessageCursorBySession[sessionId] = response.nextCursor
            await cache.upsertMessages(delivered, userId: userId)
        } catch {
            errorMessage = error.localizedDescription
        }
        loadingSessions.remove(sessionId)
    }

    func roomDidAppear(sessionId: UUID) async {
        foregroundSessionId = sessionId
        await loadMessages(sessionId: sessionId)
        await markRead(sessionId: sessionId)
    }

    func roomDidDisappear(sessionId: UUID) {
        if foregroundSessionId == sessionId { foregroundSessionId = nil }
    }

    func sendText(sessionId: UUID, campaignId: UUID, text: String) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...1_000).contains(trimmed.count), let sender = currentSender else { return }
        let pending = SessionChatMessage.pendingText(
            sessionId: sessionId,
            campaignId: campaignId,
            clientMessageId: UUID(),
            text: trimmed,
            sender: sender
        )
        messagesBySession[sessionId] = merge(messagesBySession[sessionId] ?? [], [pending])
        await cache.upsertMessages([pending], userId: userId)
        if NetworkMonitor.shared.isOnline { await deliver(pending) }
    }

    func sendVoice(sessionId: UUID, campaignId: UUID, fileURL: URL, durationMs: Int) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard let sender = currentSender else { return }
        guard (1_000...120_000).contains(durationMs) else {
            try? FileManager.default.removeItem(at: fileURL)
            errorMessage = "Voice notes must be between 1 and 120 seconds."
            return
        }
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard (1...(4 * 1_024 * 1_024)).contains(fileSize) else {
            try? FileManager.default.removeItem(at: fileURL)
            errorMessage = "Voice notes must be no larger than 4 MB."
            return
        }
        let clientId = UUID()
        let privateURL: URL
        do {
            privateURL = try moveIntoPrivateStorage(source: fileURL, clientId: clientId)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let pending = SessionChatMessage(
            id: "local:\(clientId.uuidString)",
            sessionId: sessionId,
            campaignId: campaignId,
            clientMessageId: clientId,
            type: .voice,
            text: nil,
            audioUrl: nil,
            durationMs: durationMs,
            createdAt: Date(),
            sender: sender,
            deliveryState: .pending,
            localAudioPath: privateURL.path,
            errorMessage: nil
        )
        messagesBySession[sessionId] = merge(messagesBySession[sessionId] ?? [], [pending])
        await cache.upsertMessages([pending], userId: userId)
        if NetworkMonitor.shared.isOnline { await deliver(pending) }
    }

    func retry(_ message: SessionChatMessage) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard message.sender.id == userId else { return }
        var retrying = message
        retrying.deliveryState = .retrying
        retrying.errorMessage = nil
        replace(retrying)
        await cache.upsertMessages([retrying], userId: userId)
        await deliver(retrying)
    }

    func discard(_ message: SessionChatMessage) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard message.sender.id == userId else { return }
        let cached = await cache.fetchMessages(sessionId: message.sessionId, userId: userId)
        let latest = cached.first(where: { $0.clientMessageId == message.clientMessageId }) ?? message
        guard !sendingIDs.contains(message.clientMessageId), !latest.isDelivered, latest.transmissionStarted != true else {
            errorMessage="This message is sending or was already sent and cannot be recalled."
            return
        }
        if let path = message.localAudioPath { try? FileManager.default.removeItem(atPath: path) }
        messagesBySession[message.sessionId]?.removeAll { $0.clientMessageId == message.clientMessageId }
        await cache.delete(clientMessageId: message.clientMessageId, userId: userId)
    }

    private func deliver(_ pending: SessionChatMessage) async {
        guard let userId = AuthManager.shared.user?.id, pending.sender.id == userId, startedUserId == userId,
              !sendingIDs.contains(pending.clientMessageId) else { return }
        sendingIDs.insert(pending.clientMessageId)
        defer { sendingIDs.remove(pending.clientMessageId) }
        guard await cache.fetchPending(userId: userId).contains(where: { $0.clientMessageId == pending.clientMessageId }),
              userId == AuthManager.shared.user?.id, startedUserId == userId else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        var transmitting = pending
        transmitting.transmissionStarted = true
        await cache.upsertMessages([transmitting], userId: userId)
        replace(transmitting)
        do {
            let response: SessionChatSendResponse
            switch pending.type {
            case .text:
                response = try await api.sendText(
                    sessionId: pending.sessionId,
                    clientMessageId: pending.clientMessageId,
                    text: pending.text ?? "", expectedUserId: userId
                )
            case .voice:
                guard let path = pending.localAudioPath else {
                    throw SessionChatAPIError.invalidMessage("The local voice recording is missing.")
                }
                response = try await api.sendVoice(
                    sessionId: pending.sessionId,
                    clientMessageId: pending.clientMessageId,
                    fileURL: URL(fileURLWithPath: path),
                    durationMs: pending.durationMs ?? 0, expectedUserId: userId
                )
            }
            guard userId == AuthManager.shared.user?.id else { return }
            var delivered = response.message
            delivered.deliveryState = .delivered
            delivered.localAudioPath = nil
            if let path = pending.localAudioPath { try? FileManager.default.removeItem(atPath: path) }
            replace(delivered)
            await cache.upsertMessages([delivered], userId: userId)
            await loadRooms()
        } catch {
            guard userId == AuthManager.shared.user?.id, startedUserId == userId else { return }
            var failed = transmitting
            failed.deliveryState = error is SessionChatAPIError ? .failed : .pending
            failed.errorMessage = error.localizedDescription
            replace(failed)
            await cache.upsertMessages([failed], userId: userId)
        }
    }

    func flushPending() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        for message in await cache.fetchPending(userId: userId) { await deliver(message) }
    }

    private func markRead(sessionId: UUID) async {
        guard let userId = AuthManager.shared.user?.id else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        let last = messagesBySession[sessionId]?.last(where: { $0.isDelivered })
        do {
            _ = try await api.markRead(sessionId: sessionId, lastReadMessageId: last?.id, expectedUserId: userId)
            guard userId == AuthManager.shared.user?.id else { return }
            if let index = rooms.firstIndex(where: { $0.sessionId == sessionId }) {
                rooms[index].unreadCount = 0
                await cache.upsertRooms([rooms[index]], userId: userId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscribeRealtime(userId: UUID) async {
        let channel = SupabaseManager.shared.client.channel("session-chat-user-\(userId.uuidString)")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "session_chat_messages")
        streamTask = Task { [weak self] in
            for await insert in inserts {
                guard let id = insert.record["session_id"]?.stringValue.flatMap(UUID.init(uuidString:)) else { continue }
                await self?.handleRealtimeInsert(sessionId: id)
            }
        }
        do {
            try await channel.subscribeWithError()
            self.channel = channel
        } catch {
            streamTask?.cancel()
            streamTask = nil
        }
    }

    private func handleRealtimeInsert(sessionId: UUID) async {
        if foregroundSessionId == sessionId { await loadMessages(sessionId: sessionId, refresh: true) }
        await loadRooms()
    }

    private func stopRealtime() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel { await channel.unsubscribe() }
        channel = nil
    }

    private var currentSender: SessionChatSender? {
        guard let user = AuthManager.shared.user else { return nil }
        let displayName = (user.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionChatSender(
            id: user.id,
            name: displayName.isEmpty ? user.email : displayName,
            avatarUrl: user.photoURL
        )
    }

    private func replace(_ message: SessionChatMessage) {
        let current = messagesBySession[message.sessionId] ?? []
        messagesBySession[message.sessionId] = merge(current, [message])
    }

    private func merge(_ lhs: [SessionChatMessage], _ rhs: [SessionChatMessage]) -> [SessionChatMessage] {
        SessionChatMessageMerger.merge(lhs, rhs)
    }

    private func sortRooms(_ rooms: [SessionChatRoom]) -> [SessionChatRoom] {
        rooms.sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return $0.latestMessageAt > $1.latestMessageAt
        }
    }

    private func moveIntoPrivateStorage(source: URL, clientId: UUID) throws -> URL {
        let root = OfflineDatabase.shared.storageDirectory.appendingPathComponent("SessionChatOutbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        let destination = root.appendingPathComponent("\(clientId.uuidString).m4a")
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }
}
