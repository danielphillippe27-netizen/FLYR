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
    var appointmentID: UUID? = nil
    var campaignID: UUID? = nil
    var propertyKey: String? = nil
    var body: some View {
        FieldSalesVisibility {
            if leaderboard || appointmentID != nil {
                NavigationLink(leaderboard ? "Sales Leaderboard" : "Convert to sale") {
                    FieldSalesRootView(leadID: leadID, leaderboardOnly: leaderboard, appointmentID: appointmentID,
                                       propertyKey: propertyKey, campaignID: campaignID)
                }
            }
        }
    }
}

struct FieldSalesVisibility<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared

    var body: some View {
        if let user = auth.user?.id, let id = workspace.workspaceId {
            FieldSalesVisibleContent(workspace: id, content: content).id("\(user):\(id)")
        }
    }
}

private struct FieldSalesVisibleContent<Content: View>: View {
    let workspace: UUID
    @ViewBuilder var content: () -> Content
    @State private var enabled = false
    @State private var revision = 0
    @Environment(\.scenePhase) private var scene

    var body: some View {
        Group {
            if enabled { content() }
        }
        .task(id: revision) {
            let snapshot = try? await FieldSalesService.bootstrap(workspace)
            if !Task.isCancelled { enabled = snapshot?.enabled == true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in revision += 1 }
        .onChange(of: scene) { _, phase in if phase == .active { revision += 1 } }
    }
}

// Standalone entry for Home variants that do not use the Wolfy Home summary model.
struct FieldSalesHomeModule: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        if let user = auth.user?.id, let workspace = context.workspaceId {
            FieldSalesHomeModuleContent(workspace: workspace).id("\(user):\(workspace)")
        }
    }
}
private struct FieldSalesHomeModuleContent: View {
    let workspace: UUID
    @StateObject private var model = FieldSalesModel()
    @Environment(\.scenePhase) private var scene
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = model.data, data.enabled {
                VStack(alignment: .leading, spacing: 10) {
                    if data.pro_sales_version != nil { FieldSalesProHomeView(refreshToken: data.as_of) }
                    else {
                        FieldSalesHomeCard(data: data)
                        if let coaching = data.coaching { Text("Wolfy: \(coaching)").font(.subheadline) }
                    }
                }
            }
        }.task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .onChange(of: scene) { _, value in if value == .active { Task { await reload() } } }
        .onDisappear { model.cancelPending() }
    }
    private func reload() async { await model.load(.init(p_workspace: workspace)) }
}
