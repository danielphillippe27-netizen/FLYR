import Foundation
import Combine
import Supabase

struct WolfyGoals: Codable, Equatable {
    var daily_door_goal: Int?
    var weekly_door_goal: Int?
}

struct WolfyMetrics: Decodable {
    let doors: Int
    let conversations: Int
    let leads: Int
    let appointments: Int
    let weekly_doors: Int
}

struct WolfyHomeSummary {
    var sales: FieldSalesSnapshot?
    var metrics: WolfyMetrics?
    var goals: WolfyGoals?
    var stats: UserStats?
    var rank: Int?
    var campaigns: [Campaign]?
    var followUps: [ActivityFeedItem]?
    var appointments: [ActivityFeedItem]?
    var unavailable: [String] = []
}

@MainActor
final class WolfyHomeModel: ObservableObject {
    @Published var summary = WolfyHomeSummary()
    @Published var isLoading = false
    @Published var updatedAt: Date?
    private var generation = UUID()
    private var scopedUserID: UUID?
    private let client = SupabaseManager.shared.client

    func clear() {
        generation = UUID()
        summary = WolfyHomeSummary()
        updatedAt = nil
        isLoading = false
    }

    func load(userID: UUID, workspaceID: UUID) async {
        scopedUserID = userID
        let request = UUID()
        generation = request
        isLoading = true
        var next = WolfyHomeSummary()
        let now = Date()
        let calendar = Calendar.current
        struct MetricsParams: Encodable {
            let p_workspace: UUID
            let p_day: Date
            let p_week: Date
            let p_until: Date
        }
        do {
            next.metrics = try await client.rpc("wolfy_home_metrics", params: MetricsParams(
                p_workspace: workspaceID, p_day: calendar.startOfDay(for: now),
                p_week: WolfyHomePolicy.weekStart(now: now), p_until: now
            )).execute().value
        } catch { next.unavailable.append("Today's activity") }
        do {
            let rows: [WolfyGoals] = try await client.from("user_profiles")
                .select("daily_door_goal,weekly_door_goal").eq("user_id", value: userID).execute().value
            next.goals = rows.first ?? WolfyGoals()
        } catch { next.unavailable.append("Goals") }
        do { next.stats = try await StatsService.shared.fetchUserStats(userID: userID) }
        catch { next.unavailable.append("XP and streak") }
        do {
            let rows = try await LeaderboardService.shared.fetchLeaderboard(metric: "doorknocks", timeframe: "weekly")
            next.rank = rows.firstIndex { $0.id.lowercased() == userID.uuidString.lowercased() }.map { $0 + 1 }
        } catch { next.unavailable.append("Leaderboard") }
        do { next.campaigns = try await CampaignsAPI.shared.fetchCampaigns(workspaceId: workspaceID) }
        catch { next.unavailable.append("Campaigns") }
        do {
            next.followUps = try await ActivityFeedService.shared.fetchItems(userId: userID, workspaceId: workspaceID, includeMembers: false, filter: .followUp, limit: 1000, strictRemote: true)
                .filter { ($0.dueDate ?? .distantFuture) < calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now)!) }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        } catch { next.unavailable.append("Follow-ups") }
        do {
            next.appointments = try await ActivityFeedService.shared.fetchItems(userId: userID, workspaceId: workspaceID, includeMembers: false, filter: .appointments, limit: 1000, strictRemote: true)
                .filter { ($0.dueDate ?? .distantPast) >= now }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        } catch { next.unavailable.append("Appointments") }
        do {
            let gate = try await FieldSalesService.bootstrap(workspaceID)
            if gate.enabled {
                do { next.sales = try await FieldSalesService.snapshot(.init(p_workspace: workspaceID)) }
                catch { next.unavailable.append("Sales") }
            }
        } catch { /* Sales remains gated when its backend is unavailable. */ }
        guard generation == request, !Task.isCancelled else { return }
        summary = next
        updatedAt = now
        isLoading = false
    }

    func saveGoals(daily: Int?, weekly: Int?) async throws {
        guard daily.map({ $0 > 0 }) ?? true, weekly.map({ $0 > 0 }) ?? true else {
            throw NSError(domain: "WolfyGoals", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a positive door target."])
        }
        guard let userID = scopedUserID else { throw CancellationError() }
        struct Params: Encodable {
            let p_user: UUID
            let p_daily: Int?
            let p_weekly: Int?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_user, forKey: .p_user)
                try c.encode(p_daily, forKey: .p_daily)
                try c.encode(p_weekly, forKey: .p_weekly)
            }
            enum CodingKeys: String, CodingKey { case p_user, p_daily, p_weekly }
        }
        let request = generation
        let saved: WolfyGoals = try await client.rpc("wolfy_save_personal_goals", params: Params(p_user: userID, p_daily: daily, p_weekly: weekly)).execute().value
        guard generation == request else { throw CancellationError() }
        summary.goals = saved
    }
}
