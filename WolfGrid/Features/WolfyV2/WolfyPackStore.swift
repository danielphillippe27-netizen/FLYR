import Foundation
import Combine
import Supabase

struct WolfyPackMemberV2: Decodable, Identifiable {
    let user_id: UUID
    let first_name: String
    let stage: Int
    let session_id: UUID
    let is_paused: Bool?
    let start_time: Date
    let active_seconds: Int?
    let heartbeat_at: Date?
    let fix: WolfyPackFixV2?
    let activity: String
    let last_activity_at: Date?
    var id: UUID { user_id }
    var evolution: WolfyStage { WolfyStage(rawValue: stage) ?? .pup }
    func freshness(now: Date) -> WolfyPackFreshnessV2 {
        WolfyPackPresencePolicyV2.freshness(fix: fix, permitted: fix != nil, activeSession: is_paused != true, now: now)
    }
}
struct WolfyPackEventV2: Decodable, Identifiable {
    struct Details: Decodable { let metric: String?; let target: Int?; let reporting_day: String? }
    let details: Details?
    var priority: Int { kind == "pack_goal" ? 100 : kind == "pack_milestone" ? 90 : 10 }
    /// Renderers join an already-started event at its current phase; expired events never replay.
    func phase(at serverTime: Date) -> Double? {
        guard serverTime >= starts_at, serverTime < expires_at else { return nil }
        return serverTime.timeIntervalSince(starts_at) / expires_at.timeIntervalSince(starts_at)
    }
    let id: UUID
    let campaign_id: UUID
    let actor_id: UUID?
    let recipient_id: UUID?
    let kind: String
    let created_at: Date
    let starts_at: Date
    let expires_at: Date
    let animation_seed: Int
}
struct WolfyPackSnapshotV2: Decodable {
    let version: Int
    let enabled: Bool
    let server_time: Date
    let manager: Bool?
    let summary: [String: Int]?
    let members: [WolfyPackMemberV2]
    let events: [WolfyPackEventV2]
}

/// Scoped, ephemeral projection. Precise Pack locations are never written to disk.
/// Failure clears the projection; a previous successful response cannot retain revoked access.
@MainActor final class WolfyPackStoreV2: ObservableObject {
    @Published private(set) var snapshot: WolfyPackSnapshotV2?
    @Published private(set) var error: String?
    @Published private(set) var announcement: String?
    @Published private(set) var synchronizedEvent: WolfyPackEventV2?
    private(set) var serverOffset: TimeInterval = 0
    private var user: UUID?
    private var campaign: UUID?
    private var generation = UUID()
    private var cursor: Date?
    private var seenEvents: [UUID: Date] = [:]
    private var budget = WolfyPackPresentationBudgetV2()
    private let client = SupabaseManager.shared.client

    func reset() {
        generation = UUID(); snapshot = nil; cursor = nil; seenEvents.removeAll()
        announcement = nil; synchronizedEvent = nil; error = nil; user = nil; campaign = nil; serverOffset = 0
        budget = WolfyPackPresentationBudgetV2()
    }
    func observe(user: UUID, campaign: UUID) async {
        reset(); self.user = user; self.campaign = campaign
        let ticket = generation
        while !Task.isCancelled && ticket == generation {
            await refresh(ticket: ticket)
            do { try await Task.sleep(for: .seconds(5)) } catch { break }
        }
        if ticket == generation { reset() }
    }
    private func refresh(ticket: UUID) async {
        guard let user, let campaign else { return }
        do {
            let session = try await client.auth.session
            guard session.user.id == user, ticket == generation else { reset(); return }
            struct Params: Encodable { let p_campaign: UUID; let p_after: Date? }
            let response = try await client.rpc("wolfy_pack_snapshot", params: Params(p_campaign: campaign, p_after: cursor)).execute()
            let next = try JSONDecoder.supabaseDates.decode(WolfyPackSnapshotV2.self, from: response.data)
            guard !Task.isCancelled, ticket == generation else { return }
            guard next.version == 2 else { throw CocoaError(.coderInvalidValue) }
            let returning = cursor != nil
            snapshot = next; error = nil; announcement = nil
            serverOffset = next.server_time.timeIntervalSince(Date())
            // A small overlap avoids losing equal-timestamp events; IDs suppress repeats.
            cursor = next.server_time.addingTimeInterval(-1)
            seenEvents = seenEvents.filter { $0.value > next.server_time }
            if let event = synchronizedEvent, event.expires_at <= next.server_time { synchronizedEvent = nil }
            if returning {
                for event in next.events.sorted(by: { $0.priority == $1.priority ? $0.created_at > $1.created_at : $0.priority > $1.priority }) {
                    guard seenEvents[event.id] == nil, event.expires_at > next.server_time else { continue }
                    seenEvents[event.id] = event.expires_at
                    guard event.kind == "pack_goal" || event.kind == "pack_milestone" || (event.kind == "howl" && event.recipient_id == user),
                          budget.banner(now: next.server_time) else { continue }
                    if event.kind == "howl" {
                        let actor = next.members.first { $0.id == event.actor_id }?.first_name ?? "A teammate"
                        announcement = "\(actor) sent you a howl 🐺"
                    } else {
                        synchronizedEvent = event
                        if let metric = event.details?.metric, let target = event.details?.target {
                            announcement = "Pack reached \(target.formatted()) \(metric.replacingOccurrences(of: "_", with: " "))!"
                        } else { announcement = "Your Pack reached a goal!" }
                    }
                }
            } else if let summary = next.summary {
                let goals = summary["goals"] ?? 0, milestones = summary["milestones"] ?? 0
                if goals + milestones > 0 {
                    announcement = "Recent Pack achievements: \(goals) goals and \(milestones) door milestones."
                }
            }
        } catch {
            guard ticket == generation else { return }
            snapshot = nil; announcement = nil; synchronizedEvent = nil; cursor = nil
            self.error = "Live Pack is unavailable. Your campaign remains available."
        }
    }
    func sendHowl(to recipient: UUID, request: UUID) async throws {
        guard let user, let campaign, snapshot?.enabled == true,
              try await client.auth.session.user.id == user else { throw CocoaError(.userCancelled) }
        struct Params: Encodable { let p_campaign: UUID; let p_recipient: UUID; let p_request: UUID }
        _ = try await client.rpc("wolfy_pack_send_howl", params: Params(p_campaign: campaign, p_recipient: recipient, p_request: request)).execute()
    }
}
