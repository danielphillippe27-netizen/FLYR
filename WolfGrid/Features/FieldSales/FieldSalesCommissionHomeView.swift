import SwiftUI
import Supabase

private struct CommissionHomeSnapshot: Decodable {
    let enabled: Bool
    let needs_setup: Bool?
    let commission_visible: Bool?
    let currency: String?
    let week_start: String?
    let through: String?
    let weekly_sales: Int?
    let daily_sales: Int?
    let weekly_commission_minor: String?
    let daily_commission_minor: String?
    let weekly_target_minor: String?
    let weekly_missing: Int?
    let daily_missing: Int?
    let note: String?
}

struct FieldSalesCommissionHomeView: View {
    var refreshToken: String?
    var showsHeader = true
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        if let user = auth.user?.id, let workspace = context.workspaceId {
            CommissionHomeContent(workspace: workspace, refreshToken: refreshToken, showsHeader: showsHeader).id("\(user):\(workspace)")
        }
    }
}

private struct CommissionHomeContent: View {
    let workspace: UUID
    let refreshToken: String?
    let showsHeader: Bool
    @Environment(\.scenePhase) private var scene
    @State private var data: CommissionHomeSnapshot?
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if showsHeader {
                HStack {
                    Text("THIS WEEK").font(.caption.weight(.medium)).tracking(1).foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink { FieldSalesGoalsView() } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("Sales goals")
                }
            }
            if let d = data {
                if !d.enabled { Text("Sales is not enabled for this workspace.").foregroundStyle(.secondary) }
                else if d.needs_setup == true { Text("Set up Sales in More to see commission.").foregroundStyle(.secondary) }
                else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) { ring(d).frame(width: 190, height: 190); sideMetrics(d).frame(width: 110, alignment: .leading) }
                        VStack(spacing: 24) { ring(d).frame(width: 230, height: 230); sideMetrics(d) }
                    }
                    if d.commission_visible != true {
                        Text("Commission visibility is controlled by your workspace manager.").font(.caption).foregroundStyle(.secondary)
                    } else if let missing = d.weekly_missing, missing > 0 {
                        Text("Commission is missing on \(missing) verified \(missing == 1 ? "sale" : "sales"). Shown amounts include only recorded commission.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = d.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            } else if error == nil { ProgressView("Loading sales…") }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary); Button("Retry sales") { Task { await reload() } } }
        }
        .task(id: refreshToken) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .onChange(of: scene) { _, phase in if phase == .active { Task { await reload() } } }
        .onDisappear { generation = UUID() }
    }
    private func amount(_ value: String?, _ d: CommissionHomeSnapshot, missing: Int?) -> String {
        guard d.commission_visible == true else { return "—" }
        if value == "0", (missing ?? 0) > 0 { return "—" }
        return FieldSalesService.money(value, currency: d.currency)
    }
    private func ring(_ d: CommissionHomeSnapshot) -> some View {
        let actual = Double(d.weekly_commission_minor ?? "") ?? 0
        let target = Double(d.weekly_target_minor ?? "") ?? 0
        let progress = target > 0 ? min(1, max(0, actual / target)) : 0
        return ZStack {
            Circle().stroke(Color(uiColor: .secondarySystemBackground), lineWidth: 10)
            Circle().trim(from: 0, to: progress).stroke(Color.green, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 9) {
                Text(amount(d.weekly_commission_minor, d, missing: d.weekly_missing)).font(.system(size: 35, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                Text("GROSS COMMISSION").font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(.secondary)
                if let target = d.weekly_target_minor { Text("of \(FieldSalesService.money(target, currency: d.currency))").font(.caption).foregroundStyle(.secondary) }
                else { Text("THIS WEEK").font(.caption2).foregroundStyle(.secondary) }
            }.padding(20)
        }.padding(6).accessibilityElement(children: .combine)
    }
    private func sideMetrics(_ d: CommissionHomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text(amount(d.daily_commission_minor, d, missing: d.daily_missing)).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text("DAILY EARNED").font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(.secondary)
                Text("Estimated commission").font(.caption2).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 6) {
                Text(d.weekly_sales.map(String.init) ?? "—").font(.title2.weight(.semibold)).monospacedDigit()
                Text("SALES CLOSED").font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(.secondary)
                Text("This week").font(.caption2).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
        }
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        struct Params: Encodable { let p_workspace: UUID }
        do {
            let next: CommissionHomeSnapshot = try await SupabaseManager.shared.client.rpc("field_sales_commission_home", params: Params(p_workspace: workspace)).execute().value
            guard generation == ticket, !Task.isCancelled else { return }
            data = next; error = nil
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            data = nil; self.error = "Sales commission could not refresh."
        }
    }
}
