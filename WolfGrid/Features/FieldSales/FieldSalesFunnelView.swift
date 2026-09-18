import SwiftUI
import Supabase

private struct FieldSalesFunnelSnapshot: Decodable {
    let enabled: Bool; let currency: String; let timezone: String; let total_records: Int; let has_more: Bool
    let rows: [Row]
    struct Row: Decodable, Identifiable {
        let id: UUID; let contact_id: UUID?; let sale_id: UUID?; let label: String; let occurred_at: String
        let converted: Bool?; let value_minor: String?
    }
}
struct FieldSalesFunnelView: View {
    let workspace: UUID; let filter: [String: String]; let stage: String
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        Group {
            if let user = auth.user?.id, context.workspaceId == workspace {
                FieldSalesFunnelContent(workspace: workspace, filter: filter, stage: stage).id("\(user):\(workspace):\(stage)")
            } else { ContentUnavailableView("Records unavailable", systemImage: "list.bullet", description: Text("Return to the selected workspace.")) }
        }
    }
}
private struct FieldSalesFunnelContent: View {
    let workspace: UUID; let filter: [String: String]; let stage: String
    @State private var data: FieldSalesFunnelSnapshot?
    @State private var offset = 0
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } } }
            if let d = data {
                Section("\(d.total_records) records · \(d.timezone)") {
                    ForEach(d.rows) { row in
                        if let sale = row.sale_id { NavigationLink { FieldSalesRecordView(sale: sale) } label: { rowLabel(row, d) } }
                        else { rowLabel(row, d) }
                    }
                    if d.rows.isEmpty { Text("No records in this period.").foregroundStyle(.secondary) }
                }
                Section { HStack { Button("Previous") { offset = max(0, offset - 50) }.disabled(offset == 0); Spacer(); Button("Next") { offset += 50 }.disabled(!d.has_more) } }
            } else if error == nil { ProgressView("Loading records…") }
        }
        .navigationTitle(stage.replacingOccurrences(of: "_", with: " ").capitalized)
        .task(id: offset) { await reload() }
        .refreshable { await reload() }
        .onDisappear { generation = UUID() }
    }
    private func rowLabel(_ row: FieldSalesFunnelSnapshot.Row, _ d: FieldSalesFunnelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.label).fontWeight(.medium)
            Text(FieldSalesService.timestamp(row.occurred_at, timezone: d.timezone)).font(.caption).foregroundStyle(.secondary)
            if row.converted == true { Text("Linked verified sale").font(.caption).foregroundStyle(.secondary) }
            if let amount = row.value_minor { Text(FieldSalesService.money(amount, currency: d.currency)).monospacedDigit() }
        }
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        struct Params: Encodable { let p_workspace: UUID; let p_filter: [String: String]; let p_kind: String }
        var selection = filter; selection["offset"] = String(offset); selection["limit"] = "50"
        do {
            let next: FieldSalesFunnelSnapshot = try await SupabaseManager.shared.client.rpc("field_sales_drilldown", params: Params(p_workspace: workspace, p_filter: selection, p_kind: stage)).execute().value
            guard ticket == generation, !Task.isCancelled else { return }; data = next; error = nil
        } catch { guard ticket == generation, !Task.isCancelled else { return }; data = nil; self.error = error.localizedDescription }
    }
}
