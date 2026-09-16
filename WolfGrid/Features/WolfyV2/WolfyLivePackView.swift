import SwiftUI
import Supabase

/// Native entry remains debug-only until the complete Pack release gate is met.
struct WolfyTeamEntryView: View {
    struct CampaignChoice: Decodable, Identifiable { let id: UUID; let name: String }
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var campaigns: [CampaignChoice] = []
    @State private var error: String?
    var body: some View {
        List {
            NavigationLink("Your Wolfy") { WolfyPrivateStatusView() }
            Section("Live Pack") {
                if let user = auth.user?.id {
                    ForEach(campaigns) { campaign in
                        NavigationLink(campaign.name) { WolfyLivePackView(user: user, campaign: campaign.id, name: campaign.name) }
                    }
                }
                if campaigns.isEmpty { Text(error ?? "No campaigns available").foregroundStyle(.secondary) }
            }
            Section {
                Text("Live locations appear only during shared, active sessions.").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Team")
            .task(id: "\(auth.user?.id.uuidString ?? ""): \(workspace.workspaceId?.uuidString ?? "")") {
                campaigns = []; error = nil
                guard let workspaceID = workspace.workspaceId, let user = auth.user?.id else { return }
                do {
                    let response = try await SupabaseManager.shared.client.from("campaigns").select("id,name").eq("workspace_id", value: workspaceID).order("name").execute()
                    guard !Task.isCancelled, auth.user?.id == user, workspace.workspaceId == workspaceID else { return }
                    campaigns = try JSONDecoder().decode([CampaignChoice].self, from: response.data)
                } catch { self.error = "Campaigns unavailable" }
            }
    }
}
struct WolfyLivePackView: View {
    let user: UUID
    let campaign: UUID
    let name: String
    @StateObject private var store = WolfyPackStoreV2()
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showMap = false
    @State private var selected: WolfyPackMemberV2?
    @State private var howlError: String?
    @State private var sending = false
    @State private var howlRequest = UUID()
    var body: some View {
        List {
            NavigationLink("Campaign Stats & Goals") { WolfyPackStatsViewV2(campaign: campaign, name: name) }
            Section(name) {
                if let message = store.announcement { Text(message).accessibilityAddTraits(.updatesFrequently) }
                if let snapshot = store.snapshot {
                    if !snapshot.enabled { Text("Live Pack is not available yet.").foregroundStyle(.secondary) }
                    #if DEBUG
                    if snapshot.enabled {
                        Toggle("3D Pack Map · Development", isOn: $showMap)
                        if showMap {
                            WolfyPackMapViewV2(inputs: snapshot.members.map { member in
                                WolfyPackMotionV2.Input(id:member.id,stage:member.evolution,fix:member.fix,session:member.session_id,
                                    activity:member.is_paused == true ? .paused : WolfyActivityV2(rawValue:member.activity) ?? .idle,firstName:member.first_name)
                            }, local:user,selected:selected?.id,active:phase == .active,reduceMotion:reduceMotion,
                               serverOffset:store.serverOffset,onSelect:{ id in
                                selected = snapshot.members.first { $0.id == id }; howlRequest = UUID(); howlError = nil
                            }).frame(height:360)
                        }
                    }
                    #endif
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 18) {
                            Text("\(snapshot.members.filter { $0.is_paused != true }.count) ACTIVE · \(snapshot.members.filter { $0.freshness(now: context.date.addingTimeInterval(store.serverOffset)) == .live }.count) LIVE LOCATIONS").font(.caption.bold())
                            ForEach(snapshot.members) { member in
                                Button { selected = member; howlRequest = UUID(); howlError = nil } label: {
                                    HStack {
                                        Image(systemName: "pawprint.fill").foregroundStyle(member.id == user ? .yellow : .secondary)
                                        VStack(alignment: .leading) {
                                            Text(member.first_name + (member.id == user ? " · YOU" : ""))
                                            Text(member.evolution.title).font(.caption).foregroundStyle(.secondary)
                                            if let activity = member.last_activity_at {
                                                Text("Activity \(activity.formatted(.relative(presentation: .numeric)))")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(status(member, now: context.date.addingTimeInterval(store.serverOffset))).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                            if snapshot.members.isEmpty { Text("No active reps in this campaign.").foregroundStyle(.secondary) }
                        }
                    }
                } else if let error = store.error { Text(error).foregroundStyle(.secondary) }
                else { ProgressView("Loading your pack") }
            }
        }.navigationTitle("Live Pack")
            .task(id: phase) {
                if phase == .active { await store.observe(user: user, campaign: campaign) }
                else { store.reset() }
            }
            .onDisappear { store.reset() }
            .sheet(item: $selected) { member in
                NavigationStack {
                    Form {
                        Section(member.first_name) {
                            Text(member.evolution.title)
                            Text(name)
                            NavigationLink("View Stats") { WolfyPackStatsViewV2(campaign: campaign, name: name, selectedUser: member.id) }
                            Text("Activity shared within this campaign").font(.caption)
                        }
                        if member.id != user {
                            Button(sending ? "Sending…" : "Send Howl 🐺") {
                                sending = true
                                Task {
                                    defer { sending = false }
                                    do { try await store.sendHowl(to: member.id, request: howlRequest); selected = nil }
                                    catch { howlError = "Howl unavailable. Check your active session or try again after the cooldown." }
                                }
                            }.disabled(sending)
                        }
                        if let howlError { Text(howlError).foregroundStyle(.secondary) }
                    }.navigationTitle("Wolfy").toolbar { Button("Done") { selected = nil } }
                }.presentationDetents([.medium])
            }
    }
    private func status(_ member: WolfyPackMemberV2, now: Date) -> String {
        if member.is_paused == true { return "Paused" }
        switch member.freshness(now: now) {
        case .stale: return "Location stale"
        case .hidden: return "Location unavailable"
        case .live:
            switch member.activity { case "moving": return "Walking"; case "atDoor": return "At door"; case "conversation": return "Conversation"; default: return "Idle" }
        }
    }
}
