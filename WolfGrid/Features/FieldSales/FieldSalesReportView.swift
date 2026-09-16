import SwiftUI
import Supabase

private struct FieldSalesReport: Decodable {
    let enabled: Bool
    let needs_setup: Bool?
    let currency: String?
    let timezone: String?
    let capabilities: [String: Bool]?
    let period_start: String?
    let period_end: String?
    let previous_start: String?
    let previous_end: String?
    let current_pipeline: Pipeline?
    struct Pipeline: Decodable {
        let available: Bool; let note: String
        let count: Int?; let value_minor: String?; let missing_values: Int?; let stalled: Int?
        let stages: [Stage]?; let losses: [Loss]?
        struct Stage: Decodable, Identifiable { let key: String; let label: String; let count: Int; let value_minor: String?; let stalled: Int; var id: String { key } }
        struct Loss: Decodable { let reason: String; let count: Int; let percent: String }
    }
    let summary: Summary?
    let metrics: Metrics?
    let metric_notes: String?
    let change_percent: [String: String?]?
    let sales: [Sale]?
    let groups: [Group]?
    let total_records: Int?
    let has_more: Bool?
    let options: Options?
    struct Summary: Decodable {
        let sales: Int; let pending_sales: Int; let cancelled_sales: Int
        let sold_value_minor: String?; let gross_sold_minor: String?; let cancellations_minor: String?
        let average_ticket_minor: String?; let completed_value_minor: String?; let collected_revenue_minor: String?
    }
    struct Metrics: Decodable {
        let available: Bool; let doors: Int?; let conversations: Int?; let leads: Int?; let appointments: Int?
        let appointments_completed: Int?; let opportunities: Int?; let close_rate: String?
    }
    struct Sale: Decodable, Identifiable {
        let id: UUID; let rep_name: String; let status: String; let sold_on: String; let product: String
        let value_minor: String?; let campaign_name: String?
    }
    struct Group: Decodable { let id: String?; let name: String; let sales: Int; let sold_value_minor: String? }
    struct Option: Decodable, Identifiable { let id: UUID; let name: String }
    struct Options: Decodable { let representatives: [Option]; let campaigns: [Option]; let teams: [Option]; let territories: [Option]; let products: [String] }
    static func load(_ workspace: UUID, filter: [String: String]) async throws -> FieldSalesReport {
        struct Params: Encodable { let p_workspace: UUID; let p_filter: [String: String] }
        return try await SupabaseManager.shared.client.rpc("field_sales_report", params: Params(p_workspace: workspace, p_filter: filter)).execute().value
    }
}

struct FieldSalesReportView: View {
    var teamInitially = false
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        Group {
            if let user = auth.user?.id, let workspace = context.workspaceId {
                FieldSalesReportContent(workspace: workspace, teamInitially: teamInitially).id("\(user):\(workspace)")
            } else { ContentUnavailableView("Performance", systemImage: "chart.bar", description: Text("Sign in and select a workspace.")) }
        }
    }
}

private struct FieldSalesReportContent: View {
    let workspace: UUID
    @Environment(\.scenePhase) private var scene
    @State private var data: FieldSalesReport?
    @State private var error: String?
    @State private var generation = UUID()
    @State private var filter: [String: String]
    init(workspace: UUID, teamInitially: Bool) { self.workspace = workspace; _filter = State(initialValue: ["period":"month","scope":teamInitially ? "team" : "self","dimension":"campaign","limit":"50","offset":"0"]) }
    @State private var start = Date()
    @State private var end = Date()
    private let periods = [("today","Today"),("yesterday","Yesterday"),("week","This week"),("previous_week","Last week"),("month","This month"),("previous_month","Last month"),("quarter","This quarter"),("year","This year"),("all","All time"),("custom","Custom")]
    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } } } }
            if let d = data {
                if !d.enabled || d.needs_setup == true { Text("Set up Sales to view performance.") }
                else {
                    Section {
                        Picker("Period", selection: binding("period")) { ForEach(periods, id: \.0) { Text($0.1).tag($0.0) } }
                        if filter["period"] == "custom" {
                            DatePicker("From", selection: $start, displayedComponents: .date)
                            DatePicker("Through", selection: $end, displayedComponents: .date)
                            Button("Apply dates") { applyDates() }.disabled(start > end)
                        }
                        if d.capabilities?["team_details"] == true { Picker("View", selection: binding("scope")) { Text("My performance").tag("self"); Text("Workspace performance").tag("team") } }
                        DisclosureGroup("Filters") {
                            if filter["scope"] == "team" { optionPicker("Representative", key: "rep", options: d.options?.representatives ?? []) }
                            optionPicker("Campaign", key: "campaign", options: d.options?.campaigns ?? [])
                            optionPicker("Territory", key: "territory", options: d.options?.territories ?? [])
                            optionPicker("Team at sale", key: "team", options: d.options?.teams ?? [])
                            Picker("Product / service", selection: binding("product")) { Text("All").tag(""); ForEach(d.options?.products ?? [], id: \.self) { Text($0).tag($0) } }
                            Picker("Status", selection: binding("status")) { Text("All").tag(""); ForEach(["pending","verified","cancelled","rejected","refunded","charged_back"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                            Picker("Source", selection: binding("source")) { Text("All").tag(""); ForEach(["door_knock","qr","manual","referral","inbound","crm","other"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                        }
                        Text("\(d.period_start ?? "") – \(d.period_end ?? "") · \(d.timezone ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                    Section { NavigationLink("Team leaderboards") { FieldSalesLeaderboardView() }; NavigationLink("Goals & pace") { FieldSalesGoalsView() } }
                    if d.capabilities?["export"] == true { Section { ShareLink("Export displayed sales", item: exportPage(d)) } }
                    if let s = d.summary {
                        Section("Sales performance") {
                            moneyRow("Net sold", value: s.sold_value_minor, key: "sold_value_minor", report: d)
                            drillLink("Sales",s.sales,"sales")
                            moneyRow("Average ticket", value: s.average_ticket_minor, key: "average_ticket_minor", report: d)
                            LabeledContent("Close rate", value: d.metrics?.close_rate.map { "\($0)%" } ?? "Unavailable")
                            if let pipeline = d.current_pipeline, pipeline.available {
                                LabeledContent("Current open pipeline", value: FieldSalesService.money(pipeline.value_minor, currency: d.currency))
                            }
                            moneyRow("Completed value", value: s.completed_value_minor, key: "completed_value_minor", report: d)
                            moneyRow("Collected revenue", value: s.collected_revenue_minor, key: "collected_revenue_minor", report: d)
                            NavigationLink("Inspect completed jobs") { FieldSalesFunnelView(workspace: workspace, filter: filter, stage: "completed") }
                            NavigationLink("Inspect payments") { FieldSalesFunnelView(workspace: workspace, filter: filter, stage: "collected") }
                            Text("Compared with \(d.previous_start ?? "") – \(d.previous_end ?? ""). Sold uses sale date; completed uses completion date; collected uses payment time.").font(.caption).foregroundStyle(.secondary)
                        }
                        Section("Contract reconciliation") {
                            LabeledContent("Gross sold", value: FieldSalesService.money(s.gross_sold_minor, currency: d.currency))
                            LabeledContent("Cancellations", value: FieldSalesService.money(s.cancellations_minor, currency: d.currency))
                            LabeledContent("Pending sales", value: String(s.pending_sales))
                        }
                    }
                    if let pipeline = d.current_pipeline { pipelineSection(pipeline, currency: d.currency) }
                    if let m = d.metrics {
                        Section("Field activity") {
                            if m.available {
                                drillLink("Doors",m.doors,"doors"); drillLink("Conversations",m.conversations,"conversations"); drillLink("Leads",m.leads,"leads")
                                drillLink("Appointments",m.appointments,"appointments"); drillLink("Completed appointments",m.appointments_completed,"appointments_completed"); drillLink("Opportunities",m.opportunities,"opportunities")
                                LabeledContent("Close rate", value: m.close_rate.map { "\($0)%" } ?? "Unavailable")
                            }
                            if let note = d.metric_notes { Text(note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Section("Revenue breakdown") {
                        Picker("Group by", selection: binding("dimension")) { ForEach(["campaign","territory","team","product","source"], id: \.self) { Text($0.capitalized).tag($0) } }
                        ForEach(Array((d.groups ?? []).enumerated()), id: \.offset) { _, g in
                            VStack(alignment: .leading) { LabeledContent(g.name, value: FieldSalesService.money(g.sold_value_minor, currency: d.currency)); Text("\(g.sales) sales").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Section("Sales · \(d.total_records ?? 0)") {
                        ForEach(d.sales ?? []) { sale in
                            NavigationLink { FieldSalesRecordView(sale: sale.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(sale.rep_name + (sale.product.isEmpty ? "" : " · \(sale.product)"))
                                    Text(FieldSalesService.money(sale.value_minor, currency: d.currency)).fontWeight(.semibold)
                                    Text("\(sale.sold_on) · \(sale.status)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        HStack {
                            Button("Previous") { filter["offset"] = String(max(0, (Int(filter["offset"] ?? "0") ?? 0)-50)) }.disabled(filter["offset"] == "0")
                            Spacer()
                            Button("Next") { filter["offset"] = String((Int(filter["offset"] ?? "0") ?? 0)+50) }.disabled(d.has_more != true)
                        }
                    }
                }
            } else if error == nil { ProgressView("Loading performance…") }
        }
        .navigationTitle("Performance")
        .task(id: filter) { await reload() }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .onChange(of: scene) { _, value in if value == .active { Task { await reload() } } }
        .onDisappear { generation = UUID() }
    }
    @ViewBuilder private func pipelineSection(_ pipeline: FieldSalesReport.Pipeline, currency: String?) -> some View {
        Section("Current pipeline") {
            Text(pipeline.note).font(.caption).foregroundStyle(.secondary)
            if pipeline.available {
                Text("\(pipeline.count ?? 0) open · \(pipeline.stalled ?? 0) unchanged for 72 hours · \(pipeline.missing_values ?? 0) without a value").font(.caption)
                ForEach(pipeline.stages ?? []) { stage in
                    VStack(alignment: .leading) {
                        LabeledContent(stage.label, value: FieldSalesService.money(stage.value_minor, currency: currency))
                        Text("\(stage.count) opportunities · \(stage.stalled) unchanged for 72 hours").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let losses = pipeline.losses, !losses.isEmpty {
                    Text("Current loss reasons").font(.headline)
                    ForEach(losses, id: \.reason) { loss in
                        LabeledContent(loss.reason.replacingOccurrences(of: "_", with: " ").capitalized, value: "\(loss.count) (\(loss.percent)%)")
                    }
                }
            }
            NavigationLink("Open pipeline & follow-ups") { FieldSalesPipelineRootView() }
        }
    }
    private func exportPage(_ d: FieldSalesReport) -> String {
        let rows = [["Sale ID","Sold date","Status","Representative","Campaign","Product","Attributed value (minor units)","Currency"]] + (d.sales ?? []).map { [$0.id.uuidString,$0.sold_on,$0.status,$0.rep_name,$0.campaign_name ?? "",$0.product,$0.value_minor ?? "",d.currency ?? ""] }
        return rows.map { row in row.map { raw in
            let value = raw.range(of: #"^\s*[=+@-]"#, options: .regularExpression) != nil ? "'" + raw : raw
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") }.joined(separator: "\r\n")
    }
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { filter[key] ?? "" }, set: { value in
            filter[key] = value; filter["offset"] = "0"
            if key == "period", value == "custom" { applyDates() }
        })
    }
    private func applyDates() {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        filter["start"] = formatter.string(from: start); filter["end"] = formatter.string(from: end); filter["offset"] = "0"
    }
    private func optionPicker(_ title: String, key: String, options: [FieldSalesReport.Option]) -> some View {
        Picker(title, selection: binding(key)) { Text("All").tag(""); ForEach(options) { Text($0.name).tag($0.id.uuidString) } }
    }
    private func drillLink(_ title: String, _ value: Int?, _ stage: String) -> some View {
        NavigationLink { FieldSalesFunnelView(workspace: workspace, filter: filter, stage: stage) } label: { LabeledContent(title, value: value.map(String.init) ?? "Unavailable") }
    }
    private func metricRow(_ title: String, _ value: Int?) -> some View { LabeledContent(title, value: value.map(String.init) ?? "Unavailable") }
    private func moneyRow(_ title: String, value: String?, key: String, report: FieldSalesReport) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: FieldSalesService.money(value, currency: report.currency)).monospacedDigit()
            if let change = report.change_percent?[key] ?? nil { Text("\(change)% vs previous period").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        do {
            let next = try await FieldSalesReport.load(workspace, filter: filter)
            guard generation == ticket, !Task.isCancelled else { return }
            data = next; error = nil
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            data = nil; self.error = error.localizedDescription
        }
    }
}
