import SwiftUI
import Supabase

private struct ProSalesHomeSnapshot: Decodable {
    let enabled: Bool; let needs_setup: Bool?; let scope: String?; let currency: String?; let week_start: String?; let through: String?
    let weekly: Summary?; let monthly: Summary?; let daily: Summary?; let activity: Activity?; let active_goals: [Goal]?
    let pending_review: Int?; let latest_sale: Sale?; let ranking: Ranking?; let notes: String?
    struct Summary: Decodable { let sales: Int; let sold_value_minor: String?; let completed_value_minor: String?; let collected_revenue_minor: String? }
    struct Activity: Decodable { let doors: Int; let conversations: Int; let leads: Int; let appointments: Int; let close_rate: String? }
    struct Goal: Decodable, Identifiable { let id: UUID; let title: String; let unit: String; let target: String; let actual: String?; let remaining: String?; let progress_percent: String?; let required_daily: String? }
    struct Sale: Decodable { let id: UUID; let rep_name: String; let sold_on: String; let value_minor: String? }
    struct Ranking: Decodable { let metric: String?; let top: Rank?; let own: Rank?; enum CodingKeys: String, CodingKey { case metric, top; case own = "self" } }
    struct Rank: Decodable { let rep_name: String; let rank: Int; let value: String }
}
struct FieldSalesProHomeView: View {
    var refreshToken: String? = nil
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        if let user = auth.user?.id, let workspace = context.workspaceId { ProSalesHomeContent(workspace: workspace, refreshToken: refreshToken).id("\(user):\(workspace)") }
    }
}
private struct ProSalesHomeContent: View {
    let workspace: UUID; let refreshToken: String?
    @State private var data: ProSalesHomeSnapshot?
    @State private var error: String?
    @State private var generation = UUID()
    @Environment(\.scenePhase) private var scene
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let error { Text(error).font(.caption).foregroundStyle(.secondary); Button("Retry performance") { Task { await reload() } } }
            if let d = data, d.enabled {
                if d.needs_setup == true { NavigationLink("Set up Sales") { FieldSalesRootView() } }
                else { performance(d) }
            } else if data == nil && error == nil { ProgressView("Loading performance…") }
        }.task(id: refreshToken) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .onChange(of: scene) { _, phase in if phase == .active { Task { await reload() } } }
        .onDisappear { generation = UUID() }
    }
    private func performance(_ d: ProSalesHomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading) { Text(d.scope == "workspace" ? "Team performance" : "This week").font(.title2.bold()); Text("\(d.week_start ?? "") – \(d.through ?? "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); NavigationLink { FieldSalesReportView() } label: { Image(systemName: "arrow.up.right").accessibilityLabel("Full performance report") } }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 18) {
                metric("Sold this week", FieldSalesService.money(d.weekly?.sold_value_minor, currency: d.currency))
                metric("Sales this week", String(d.weekly?.sales ?? 0))
                metric("Sales today", String(d.daily?.sales ?? 0))
                metric("Close rate", d.activity?.close_rate.map { "\($0)%" } ?? "—")
                if d.scope == "workspace" {
                    metric("Sold this month", FieldSalesService.money(d.monthly?.sold_value_minor, currency: d.currency))
                    metric("Sales this month", String(d.monthly?.sales ?? 0))
                    metric("Completed this month", FieldSalesService.money(d.monthly?.completed_value_minor, currency: d.currency))
                    metric("Collected this month", FieldSalesService.money(d.monthly?.collected_revenue_minor, currency: d.currency))
                }
            }
            if let a = d.activity { Text("\(a.doors) doors · \(a.conversations) conversations · \(a.leads) leads · \(a.appointments) appointments").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(d.active_goals ?? []) { g in
                NavigationLink { FieldSalesGoalsView() } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(g.title).font(.headline)
                        Text("\(goalValue(g, g.actual, d.currency)) / \(goalValue(g, g.target, d.currency))").monospacedDigit()
                        if let p = g.progress_percent { ProgressView(value: max(0, min(100, Double(p) ?? 0)), total: 100); Text("\(p)% · \(goalValue(g, g.remaining, d.currency)) remaining").font(.caption) }
                        else { Text("Waiting for enough evidence").font(.caption) }
                        if let daily = g.required_daily { Text("\(goalValue(g, daily, d.currency))/day required").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
            if d.active_goals?.isEmpty == true { NavigationLink("Set a \(d.scope == "workspace" ? "workspace" : "personal") goal") { FieldSalesGoalsView() } }
            if let rank = d.ranking?.own { NavigationLink("Your rank: \(rank.rank) · \((d.ranking?.metric ?? "sales").replacingOccurrences(of: "_", with: " "))") { FieldSalesLeaderboardView() }.font(.subheadline) }
            if d.scope == "workspace", let top = d.ranking?.top, (Decimal(string: top.value) ?? 0)>0 { NavigationLink("Top this week: \(top.rep_name) · Rank \(top.rank)") { FieldSalesLeaderboardView() }.font(.subheadline) }
            if let n = d.pending_review, n>0 { NavigationLink("\(n) pending \(d.scope == "workspace" ? "review" : "verification")") { FieldSalesRootView() }.font(.subheadline) }
            if let sale = d.latest_sale { NavigationLink { FieldSalesRecordView(sale: sale.id) } label: { VStack(alignment: .leading, spacing: 3) { Text("Latest verified sale: \(sale.rep_name)"); Text(sale.sold_on); if let value = sale.value_minor { Text(FieldSalesService.money(value, currency: d.currency)) } }.font(.caption).foregroundStyle(.secondary) } }
            if let notes = d.notes { Text(notes).font(.caption2).foregroundStyle(.secondary) }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.title3.bold()).monospacedDigit(); Text(title).font(.caption).foregroundStyle(.secondary) } }
    private func goalValue(_ g: ProSalesHomeSnapshot.Goal, _ n: String?, _ currency: String?) -> String { guard let n else { return "—" }; return g.unit == "money" ? FieldSalesService.money(n, currency: currency) : n + (g.unit == "percent" ? "%" : "") }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        struct Params: Encodable { let p_workspace: UUID }
        do { let next: ProSalesHomeSnapshot = try await SupabaseManager.shared.client.rpc("field_sales_home", params: Params(p_workspace: workspace)).execute().value; guard generation == ticket, !Task.isCancelled else { return }; data = next; error = nil }
        catch { guard generation == ticket, !Task.isCancelled else { return }; data = nil; self.error = error.localizedDescription }
    }
}
