import Foundation
import Combine
import Supabase

struct WolfyCoachReply: Decodable {
    let message: String
    let recommendation: String?
    let source: String
    let reason: String
    let destination: String
    var label: String { source == "ai" ? "AI coach" : "Rule-based coach" }
}

struct WolfyCoachMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    var label: String? = nil
}

@MainActor final class WolfyCoachStore: ObservableObject {
    @Published private(set) var brief: WolfyCoachReply?
    @Published private(set) var messages: [WolfyCoachMessage] = []
    @Published private(set) var loading = false
    @Published private(set) var sending = false
    @Published private(set) var error: String?
    private var scope: String?
    private var generation = UUID()
    private var lastQuestion: String?

    func clear() {
        generation = UUID(); brief = nil; messages = []; error = nil
        scope = nil; loading = false; sending = false; lastQuestion = nil
    }
    private func select(user: UUID, workspace: UUID) {
        let next = "\(user):\(workspace)"
        if scope != next { clear(); scope = next }
    }
    func refresh(user: UUID, workspace: UUID) async {
        select(user: user, workspace: workspace)
        guard !loading else { return }
        loading = true
        let token = generation
        defer { if token == generation { loading = false } }
        do {
            let result = try await request(user: user, workspace: workspace, question: nil)
            guard token == generation, !Task.isCancelled else { return }
            brief = result; error = nil
        } catch {
            guard token == generation else { return }
            brief = nil
            self.error = "AI coaching is unavailable. Your next step still uses available activity."
        }
    }
    func ask(_ question: String, user: UUID, workspace: UUID, retry: Bool = false) async {
        select(user: user, workspace: workspace)
        let question = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !question.isEmpty, !sending else { return }
        sending = true; error = nil; lastQuestion = question
        let token = generation
        defer { if token == generation { sending = false } }
        // Capture preceding history before adding this question.
        let history = Array(messages.suffix(6))
        if !retry { messages.append(.init(role: "user", content: question)) }
        do {
            let reply = try await request(user: user, workspace: workspace, question: question, history: retry ? Array(history.dropLast()) : history)
            guard token == generation, !Task.isCancelled else { return }
            let text = reply.source == "ai" ? reply.message : "AI couldn't answer this question right now. Based on your synced activity: \(reply.message)"
            messages.append(.init(role: "assistant", content: text, label: reply.label))
            if reply.source != "ai" { error = reply.reason == "limit" ? "AI is taking a break. Try again later; daily requests are limited." : "AI is unavailable. You can retry your question." }
            else { lastQuestion = nil }
            if messages.count > 40 { messages.removeFirst(messages.count - 40) }
        } catch {
            guard token == generation else { return }
            self.error = "Couldn't reach Wolfy. Check your connection and retry."
        }
    }
    func retry(user: UUID, workspace: UUID) async {
        guard let lastQuestion else { return }
        if messages.last?.role == "assistant" { messages.removeLast() }
        await ask(lastQuestion, user: user, workspace: workspace, retry: true)
    }
    private struct Turn: Encodable { let role: String; let content: String }
    private struct Body: Encodable {
        let workspaceId: UUID; let timezone: String; let mode: String
        let message: String?; let history: [Turn]
    }
    private func request(user: UUID, workspace: UUID, question: String?, history: [WolfyCoachMessage] = []) async throws -> WolfyCoachReply {
        let session = try await SupabaseManager.shared.client.auth.session
        guard session.user.id == user else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: Config.backendAPIURL.appendingPathComponent("api/wolfy/coach"))
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(workspaceId: workspace, timezone: TimeZone.current.identifier, mode: question == nil ? "brief" : "chat", message: question, history: history.map { Turn(role: $0.role, content: String($0.content.prefix(1400))) }))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(WolfyCoachReply.self, from: data)
    }
}
