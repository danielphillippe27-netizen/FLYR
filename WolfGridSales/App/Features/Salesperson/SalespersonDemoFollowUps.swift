import SwiftUI
import Combine
import Supabase

struct SalespersonDemoFollowUp: Decodable, Identifiable, Sendable {
    struct Metadata: Decodable, Sendable {
        let recipientName: String?
        let recipientEmail: String?
        let recipientPhone: String?
        let firstSentAt: Date?
        let lastSentAt: Date?
        let lastChannel: String?
        let sendCount: Int?
        let lastBody: String?
        let lastSubject: String?
        let replyReceivedAt: Date?
        let outcome: String?
    }
    let id: String
    let title: String
    let dueAt: Date?
    let status: String
    let salesLeadId: String?
    let salesContactId: String?
    let metadata: Metadata

    enum CodingKeys: String, CodingKey {
        case id, title, status, metadata
        case dueAt = "due_at", salesLeadId = "sales_lead_id", salesContactId = "sales_contact_id"
    }
    var displayName: String { metadata.recipientName ?? title }
    var statusLabel: String {
        if metadata.outcome == "signed_up" { return "Signed up" }
        if metadata.outcome == "delivery_failed" { return "Delivery failed" }
        if status == "completed" { return "Completed" }
        if status == "dismissed" { return "Stopped" }
        if let dueAt, dueAt < Calendar.current.startOfDay(for: Date()) { return "Overdue" }
        return "Scheduled"
    }
}

private struct DemoSendEvent: Decodable, Identifiable, Sendable {
    let id: String
    let channel: String
    let subject: String?
    let body: String?
    let status: String
    let occurredAt: Date
    let toAddresses: [String]
    enum CodingKeys: String, CodingKey {
        case id, channel, subject, body, status
        case occurredAt = "occurred_at", toAddresses = "to_addresses"
    }
}

private actor DemoFollowUpsAPI {
    static let shared = DemoFollowUpsAPI()

    private func request(path: String, method: String = "GET", query: [URLQueryItem] = [], payload: [String: String]? = nil) async throws -> Data {
        guard let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) else {
            throw NSError(domain: "DemoFollowUp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Select a workspace to load demo follow-ups."])
        }
        let session = try await SupabaseManager.shared.client.auth.session
        var components = URLComponents(url: Config.backendAPIURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)] + query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (try? await SupabaseManager.shared.client.auth.session.user.id) == session.user.id,
              (await MainActor.run(body: { WorkspaceContext.shared.workspaceId })) == workspaceId else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let error = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? "Unable to update demo follow-ups. Please try again."
            throw NSError(domain: "DemoFollowUp", code: 2, userInfo: [NSLocalizedDescriptionKey: error])
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid demo date")
        }
        return try decoder.decode(type, from: data)
    }

    func tasks() async throws -> [SalespersonDemoFollowUp] {
        struct Envelope: Decodable { let tasks: [SalespersonDemoFollowUp]; let hasMore: Bool }
        var rows: [SalespersonDemoFollowUp] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let data = try await request(path: "api/demo-follow-ups", query: [URLQueryItem(name: "offset", value: String(offset))])
            let page = try decode(Envelope.self, from: data)
            rows += page.tasks
            if !page.hasMore { return rows }
            offset += 100
        }
    }

    func history(taskId: String) async throws -> [DemoSendEvent] {
        struct Envelope: Decodable { let events: [DemoSendEvent]; let hasMore: Bool }
        var rows: [DemoSendEvent] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let data = try await request(path: "api/demo-follow-ups", query: [URLQueryItem(name: "taskId", value: taskId), URLQueryItem(name: "offset", value: String(offset))])
            let page = try decode(Envelope.self, from: data)
            rows += page.events
            if !page.hasMore { return rows }
            offset += 100
        }
    }

    func update(id: String, status: String? = nil, dueAt: Date? = nil) async throws -> SalespersonDemoFollowUp {
        var payload = ["id": id]
        if let status { payload["status"] = status }
        if let dueAt { payload["dueAt"] = ISO8601DateFormatter().string(from: dueAt) }
        struct Envelope: Decodable { let task: SalespersonDemoFollowUp }
        let data = try await request(path: "api/tasks", method: "PATCH", payload: payload)
        return try decode(Envelope.self, from: data).task
    }

    func send(task: SalespersonDemoFollowUp, channel: String, recipient: String, subject: String, body: String) async throws {
        var payload = ["channel": channel, "body": body, "subject": subject]
        payload[channel == "email" ? "email" : "phone"] = recipient
        payload["leadId"] = task.salesLeadId
        payload["contactId"] = task.salesContactId
        _ = try await request(path: "api/inbox", method: "POST", payload: payload)
    }
}

private enum DemoDueFilter: String, CaseIterable, Identifiable {
    case today = "Today", overdue = "Overdue", upcoming = "Upcoming", all = "All"
    var id: String { rawValue }
    func includes(_ task: SalespersonDemoFollowUp, now: Date = Date()) -> Bool {
        if self == .all { return true }
        guard task.status == "open", let due = task.dueAt else { return false }
        let start = Calendar.current.startOfDay(for: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        switch self {
        case .today: return due >= start && due < tomorrow
        case .overdue: return due < start
        case .upcoming: return due >= tomorrow
        case .all: return true
        }
    }
}

@MainActor
private final class DemoFollowUpsViewModel: ObservableObject {
    @Published var tasks: [SalespersonDemoFollowUp] = []
    @Published var isLoading = true
    @Published var error: String?
    private var refreshing = false
    func load() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false; isLoading = false }
        do { tasks = try await DemoFollowUpsAPI.shared.tasks(); error = nil }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

struct SalespersonDemoFollowUpsView: View {
    @StateObject private var model = DemoFollowUpsViewModel()
    @State private var filter: DemoDueFilter = .today
    private var visible: [SalespersonDemoFollowUp] { model.tasks.filter { filter.includes($0) } }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Demo due dates", selection: $filter) {
                ForEach(DemoDueFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(16)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
            List {
                Section {
                    Text("Demos sent by email or text automatically get a follow-up seven days later. Repeat sends keep the existing due date.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(visible) { task in
                    NavigationLink {
                        DemoFollowUpDetail(task: task)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(task.displayName).font(.subheadline.weight(.semibold)); Spacer(); Text(task.statusLabel).font(.caption2).foregroundStyle(task.statusLabel == "Overdue" ? .red : .secondary) }
                            if let sent = task.metadata.lastSentAt { Text("Sent by \(task.metadata.lastChannel == "sms" ? "text" : "email") · \(sent.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                            if let due = task.dueAt { Text("Follow up \(due.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                            if task.metadata.replyReceivedAt != nil { Label("Reply received", systemImage: "bubble.left.fill").font(.caption).foregroundStyle(.green) }
                        }.padding(.vertical, 4)
                    }
                }
                if visible.isEmpty && !model.isLoading {
                    Text(filter == .all ? "No demos sent yet. Send a demo through WolfGrid to start tracking follow-ups." : "No demos in this view. Check Upcoming for scheduled follow-ups.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical)
                }
            }
            .listStyle(.plain)
            .overlay { if model.isLoading { ProgressView() } }
            .refreshable { await model.load() }
        }
        .task {
            while !Task.isCancelled {
                await model.load()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}

private struct DemoFollowUpDetail: View {
    @State var task: SalespersonDemoFollowUp
    @Environment(\.dismiss) private var dismiss
    @State private var events: [DemoSendEvent] = []
    @State private var loading = true
    @State private var updating = false
    @State private var error: String?
    @State private var composeChannel: String?
    @State private var sentNotice = false
    var body: some View {
        List {
            Section("Demo follow-up") {
                Text(task.displayName).font(.headline)
                Text(task.statusLabel).font(.subheadline).foregroundStyle(.secondary)
                if let email = task.metadata.recipientEmail { Text(email).textSelection(.enabled) }
                if let phone = task.metadata.recipientPhone { Text("+\(phone)").textSelection(.enabled) }
                if let due = task.dueAt { Text("Follow up \(due.formatted(date: .abbreviated, time: .shortened))") }
                if let reply = task.metadata.replyReceivedAt { Label("Reply received \(reply.formatted(date: .abbreviated, time: .shortened))", systemImage: "bubble.left.fill").foregroundStyle(.green) }
                Text("Sent is recorded; viewing is not confirmed.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if sentNotice { Section { Text("Follow-up sent. Mark done when you’re finished.").foregroundStyle(.green) } }
            if task.status == "open" {
                Section("Actions") {
                    if let phone = task.metadata.recipientPhone, let url = URL(string: "tel:+\(phone)") { Link(destination: url) { Label("Call", systemImage: "phone") } }
                    if task.metadata.recipientPhone != nil { Button { composeChannel = "sms" } label: { Label("Text", systemImage: "message") } }
                    if task.metadata.recipientEmail != nil { Button { composeChannel = "email" } label: { Label("Email", systemImage: "envelope") } }
                    Button { snooze(days: 1) } label: { Label("Snooze until tomorrow", systemImage: "clock") }
                    Button("Snooze for a week") { snooze(days: 7) }
                    Button { update(status: "completed") } label: { Label("Mark done", systemImage: "checkmark.circle") }
                    Button("Stop follow-up", role: .destructive) { update(status: "dismissed") }
                }.disabled(updating)
            }
            Section("Send history") {
                if loading { ProgressView() }
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(event.channel == "sms" ? "Text" : "Email") · \(event.occurredAt.formatted(date: .abbreviated, time: .shortened))").font(.subheadline.weight(.medium))
                        Text("To \(event.toAddresses.joined(separator: ", ")) · \(event.status)").font(.caption).foregroundStyle(.secondary)
                        if let subject = event.subject { Text(subject).font(.subheadline.weight(.semibold)) }
                        if let body = event.body { Text(body).font(.subheadline).textSelection(.enabled) }
                    }.padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Demo").navigationBarTitleDisplayMode(.inline)
        .task {
            do { events = try await DemoFollowUpsAPI.shared.history(taskId: task.id) }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            loading = false
        }
        .sheet(isPresented: Binding(get: { composeChannel != nil }, set: { if !$0 { composeChannel = nil } })) {
            if let channel = composeChannel { DemoFollowUpComposer(task: task, channel: channel) { sentNotice = true } }
        }
    }
    private func snooze(days: Int) {
        guard let due = Calendar.current.date(byAdding: .day, value: days, to: Date()) else { return }
        update(dueAt: due)
    }
    private func update(status: String? = nil, dueAt: Date? = nil) {
        guard !updating else { return }
        updating = true; error = nil
        Task {
            defer { updating = false }
            do {
                task = try await DemoFollowUpsAPI.shared.update(id: task.id, status: status, dueAt: dueAt)
                if status != nil { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct DemoFollowUpComposer: View {
    let task: SalespersonDemoFollowUp
    let channel: String
    let onSent: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recipient: String
    @State private var subject = "Checking in about WolfGrid"
    @State private var message = "Hi, just checking in to see if you had a chance to look at WolfGrid. Any questions I can help with?"
    @State private var sending = false
    @State private var error: String?
    init(task: SalespersonDemoFollowUp, channel: String, onSent: @escaping () -> Void) {
        self.task = task; self.channel = channel; self.onSent = onSent
        _recipient = State(initialValue: channel == "email" ? task.metadata.recipientEmail ?? "" : "+\(task.metadata.recipientPhone ?? "")")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("To") { TextField("Recipient", text: $recipient).keyboardType(channel == "email" ? .emailAddress : .phonePad).textInputAutocapitalization(.never).autocorrectionDisabled() }
                if channel == "email" { Section("Subject") { TextField("Subject", text: $subject) } }
                Section("Message") { TextEditor(text: $message).frame(minHeight: 160) }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .disabled(sending)
            .navigationTitle(channel == "email" ? "Email follow-up" : "Text follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(sending) }
                ToolbarItem(placement: .confirmationAction) { Button(sending ? "Sending…" : "Send") { send() }.disabled(sending || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .interactiveDismissDisabled(sending)
        }
    }
    private func send() {
        guard !sending else { return }
        sending = true; error = nil
        Task {
            defer { sending = false }
            do {
                try await DemoFollowUpsAPI.shared.send(task: task, channel: channel, recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines), subject: subject, body: message.trimmingCharacters(in: .whitespacesAndNewlines))
                onSent(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
