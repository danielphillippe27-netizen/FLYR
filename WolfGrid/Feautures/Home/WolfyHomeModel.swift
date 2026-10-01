import Foundation
import Combine
import Supabase

struct WolfyGoals: Codable, Equatable {
    var daily_door_goal: Int?
    var weekly_door_goal: Int?
    /// ISO weekdays: Monday = 1, Sunday = 7.
    var door_goal_days: [Int]?
    var scheduledDays: [Int] { door_goal_days ?? [1, 2, 3, 4, 5] }
    func dailyTarget(on date: Date = Date(), calendar: Calendar = .current) -> Int? {
        let day = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        return scheduledDays.contains(day) ? daily_door_goal : nil
    }
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
    var weeklyMetrics: WolfyMetrics?
    var goals: WolfyGoals?
    var stats: UserStats?
    var overdueFollowUps: Int?
    var unavailable: [String] = []
}

@MainActor
final class WolfyHomeModel: ObservableObject {
    @Published var summary = WolfyHomeSummary()
    @Published var isLoading = false
    @Published var updatedAt: Date?
    @Published private(set) var assignments: [CampaignAssignmentSummary] = []
    @Published private(set) var assignmentsUnavailable = false
    private var loadingAssignments = false
    private var generation = UUID()
    private var primaryUnavailable: [String] = []
    private var secondaryUnavailable: [String] = []
    private var scopedUserID: UUID?
    private let client = SupabaseManager.shared.client

    private struct LoadResult<Value> {
        let value: Value?
        let unavailable: String?
    }

    private struct CoachContextCounts: Decodable {
        let overdue: Int
    }

    func clear() {
        generation = UUID()
        summary = WolfyHomeSummary()
        assignments = []
        assignmentsUnavailable = false
        updatedAt = nil
        isLoading = false
        primaryUnavailable = []
        secondaryUnavailable = []
    }

    /// Refreshes only the values required to render the weekly Home dashboard.
    /// Secondary content deliberately does not extend pull-to-refresh.
    func loadPrimary(userID: UUID, workspaceID: UUID) async {
        if !NetworkMonitor.shared.isOnline, updatedAt != nil { return }
        scopedUserID = userID
        let request = UUID()
        generation = request
        isLoading = true
        defer {
            if generation == request { isLoading = false }
        }
        let now = Date()
        let calendar = Calendar.current
        struct MetricsParams: Encodable {
            let p_workspace: UUID
            let p_day: Date
            let p_week: Date
            let p_until: Date
        }

        let weekStart = WolfyHomePolicy.weekStart(now: now)
        async let metricsResult: LoadResult<WolfyMetrics> = capture("Today's activity") {
            try await client.rpc("wolfy_home_metrics", params: MetricsParams(
                p_workspace: workspaceID, p_day: calendar.startOfDay(for: now),
                p_week: weekStart, p_until: now
            )).execute().value
        }
        async let weeklyMetricsResult: LoadResult<WolfyMetrics> = capture("This week's activity") {
            try await client.rpc("wolfy_home_metrics", params: MetricsParams(
                p_workspace: workspaceID, p_day: weekStart,
                p_week: weekStart, p_until: now
            )).execute().value
        }
        async let goalsResult: LoadResult<WolfyGoals> = capture("Goals") {
            let rows: [WolfyGoals] = try await self.client.from("user_profiles")
                .select("daily_door_goal,weekly_door_goal,door_goal_days").eq("user_id", value: userID).execute().value
            return rows.first ?? WolfyGoals()
        }
        let (metrics, weeklyMetrics, goals) = await (metricsResult, weeklyMetricsResult, goalsResult)
        guard generation == request, !Task.isCancelled else { return }
        summary.metrics = metrics.value
        summary.weeklyMetrics = weeklyMetrics.value
        summary.goals = goals.value
        primaryUnavailable = [metrics.unavailable, weeklyMetrics.unavailable, goals.unavailable].compactMap { $0 }
        syncUnavailable()
        updatedAt = now
    }

    /// Refreshes supporting Home content without holding the pull-to-refresh gesture open.
    func loadSecondary(userID: UUID, workspaceID: UUID) async {
        guard NetworkMonitor.shared.isOnline else { return }
        let request = generation
        async let statsResult: LoadResult<UserStats?> = capture("XP and streak") {
            try await StatsService.shared.fetchUserStats(userID: userID)
        }
        async let overdueResult: LoadResult<Int> = capture("Follow-ups") {
            struct Params: Encodable { let p_workspace: UUID; let p_timezone: String }
            let context: CoachContextCounts = try await self.client.rpc(
                "wolfy_coach_context",
                params: Params(p_workspace: workspaceID, p_timezone: TimeZone.current.identifier)
            ).execute().value
            return context.overdue
        }
        async let salesResult: LoadResult<FieldSalesSnapshot?> = capture(nil) {
            let gate = try await FieldSalesService.bootstrap(workspaceID)
            guard gate.enabled else { return nil }
            return try await FieldSalesService.snapshot(.init(p_workspace: workspaceID))
        }
        let (stats, overdue, sales) = await (statsResult, overdueResult, salesResult)
        guard generation == request, !Task.isCancelled,
              AuthManager.shared.user?.id == userID,
              WorkspaceContext.shared.workspaceId == workspaceID else { return }
        summary.stats = stats.value ?? nil
        summary.overdueFollowUps = overdue.value
        summary.sales = sales.value ?? nil
        secondaryUnavailable = [stats.unavailable, overdue.unavailable, sales.unavailable].compactMap { $0 }
        syncUnavailable()
    }

    private func capture<Value>(_ unavailable: String?, operation: () async throws -> Value) async -> LoadResult<Value> {
        do { return LoadResult(value: try await operation(), unavailable: nil) }
        catch { return LoadResult(value: nil, unavailable: unavailable) }
    }

    private func syncUnavailable() {
        summary.unavailable = primaryUnavailable + secondaryUnavailable
    }

    func loadAssignments(userID: UUID, workspaceID: UUID) async {
        guard !loadingAssignments else { return }
        guard NetworkMonitor.shared.isOnline else { return }
        loadingAssignments = true
        defer { loadingAssignments = false }
        do {
            let response = try await CampaignAssignmentsAPI.shared.fetchAssignments(workspaceId: workspaceID)
            guard !Task.isCancelled, AuthManager.shared.user?.id == userID,
                  WorkspaceContext.shared.workspaceId == workspaceID else { return }
            assignments = response.assignments.filter {
                $0.workspaceId == workspaceID && $0.isActive &&
                ($0.assignedToUserId == userID || $0.assignedToUserId == nil) &&
                !["archived", "completed", "cancelled", "canceled"].contains($0.campaign?.status?.lowercased() ?? "")
            }
            assignmentsUnavailable = false
            let scope = AssignmentBellScope(userID: userID, workspaceID: workspaceID)
            AssignmentBellStore.shared.activate(scope)
            AssignmentBellStore.shared.recordPendingAssignments(Set(assignments.filter {
                $0.assignedToUserId == userID && $0.status.lowercased() == "assigned"
            }.map(\.id)), for: scope)
        } catch {
            guard !Task.isCancelled, AuthManager.shared.user?.id == userID,
                  WorkspaceContext.shared.workspaceId == workspaceID else { return }
            assignmentsUnavailable = true
        }
    }

    func saveGoals(daily: Int?, weekly: Int?, days: [Int]) async throws {
        guard daily.map({ $0 > 0 }) ?? true, weekly.map({ $0 > 0 }) ?? true else {
            throw NSError(domain: "WolfyGoals", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a positive door target."])
        }
        guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
            throw NSError(domain: "WolfyGoals", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose at least one goal day."])
        }
        guard let userID = scopedUserID else { throw CancellationError() }
        struct Params: Encodable {
            let p_user: UUID
            let p_daily: Int?
            let p_weekly: Int?
            let p_days: [Int]
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_user, forKey: .p_user)
                try c.encode(p_daily, forKey: .p_daily)
                try c.encode(p_weekly, forKey: .p_weekly)
                try c.encode(p_days, forKey: .p_days)
            }
            enum CodingKeys: String, CodingKey { case p_user, p_daily, p_weekly, p_days }
        }
        let request = generation
        let saved: WolfyGoals = try await client.rpc("wolfy_save_personal_goals", params: Params(p_user: userID, p_daily: daily, p_weekly: weekly, p_days: days.sorted())).execute().value
        guard generation == request else { throw CancellationError() }
        summary.goals = saved
    }
}
