import SwiftUI
import Supabase

struct SupportChatView: View {
    @StateObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var thread: SupportThread?
    @State private var messages: [SupportMessage] = []
    @State private var inputText = ""
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var sendError: String?
    @State private var realtimeChannel: RealtimeChannel?

    var body: some View {
        Group {
            if let thread = thread {
                chatContent(thread: thread)
            } else if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Unable to load support",
                    systemImage: "message",
                    description: Text(loadError ?? "Could not load or create your support thread. Please try again.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Button("Retry") {
                        Task { await loadOrCreateThread() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: auth.user?.id) {
            await loadOrCreateThread()
        }
        .onDisappear {
            Task { await unsubscribeRealtime() }
        }
    }

    private func chatContent(thread: SupportThread) -> some View {
        VStack(spacing: 0) {
            messagesList
            inputBar(threadId: thread.id)
        }
        .background(chatBackground)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        SupportBubbleView(message: msg, isFromUser: msg.isFromUser)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inputBar(threadId: UUID) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...5)

            Button {
                sendMessage(threadId: threadId)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .red)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            if let err = sendError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    private var chatBackground: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }

    // MARK: - Data

    private func loadOrCreateThread() async {
        guard let userId = auth.user?.id else {
            await MainActor.run {
                loadError = "You must be signed in to use support."
                thread = nil
                isLoading = false
            }
            return
        }
        await MainActor.run {
            isLoading = true
            loadError = nil
            sendError = nil
        }
        do {
            let t = try await SupportService.shared.getOrCreateThread(userId: userId)
            await MainActor.run { thread = t }
            let list = try await SupportService.shared.fetchMessages(threadId: t.id)
            await MainActor.run { messages = list }
            try await subscribeRealtime(threadId: t.id)
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                thread = nil
            }
        }
        await MainActor.run { isLoading = false }
    }

    private func subscribeRealtime(threadId: UUID) async throws {
        await unsubscribeRealtime()
        let channel = try await SupportService.shared.subscribeMessages(threadId: threadId) { newMsg in
            Task { @MainActor in
                if !messages.contains(where: { $0.id == newMsg.id }) {
                    messages.append(newMsg)
                }
            }
        }
        await MainActor.run { realtimeChannel = channel }
    }

    private func unsubscribeRealtime() async {
        if let ch = realtimeChannel {
            await ch.unsubscribe()
            await MainActor.run { realtimeChannel = nil }
        }
    }

    private func sendMessage(threadId: UUID) {
        guard let userId = auth.user?.id else { return }
        let body = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        inputText = ""
        sendError = nil
        Task {
            do {
                let sent = try await SupportService.shared.sendMessage(threadId: threadId, body: body, senderUserId: userId)
                await MainActor.run {
                    if !messages.contains(where: { $0.id == sent.id }) {
                        messages.append(sent)
                    }
                }
            } catch {
                await MainActor.run { sendError = error.localizedDescription }
            }
        }
    }
}

// MARK: - Bubble

private struct SupportBubbleView: View {
    let message: SupportMessage
    let isFromUser: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: message.createdAt)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isFromUser { Spacer(minLength: 48) }
            VStack(alignment: isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(isFromUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        isFromUser
                            ? Color.red
                            : Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.12),
                        in: Capsule()
                    )
                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !isFromUser { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isFromUser ? .trailing : .leading)
    }
}

#Preview {
    NavigationStack {
        SupportChatView()
            .environmentObject(AppUIState())
    }
}
