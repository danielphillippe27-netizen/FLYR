import SwiftUI

struct FieldSalesHomeCard: View {
    let data: FieldSalesSnapshot
    var body: some View {
        if data.enabled {
            NavigationLink { FieldSalesRootView() } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label("Sales · Beta", systemImage: "chart.line.uptrend.xyaxis").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                    if let totals = data.totals {
                        HStack {
                            VStack(alignment: .leading) { Text("\(totals.weekly_sales) this week").font(.title3.bold()); Text(FieldSalesService.money(totals.weekly_revenue_minor, currency: data.currency)) }
                            Spacer()
                            VStack(alignment: .leading) { Text("\(totals.monthly_sales) this month").font(.title3.bold()); Text(FieldSalesService.money(totals.monthly_revenue_minor, currency: data.currency)) }
                        }
                        if let goal = data.goal, let target = goal.target {
                            Text("\(goal.completed) / \(target) monthly sales · \(goal.remaining ?? 0) remaining")
                            ProgressView(value: Double(min(goal.completed, target)), total: Double(target))
                        } else { Text("Set a monthly sales target").font(.subheadline) }
                        if let win = data.feed?.first { Text("Latest team win: \(win.rep_name) · \(win.sold_on)").font(.caption).foregroundStyle(.secondary) }
                    } else { Text("An owner must select the reporting currency and timezone.").font(.subheadline) }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
        }
    }
}

struct FieldSalesEntryLink: View {
    var leadID: UUID? = nil
    var leaderboard = false
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var enabledScope: String?
    private var scope: String { "\(auth.user?.id.uuidString ?? ""):\(workspace.workspaceId?.uuidString ?? "")" }
    var body: some View {
        Group {
            if enabledScope == scope {
                NavigationLink(leaderboard ? "Sales & Revenue leaderboard · Beta" : "Record Sale · Beta") { FieldSalesRootView(leadID: leadID, leaderboardOnly: leaderboard) }
            }
        }.task(id: scope) {
            enabledScope = nil
            let key = scope
            guard let space = workspace.workspaceId, auth.user != nil else { return }
            if let data = try? await FieldSalesService.bootstrap(space), data.enabled, !Task.isCancelled, key == scope { enabledScope = key }
        }
    }
}
