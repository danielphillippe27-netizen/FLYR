import SwiftUI

struct SessionChatButton: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.black.opacity(0.94))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.34), radius: 8, x: 0, y: 3)
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 19, minHeight: 19)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: 3, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Team chat")
        .accessibilityValue(unreadCount == 0 ? "No unread messages" : "\(unreadCount) unread messages")
    }
}

struct LiveSessionParticipantsButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("\(count) Live")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(Color.black.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) people live")
        .accessibilityHint("Opens the list of people in this session")
    }
}

struct LiveSessionParticipantsSheet: View {
    let teammates: [SharedCanvassingTeammate]
    let includesCurrentUser: Bool

    var body: some View {
        NavigationStack {
            List {
                if includesCurrentUser { participantRow(name: "You", isAvailable: true) }
                ForEach(teammates) { teammate in
                    participantRow(
                        name: teammate.displayName,
                        isAvailable: !teammate.isStale && teammate.presenceStatus == .active
                    )
                }
            }
            .navigationTitle("Live Session")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func participantRow(name: String, isAvailable: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(isAvailable ? Color.green : Color.gray).frame(width: 8, height: 8)
            Text(name).font(.system(size: 16, weight: .medium))
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isAvailable ? "active" : "inactive")")
    }
}

struct TeamChatListView: View {
    @StateObject private var store = SessionChatStore.shared

    var body: some View {
        Group {
            if store.loadingRooms && store.rooms.isEmpty {
                ProgressView("Loading team chats…")
            } else if store.rooms.isEmpty {
                ContentUnavailableView(
                    "No Team Chats",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Chats appear here after you join a team session.")
                )
            } else {
                List(store.rooms) { room in
                    NavigationLink {
                        SessionChatRoomView(sessionId: room.sessionId, campaignId: room.campaignId)
                    } label: {
                        SessionChatRoomRow(room: room)
                    }
                }
                .listStyle(.plain)
                .refreshable { await store.loadRooms() }
            }
        }
        .navigationTitle("Team Chats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.start() }
    }
}

private struct SessionChatRoomRow: View {
    let room: SessionChatRoom

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(room.isActive ? Color.green.opacity(0.18) : Color.secondary.opacity(0.14))
                Image(systemName: room.isActive ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .foregroundStyle(room.isActive ? Color.green : Color.secondary)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(room.campaignName).font(.headline).lineLimit(1)
                    if room.isActive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.green).clipShape(Capsule())
                    }
                }
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(room.latestMessageAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                if room.unreadCount > 0 {
                    Text("\(room.unreadCount)")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20).background(Color.red).clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: String {
        guard let message = room.latestMessage else { return "No messages yet • \(room.participantCount) participants" }
        return message.type == .voice ? "Voice note" : (message.text ?? "Message")
    }
}

struct SessionChatRoomView: View {
    let sessionId: UUID
    let campaignId: UUID
    @StateObject private var store = SessionChatStore.shared
    @StateObject private var audio = SessionChatAudioController.shared
    @State private var draft = ""
    @State private var sendError: String?
    @FocusState private var composerFocused: Bool

    private var messages: [SessionChatMessage] { store.messagesBySession[sessionId] ?? [] }
    private var room: SessionChatRoom? { store.rooms.first(where: { $0.sessionId == sessionId }) }
    private var canSend: Bool { room?.canSend ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if !canSend {
                Text("This session has ended. Messages are read-only.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.secondary.opacity(0.12))
            }
            messageList
            if canSend { composer }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(room?.campaignName ?? "Team Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.roomDidAppear(sessionId: sessionId) }
        .onDisappear {
            store.roomDidDisappear(sessionId: sessionId)
            audio.pausePlayback()
            if audio.isRecording { audio.stopRecording() }
        }
        .alert("Team Chat", isPresented: Binding(
            get: { sendError != nil },
            set: { if !$0 { sendError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(sendError ?? "") }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.nextMessageCursorBySession[sessionId] != nil {
                        Button("Load earlier messages") {
                            Task { await store.loadOlderMessages(sessionId: sessionId) }
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.vertical, 8)
                    }
                    if store.loadingSessions.contains(sessionId) && messages.isEmpty { ProgressView().padding() }
                    if messages.isEmpty && !store.loadingSessions.contains(sessionId) {
                        ContentUnavailableView(
                            "No Messages Yet",
                            systemImage: "bubble.left",
                            description: Text(canSend ? "Start the team conversation." : "No messages were sent in this session.")
                        ).padding(.top, 80)
                    }
                    ForEach(messages) { message in
                        SessionChatBubble(
                            message: message,
                            isMine: message.sender.id == AuthManager.shared.user?.id,
                            onRetry: { Task { await store.retry(message) } },
                            onDiscard: { Task { await store.discard(message) } }
                        )
                        .id(message.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if audio.isRecording || audio.recordingURL != nil { recordingPreview }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .onChange(of: draft) { _, value in
                        if value.count > 1_000 { draft = String(value.prefix(1_000)) }
                    }
                Button {
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let text = draft
                        draft = ""
                        Task { await store.sendText(sessionId: sessionId, campaignId: campaignId, text: text) }
                    } else {
                        Task {
                            do {
                                if audio.isRecording { audio.stopRecording() } else { try await audio.startRecording() }
                            } catch { sendError = error.localizedDescription }
                        }
                    }
                } label: {
                    Image(systemName: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(draft.isEmpty ? "Record voice note" : "Send message")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private var recordingPreview: some View {
        HStack(spacing: 10) {
            Circle().fill(audio.isRecording ? Color.red : Color.secondary).frame(width: 8, height: 8)
            Text(audio.recordingDuration.formattedChatDuration).font(.system(.body, design: .monospaced))
            ProgressView(value: min(1, audio.recordingDuration / 120)).tint(.red)
            Button("Cancel") { audio.discardRecording() }.font(.footnote.weight(.semibold))
            if !audio.isRecording {
                Button("Send") {
                    guard let recording = audio.consumeRecording() else { return }
                    Task {
                        await store.sendVoice(
                            sessionId: sessionId,
                            campaignId: campaignId,
                            fileURL: recording.0,
                            durationMs: recording.1
                        )
                    }
                }
                .font(.footnote.bold())
                .disabled(audio.recordingDuration < 1)
            }
        }
        .padding(.horizontal, 8)
    }
}

private struct SessionChatBubble: View {
    let message: SessionChatMessage
    let isMine: Bool
    let onRetry: () -> Void
    let onDiscard: () -> Void
    @ObservedObject private var audio = SessionChatAudioController.shared

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            if isMine { Spacer(minLength: 50) }
            if !isMine {
                AsyncImage(url: message.sender.avatarUrl) { image in image.resizable().scaledToFill() } placeholder: {
                    Circle().fill(Color.secondary.opacity(0.2)).overlay(Text(String(message.sender.name.prefix(1))).font(.caption.bold()))
                }
                .frame(width: 28, height: 28).clipShape(Circle())
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine { Text(message.sender.name).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                Group {
                    if message.type == .text {
                        Text(message.text ?? "").textSelection(.enabled)
                    } else {
                        Button {
                            audio.togglePlayback(
                                messageId: message.id,
                                remoteURL: message.audioUrl,
                                localPath: message.localAudioPath,
                                durationMs: message.durationMs
                            )
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: audio.playingMessageId == message.id ? "pause.fill" : "play.fill")
                                ProgressView(value: audio.playingMessageId == message.id ? audio.playbackProgress : 0)
                                    .frame(width: 100).tint(isMine ? .white : .red)
                                Text((Double(message.durationMs ?? 0) / 1_000).formattedChatDuration)
                                    .font(.caption.monospacedDigit())
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(isMine ? Color.white : Color.primary)
                .background(isMine ? Color.red : Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack(spacing: 5) {
                    Text(message.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                    if let state = message.deliveryState, state != .delivered {
                        Text(state == .pending ? "Queued" : state == .retrying ? "Retrying" : "Failed")
                            .font(.caption2.weight(.semibold)).foregroundStyle(state == .failed ? .red : .secondary)
                    }
                    if message.deliveryState == .failed {
                        Button("Retry", action: onRetry).font(.caption2.bold())
                        Button("Discard", role: .destructive, action: onDiscard).font(.caption2)
                    }
                }
            }
            if !isMine { Spacer(minLength: 50) }
        }
    }
}

private extension TimeInterval {
    var formattedChatDuration: String {
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
