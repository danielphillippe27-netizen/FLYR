import SwiftUI
import Combine
import Supabase

struct WolfyPrivateSnapshotV2: Decodable {
    struct Profile: Codable {
        let user_id: UUID
        var sharing_enabled: Bool
        var haptics: WolfyHapticMode
        var sounds: WolfySoundMode
        var team_haptics: Bool
        var camera_emphasis: Bool
        var timezone: String
    }
    struct Configuration: Decodable {
        let personal_enabled: Bool
        let pack_enabled: Bool
        let version: Int
        let thresholds: [Int]
        let rewards: [String: Int]
        var rules: WolfyRulesV2 { .init(version: version, thresholds: thresholds, rewards: rewards) }
    }
    struct Today: Decodable {
        let door_goal: Int
        let doors: Int
        let conversations: Int
        let leads: Int
        let appointments: Int
        let follow_ups: Int
        let verified_sales: Int
    }
    struct Reward: Decodable, Identifiable {
        let id: UUID
        let event_type: String
        let xp: Int
        let created_at: Date
    }
    let version: Int
    let profile: Profile
    let xp: Int
    let stage: Int
    let config: Configuration
    let today: Today
    let current_session_streak: Int
    let recent_rewards: [Reward]
}

/// Lifetime state is held only for the signed-in user, never in the shared Pack store.
@MainActor final class WolfyPrivateStoreV2: ObservableObject {
    @Published private(set) var snapshot: WolfyPrivateSnapshotV2?
    @Published private(set) var error: String?
    @Published private(set) var saving = false
    private var generation = UUID()
    private var mutationRevision = 0
    private let client = SupabaseManager.shared.client

    func reset() { generation = UUID(); snapshot = nil; error = nil; saving = false }
    func observe(user: UUID) async {
        reset()
        let ticket = generation
        while !Task.isCancelled && ticket == generation {
            await refresh(user: user, ticket: ticket)
            do { try await Task.sleep(for: .seconds(5)) } catch { break }
        }
        if ticket == generation { reset() }
    }
    private func refresh(user: UUID, ticket: UUID) async {
        guard !saving else { return }
        let revision = mutationRevision
        do {
            guard try await client.auth.session.user.id == user else { reset(); return }
            let response = try await client.rpc("wolfy_v2_snapshot").execute()
            let next = try JSONDecoder.supabaseDates.decode(WolfyPrivateSnapshotV2.self, from: response.data)
            guard !Task.isCancelled, ticket == generation else { return }
            guard try await client.auth.session.user.id == user, next.profile.user_id == user,
                  next.version == 2, next.config.rules.isValid else { reset(); return }
            guard ticket == generation else { return }
            guard revision == mutationRevision else { return }
            snapshot = next; error = nil
        } catch {
            guard ticket == generation, revision == mutationRevision else { return }
            snapshot = nil; self.error = "Wolfy status is unavailable. Please try again later."
        }
    }
    func save(_ profile: WolfyPrivateSnapshotV2.Profile) async -> Bool {
        guard !saving, snapshot?.profile.user_id == profile.user_id else { return false }
        let ticket = generation
        saving = true
        mutationRevision += 1
        defer { if ticket == generation { saving = false } }
        do {
            guard try await client.auth.session.user.id == profile.user_id else { reset(); return false }
            struct Params: Encodable {
                let p_sharing: Bool; let p_haptics: WolfyHapticMode; let p_sounds: WolfySoundMode
                let p_team_haptics: Bool; let p_camera: Bool; let p_timezone: String
            }
            let response = try await client.rpc("wolfy_v2_preferences", params: Params(
                p_sharing: profile.sharing_enabled, p_haptics: profile.haptics, p_sounds: profile.sounds,
                p_team_haptics: profile.team_haptics, p_camera: profile.camera_emphasis, p_timezone: profile.timezone)).execute()
            let next = try JSONDecoder.supabaseDates.decode(WolfyPrivateSnapshotV2.self, from: response.data)
            guard ticket == generation, !Task.isCancelled,
                  try await client.auth.session.user.id == profile.user_id, next.profile.user_id == profile.user_id else { return false }
            snapshot = next; error = nil
            return true
        } catch {
            if ticket == generation { self.error = "Settings could not be confirmed. Refresh Wolfy status before trying again." }
            return false
        }
    }
}

struct WolfyPrivateStatusView: View {
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var store = WolfyPrivateStoreV2()
    @Environment(\.scenePhase) private var phase
    @State private var preferences: WolfyPrivateSnapshotV2.Profile?
    var body: some View {
        List {
            if let state = store.snapshot, state.profile.user_id == auth.user?.id {
                if !state.config.personal_enabled {
                    Text("New Wolfy progression is not enabled yet.").foregroundStyle(.secondary)
                }
                Section {
                    Label((WolfyStage(rawValue: state.stage) ?? .pup).title, systemImage: "pawprint.fill")
                        .font(.title2.bold())
                    Text("\(state.xp.formatted()) lifetime XP").font(.headline)
                    if let remaining = state.config.rules.remaining(xp: state.xp) {
                        Text("\(remaining.formatted()) XP to your next evolution").foregroundStyle(.secondary)
                    }
                    Text("Your lifetime XP is private. Your Pack sees your evolution stage and permitted campaign activity.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Today") {
                    LabeledContent("Doors", value: "\(state.today.doors) / \(state.today.door_goal)")
                    LabeledContent("Conversations", value: state.today.conversations.formatted())
                    LabeledContent("Leads", value: state.today.leads.formatted())
                    LabeledContent("Appointments", value: state.today.appointments.formatted())
                    LabeledContent("Follow-ups completed", value: state.today.follow_ups.formatted())
                    LabeledContent("Verified sales", value: state.today.verified_sales.formatted())
                    LabeledContent("Current session streak · live", value: state.current_session_streak.formatted())
                }
                Section("Recent XP") {
                    ForEach(state.recent_rewards) { reward in
                        LabeledContent(reward.event_type.replacingOccurrences(of: "_", with: " ").capitalized,
                                       value: "\(reward.xp >= 0 ? "+" : "")\(reward.xp) XP")
                    }
                    if state.recent_rewards.isEmpty { Text("Your next saved activity starts your progress.").foregroundStyle(.secondary) }
                }
                NavigationLink("Follow-ups") { WolfyFollowupsViewV2() }
                Button("Wolfy Settings") { preferences = state.profile }
            } else if let error = store.error { Text(error).foregroundStyle(.secondary) }
            else { ProgressView("Loading Wolfy") }
        }
        .navigationTitle("Your Wolfy")
        .task(id: "\(auth.user?.id.uuidString ?? ""):\(phase)") {
            preferences = nil
            if phase == .active, let user = auth.user?.id { await store.observe(user: user) }
            else { store.reset() }
        }
        .onDisappear { store.reset() }
        .sheet(isPresented: Binding(get: { preferences != nil }, set: { if !$0 { preferences = nil } })) {
            if let profile = preferences {
                WolfyPreferencesViewV2(profile: profile, store: store)
            }
        }
    }
}

private struct WolfyPreferencesViewV2: View {
    @State var profile: WolfyPrivateSnapshotV2.Profile
    @ObservedObject var store: WolfyPrivateStoreV2
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Live Pack") {
                    Toggle("Share during active sessions", isOn: $profile.sharing_enabled)
                    Text("Sharing stops when you pause or end your session. Only authorized teammates and managers can see your location.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Team Haptics", isOn: $profile.team_haptics)
                }
                Section("Personal feedback") {
                    Picker("Haptics", selection: $profile.haptics) {
                        Text("Off").tag(WolfyHapticMode.off)
                        Text("Subtle").tag(WolfyHapticMode.subtle)
                        Text("Full").tag(WolfyHapticMode.full)
                    }
                    Picker("Sound", selection: $profile.sounds) {
                        Text("Off").tag(WolfySoundMode.off)
                        Text("Haptics Only").tag(WolfySoundMode.hapticsOnly)
                        Text("Full").tag(WolfySoundMode.full)
                    }
                    Toggle("Brief camera emphasis", isOn: $profile.camera_emphasis)
                }
                Section("Reporting day") {
                    Text(profile.timezone)
                    Button("Use device timezone") { profile.timezone = TimeZone.current.identifier }
                    Text("An active day's timezone and door goal stay fixed until that day ends.").font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.error { Text(error).foregroundStyle(.secondary) }
            }
            .navigationTitle("Wolfy Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.saving ? "Saving…" : "Save") {
                        Task { if await store.save(profile) { dismiss() } }
                    }.disabled(store.saving)
                }
            }
        }
    }
}
