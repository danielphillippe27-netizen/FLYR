import SwiftUI
import Supabase

/// Uses the user's existing calendar records; completion persists independently of XP rollout.
struct WolfyFollowupsViewV2: View {
    private struct Followup: Decodable, Identifiable {
        let id: UUID
        let user_id: UUID
        let title: String
        let start_at: Date
        let completed_at: Date?
    }
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var phase
    @State private var rows: [Followup] = []
    @State private var error: String?
    @State private var loading = true
    @State private var saving: UUID?
    @State private var generation = UUID()
    private let client = SupabaseManager.shared.client
    var body: some View {
        List {
            Section {
                ForEach(rows.filter { $0.user_id == auth.user?.id }) { row in
                    Button {
                        Task { await complete(row) }
                    } label: {
                        HStack {
                            Image(systemName: row.completed_at == nil ? "circle" : "checkmark.circle.fill")
                            VStack(alignment: .leading) {
                                Text(row.title)
                                Text(row.start_at, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if saving == row.id { ProgressView() }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(saving != nil)
                    .accessibilityLabel("\(row.title), \(row.completed_at == nil ? "mark completed" : "undo completion")")
                }
                if loading { ProgressView("Loading follow-ups") }
                else if rows.isEmpty && error == nil { Text("No recent or upcoming follow-ups.").foregroundStyle(.secondary) }
            } footer: {
                Text("Mark a follow-up complete after you finish it. Undoing completion also corrects its XP reward.")
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }
        .navigationTitle("Follow-ups")
        .task(id: "\(auth.user?.id.uuidString ?? ""):\(phase)") {
            generation = UUID(); rows = []; error = nil; saving = nil
            if phase == .active { await load(ticket: generation) }
            else { loading = false }
        }
        .onDisappear { generation = UUID(); rows = []; saving = nil }
        .refreshable { await load(ticket: generation) }
    }
    private func load(ticket: UUID) async {
        guard let user = auth.user?.id else { loading = false; return }
        loading = true
        defer { if ticket == generation { loading = false } }
        do {
            let response = try await client.from("calendar_events")
                .select("id,user_id,title,start_at,completed_at")
                .eq("user_id", value: user).eq("event_type", value: "follow_up")
                .is("deleted_at", value: nil)
                .gte("start_at", value: Date().addingTimeInterval(-30 * 86400).ISO8601Format())
                .order("start_at").limit(100).execute()
            let next = try JSONDecoder.supabaseDates.decode([Followup].self, from: response.data)
            guard !Task.isCancelled, ticket == generation, auth.user?.id == user,
                  next.allSatisfy({ $0.user_id == user }) else { return }
            rows = next; error = nil
        } catch {
            guard ticket == generation else { return }
            rows = []; self.error = "Follow-ups are unavailable. Your calendar remains available."
        }
    }
    private func complete(_ row: Followup) async {
        guard saving == nil, auth.user?.id == row.user_id else { return }
        let ticket = generation
        saving = row.id
        defer { if ticket == generation { saving = nil } }
        do {
            guard try await client.auth.session.user.id == row.user_id else { return }
            struct Params: Encodable { let p_event: UUID; let p_completed: Bool }
            _ = try await client.rpc("wolfy_v2_complete_followup", params: Params(p_event: row.id, p_completed: row.completed_at == nil)).execute()
            guard ticket == generation, auth.user?.id == row.user_id else { return }
            await load(ticket: ticket)
        } catch {
            if ticket == generation { self.error = "Completion could not be saved. Please try again." }
        }
    }
}
