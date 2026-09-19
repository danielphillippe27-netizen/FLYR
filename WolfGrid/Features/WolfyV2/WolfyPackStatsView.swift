import SwiftUI
import Combine
import Supabase

enum WolfyPackPeriodV2: String, CaseIterable, Identifiable {
    case today, week, month, campaign
    var id: String { rawValue }
    var title: String {
        switch self { case .today: "Today"; case .week: "This Week"; case .month: "This Month"; case .campaign: "Campaign" }
    }
}
struct WolfyPackStatsV2: Decodable {
    struct Goals: Codable {
        var doors: Int?
        var conversations: Int?
        var appointments: Int?
        var verified_sales: Int?
    }
    struct Member: Decodable, Identifiable {
        let user_id: UUID
        let first_name: String
        let stage: Int
        let doors: Int
        let conversations: Int
        let leads: Int
        let appointments: Int
        let verified_sales: Int
        let earned_xp: Int
        let current_session_streak: Int
        let revenue_minor: String?
        let conversion: Double?
        var id: UUID { user_id }
    }
    let version: Int
    let enabled: Bool
    let campaign_id: UUID?
    let period: WolfyPackPeriodV2?
    let timezone: String?
    let manager: Bool?
    let goals: Goals?
    let totals: [String: Int]?
    let currency: String?
    let members: [Member]?
}
extension WolfyPackPeriodV2: Codable {}

@MainActor final class WolfyPackStatsStoreV2: ObservableObject {
    @Published private(set) var snapshot: WolfyPackStatsV2?
    @Published private(set) var error: String?
    @Published private(set) var saving = false
    @Published private(set) var ownerID: UUID?
    private let client = SupabaseManager.shared.client
    private var generation = UUID()
    private var mutation = 0
    func reset() { generation = UUID(); snapshot = nil; error = nil; saving = false; ownerID = nil }
    func observe(user: UUID, campaign: UUID, period: WolfyPackPeriodV2) async {
        reset(); ownerID = user
        let ticket = generation
        while !Task.isCancelled && generation == ticket {
            await refresh(user: user, campaign: campaign, period: period, ticket: ticket)
            do { try await Task.sleep(for: .seconds(15)) } catch { break }
        }
        if generation == ticket { reset() }
    }
    private func refresh(user: UUID, campaign: UUID, period: WolfyPackPeriodV2, ticket: UUID) async {
        guard !saving else { return }
        let revision = mutation
        do {
            guard try await client.auth.session.user.id == user else { reset(); return }
            struct Params: Encodable { let p_campaign: UUID; let p_period: String }
            let response = try await client.rpc("wolfy_pack_stats", params: Params(p_campaign: campaign, p_period: period.rawValue)).execute()
            let next = try JSONDecoder().decode(WolfyPackStatsV2.self, from: response.data)
            guard !Task.isCancelled, generation == ticket, revision == mutation else { return }
            guard try await client.auth.session.user.id == user, next.version == 2,
                  !next.enabled || (next.campaign_id == campaign && next.period == period) else { reset(); return }
            guard generation == ticket else { return }
            snapshot = next; error = nil
        } catch {
            guard generation == ticket, revision == mutation else { return }
            snapshot = nil; self.error = "Pack statistics are unavailable. Please try again later."
        }
    }
    func save(goals: WolfyPackStatsV2.Goals, timezone: String, user: UUID, campaign: UUID) async -> Bool {
        guard !saving, snapshot?.manager == true, snapshot?.campaign_id == campaign else { return false }
        let ticket = generation
        saving = true; mutation += 1
        defer { if generation == ticket { saving = false } }
        do {
            guard try await client.auth.session.user.id == user else { reset(); return false }
            struct Params: Encodable {
                let p_campaign: UUID; let p_doors: Int?; let p_conversations: Int?
                let p_appointments: Int?; let p_verified_sales: Int?; let p_timezone: String
                // RPC parameters must include explicit nulls when a manager removes a goal.
                enum CodingKeys: String, CodingKey { case p_campaign, p_doors, p_conversations, p_appointments, p_verified_sales, p_timezone }
                func encode(to encoder: Encoder) throws {
                    var c = encoder.container(keyedBy: CodingKeys.self)
                    try c.encode(p_campaign, forKey: .p_campaign); try c.encode(p_timezone, forKey: .p_timezone)
                    try c.encode(p_doors, forKey: .p_doors); try c.encode(p_conversations, forKey: .p_conversations)
                    try c.encode(p_appointments, forKey: .p_appointments); try c.encode(p_verified_sales, forKey: .p_verified_sales)
                }
            }
            _ = try await client.rpc("wolfy_pack_set_goals", params: Params(p_campaign: campaign, p_doors: goals.doors,
                p_conversations: goals.conversations, p_appointments: goals.appointments,
                p_verified_sales: goals.verified_sales, p_timezone: timezone)).execute()
            guard generation == ticket, try await client.auth.session.user.id == user else { return false }
            error = nil
            return true
        } catch {
            if generation == ticket {
                self.error = "Goals could not be confirmed. The reporting timezone cannot change after campaign activity begins."
            }
            return false
        }
    }
}

struct WolfyPackStatsViewV2: View {
    let campaign: UUID
    let name: String
    var selectedUser: UUID? = nil
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var store = WolfyPackStatsStoreV2()
    @Environment(\.scenePhase) private var phase
    @State private var period: WolfyPackPeriodV2 = .today
    @State private var showGoals = false
    @State private var refreshID = UUID()
    var body: some View {
        List {
            Picker("Period", selection: $period) {
                ForEach(WolfyPackPeriodV2.allCases) { value in Text(value.title).tag(value) }
            }
            if let stats = store.snapshot, store.ownerID == auth.user?.id {
                if !stats.enabled { Text("Live Pack is not available yet.").foregroundStyle(.secondary) }
                else {
                    Section("\(name) · \(period.title)") {
                        ForEach(["doors", "conversations", "leads", "appointments", "verified_sales"], id: \.self) { metric in
                            LabeledContent(title(metric), value: (stats.totals?[metric] ?? 0).formatted())
                        }
                        Text("Campaign doors count each property once per reporting day.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if period == .today, let goals = stats.goals {
                        Section("Daily Pack goals") {
                            goal("Doors", value: stats.totals?["doors"] ?? 0, target: goals.doors)
                            goal("Conversations", value: stats.totals?["conversations"] ?? 0, target: goals.conversations)
                            goal("Appointments", value: stats.totals?["appointments"] ?? 0, target: goals.appointments)
                            goal("Verified sales", value: stats.totals?["verified_sales"] ?? 0, target: goals.verified_sales)
                            if [goals.doors, goals.conversations, goals.appointments, goals.verified_sales].allSatisfy({ $0 == nil }) {
                                Text("No daily goals configured.").foregroundStyle(.secondary)
                            }
                            if stats.manager == true { Button("Configure Pack Goals") { showGoals = true } }
                        }
                    }
                    Section(selectedUser == nil ? "Leaderboard · Doors" : "Rep statistics") {
                        ForEach((stats.members ?? []).filter { selectedUser == nil || $0.id == selectedUser }) { member in
                            DisclosureGroup {
                                LabeledContent("Doors", value: member.doors.formatted())
                                LabeledContent("Conversations", value: member.conversations.formatted())
                                LabeledContent("Leads", value: member.leads.formatted())
                                LabeledContent("Appointments", value: member.appointments.formatted())
                                LabeledContent("Verified sales", value: member.verified_sales.formatted())
                                if let rate = member.conversion { LabeledContent("Conversation / door", value: rate.formatted(.percent.precision(.fractionLength(1)))) }
                                LabeledContent("Earned XP · \(period.title)", value: member.earned_xp.formatted())
                                LabeledContent("Current session streak · live", value: member.current_session_streak.formatted())
                                if let value = member.revenue_minor {
                                    LabeledContent("Verified revenue", value: FieldSalesService.money(value, currency: stats.currency))
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(member.first_name)
                                        Text((WolfyStage(rawValue: member.stage) ?? .pup).title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(); Text("\(member.doors) doors")
                                }
                            }
                        }
                    }
                    Text("Reporting timezone: \(stats.timezone ?? "UTC")").font(.footnote).foregroundStyle(.secondary)
                }
            } else if let error = store.error { Text(error).foregroundStyle(.secondary) }
            else { ProgressView("Loading Pack statistics") }
        }
        .navigationTitle("Pack Stats")
        .task(id: "\(auth.user?.id.uuidString ?? ""):\(campaign):\(period.rawValue):\(phase):\(refreshID)") {
            showGoals = false
            if phase == .active, let user = auth.user?.id { await store.observe(user: user, campaign: campaign, period: period) }
            else { store.reset() }
        }
        .onDisappear { store.reset() }
        .sheet(isPresented: $showGoals, onDismiss: { refreshID = UUID() }) {
            if let stats = store.snapshot, let goals = stats.goals, let user = auth.user?.id {
                WolfyPackGoalEditorV2(goals: goals, timezone: stats.timezone ?? "UTC", store: store, user: user, campaign: campaign)
            }
        }
    }
    @ViewBuilder private func goal(_ label: String, value: Int, target: Int?) -> some View {
        if let target { LabeledContent(label, value: "\(value.formatted()) / \(target.formatted())") }
    }
    private func title(_ metric: String) -> String { metric.replacingOccurrences(of: "_", with: " ").capitalized }
}

private struct WolfyPackGoalEditorV2: View {
    @State private var doors: String
    @State private var conversations: String
    @State private var appointments: String
    @State private var sales: String
    @State var timezone: String
    @ObservedObject var store: WolfyPackStatsStoreV2
    let user: UUID
    let campaign: UUID
    @Environment(\.dismiss) private var dismiss
    init(goals: WolfyPackStatsV2.Goals, timezone: String, store: WolfyPackStatsStoreV2, user: UUID, campaign: UUID) {
        _doors = State(initialValue: goals.doors.map(String.init) ?? "")
        _conversations = State(initialValue: goals.conversations.map(String.init) ?? "")
        _appointments = State(initialValue: goals.appointments.map(String.init) ?? "")
        _sales = State(initialValue: goals.verified_sales.map(String.init) ?? "")
        _timezone = State(initialValue: timezone); self.store = store; self.user = user; self.campaign = campaign
    }
    private var valid: Bool {
        [doors, conversations, appointments, sales].allSatisfy { $0.isEmpty || (Int($0).map { $0 > 0 && $0 <= Int(Int32.max) } ?? false) }
        && TimeZone(identifier: timezone) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Daily goals") {
                    TextField("Doors", text: $doors).keyboardType(.numberPad)
                    TextField("Conversations", text: $conversations).keyboardType(.numberPad)
                    TextField("Appointments", text: $appointments).keyboardType(.numberPad)
                    TextField("Verified sales", text: $sales).keyboardType(.numberPad)
                    Text("Leave a field empty to remove that goal. Pack achievements do not add personal XP.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Reporting timezone") {
                    TextField("Timezone", text: $timezone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Fixed after campaign activity begins.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Text(error).foregroundStyle(.secondary) }
            }.navigationTitle("Pack Goals").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.saving ? "Saving…" : "Save") {
                        Task {
                            let goals = WolfyPackStatsV2.Goals(doors: Int(doors), conversations: Int(conversations), appointments: Int(appointments), verified_sales: Int(sales))
                            if await store.save(goals: goals, timezone: timezone, user: user, campaign: campaign) { dismiss() }
                        }
                    }.disabled(!valid || store.saving)
                }
            }
        }
    }
}
