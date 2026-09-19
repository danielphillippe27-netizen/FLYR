import SwiftUI
import Supabase

private let fieldSalesRankingLabels = ["sales":"Sales","sold_value":"Sold value","collected_revenue":"Collected revenue","appointments":"Appointments","leads":"Leads","doors":"Doors","conversations":"Conversations","close_rate":"Close rate","setters":"Setters","closers":"Closers","average_ticket":"Average credited value","lead_conversion":"Lead conversion","sales_per_100_doors":"Sales per 100 doors","revenue_per_100_doors":"Revenue per 100 doors","sales_cycle":"Fastest sales cycle"]
private struct FieldSalesRankingSnapshot: Decodable {
    let enabled: Bool; let needs_setup: Bool?; let currency: String?; let metric: String?; let unit: String?
    let categories: [String]?; let definition: String?; let message: String?; let period_start: String?; let period_end: String?
    let minimum_opportunities: Int?; let below_threshold_or_unavailable: Int?; let has_more: Bool?
    let rows: [Row]?; let options: Options?; let settings: Settings?
    struct Row: Decodable, Identifiable { let rep_id: UUID; let rep_name: String; let rank: Int; let value: String; let metrics: [String: String]; var id: UUID { rep_id } }
    struct Option: Decodable, Identifiable { let id: UUID; let name: String }
    struct Options: Decodable { let products: [String]; let campaigns: [Option]; let teams: [Option]; let territories: [Option] }
    struct Settings: Decodable { let leaderboard_categories: [String]; let minimum_close_opportunities: Int; let featured_ranking: String }
}

struct FieldSalesLeaderboardView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        Group {
            if let user = auth.user?.id, let workspace = context.workspaceId { FieldSalesLeaderboardContent(workspace: workspace).id("\(user):\(workspace)") }
            else { ContentUnavailableView("Leaderboards", systemImage: "chart.bar", description: Text("Sign in and select a workspace.")) }
        }
    }
}
private struct FieldSalesLeaderboardContent: View {
    let workspace: UUID
    @State private var filter: [String: String] = ["period":"month","offset":"0","limit":"100"]
    @State private var metric = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var data: FieldSalesRankingSnapshot?
    @State private var error: String?
    @State private var generation = UUID()
    @Environment(\.scenePhase) private var scene
    private var request: [String: String] { filter.merging(["metric":metric]) { _, new in new } }
    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red); Button("Reset filters") { metric = ""; filter = ["period":"month","offset":"0","limit":"100"] } } }
            if let d = data {
                if let message = d.message { Text(message) }
                else if !d.enabled || d.needs_setup == true { Text("Set up Sales to view leaderboards.") }
                else {
                    Section {
                        Picker("Category", selection: Binding(get: { d.metric ?? "sales" }, set: { metric = $0; filter["offset"] = "0" })) {
                            ForEach(d.categories ?? [], id: \.self) { Text(fieldSalesRankingLabels[$0] ?? $0).tag($0) }
                        }
                        Picker("Period", selection: binding("period")) {
                            ForEach([("today","Today"),("yesterday","Yesterday"),("week","This week"),("previous_week","Last week"),("month","This month"),("previous_month","Last month"),("quarter","This quarter"),("year","This year"),("all","All time"),("custom","Custom")], id: \.0) { Text($0.1).tag($0.0) }
                        }
                        if filter["period"] == "custom" { DatePicker("From", selection: $start, displayedComponents: .date); DatePicker("Through", selection: $end, displayedComponents: .date); Button("Apply dates") { applyDates() }.disabled(start > end) }
                        DisclosureGroup("Filters") {
                            optionPicker("Campaign", "campaign", d.options?.campaigns ?? [])
                            optionPicker("Territory", "territory", d.options?.territories ?? [])
                            optionPicker("Team at sale", "team", d.options?.teams ?? [])
                            Picker("Product / service", selection: binding("product")) { Text("All").tag(""); ForEach(d.options?.products ?? [], id: \.self) { Text($0).tag($0) } }
                            Picker("Source", selection: binding("source")) { Text("All").tag(""); ForEach(["door_knock","qr","manual","referral","inbound","crm","other"], id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                        }
                        Text("\(d.period_start ?? "") – \(d.period_end ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                    if let n = d.below_threshold_or_unavailable, n > 0 { Text("\(n) representatives have insufficient evidence for this category. Conversion and cycle rankings require at least \(d.minimum_opportunities ?? 10) opportunities.").font(.caption).foregroundStyle(.secondary) }
                    Section(fieldSalesRankingLabels[d.metric ?? ""] ?? "Ranking") {
                        ForEach(d.rows ?? []) { row in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(row.rank)").font(.headline).frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.rep_name).fontWeight(.medium)
                                    Text("\(row.metrics["sales"] ?? "—") sales").font(.caption).foregroundStyle(.secondary)
                                    if let trend = row.metrics["sales_change_percent"] { Text("Sales trend: \(trend)%").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Text(d.unit == "money" ? FieldSalesService.money(row.value, currency: d.currency) : row.value + (d.unit == "percent" ? "%" : d.unit == "days" ? " days" : "")).fontWeight(.semibold).monospacedDigit()
                            }.padding(.vertical, 4)
                        }
                        if d.rows?.isEmpty == true { Text("No representatives have enough evidence for this ranking yet.").foregroundStyle(.secondary) }
                    }
                    Section {
                        HStack { Button("Previous") { filter["offset"] = String(max(0, (Int(filter["offset"] ?? "0") ?? 0)-100)) }.disabled(filter["offset"] == "0"); Spacer(); Button("Next") { filter["offset"] = String((Int(filter["offset"] ?? "0") ?? 0)+100) }.disabled(d.has_more != true) }
                        if let definition = d.definition { Text(definition).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let settings = d.settings {
                    Section { NavigationLink("Manage leaderboards") { FieldSalesRankingSettings(workspace: workspace, settings: settings) } }
                }
            } else if error == nil { ProgressView("Loading leaderboards…") }
        }
        .navigationTitle("Leaderboards")
        .task(id: request) { await reload() }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in metric = ""; Task { await reload() } }
        .onChange(of: scene) { _, value in if value == .active { Task { await reload() } } }
        .onDisappear { generation = UUID() }
    }
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { filter[key] ?? "" }, set: { filter[key] = $0; filter["offset"] = "0"; if key == "product" || key == "source" { metric = "" }; if key == "period", $0 == "custom" { applyDates() } })
    }
    private func applyDates() {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        filter["start"] = formatter.string(from: start); filter["end"] = formatter.string(from: end); filter["offset"] = "0"
    }
    private func optionPicker(_ title: String, _ key: String, _ options: [FieldSalesRankingSnapshot.Option]) -> some View {
        Picker(title, selection: binding(key)) { Text("All").tag(""); ForEach(options) { Text($0.name).tag($0.id.uuidString) } }
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        struct Params: Encodable { let p_workspace: UUID; let p_filter: [String:String]; let p_metric: String? }
        do {
            let next: FieldSalesRankingSnapshot = try await SupabaseManager.shared.client.rpc("field_sales_leaderboard", params: Params(p_workspace: workspace, p_filter: filter, p_metric: metric.isEmpty ? nil : metric)).execute().value
            guard ticket == generation, !Task.isCancelled else { return }; data = next; error = nil
        } catch { guard ticket == generation, !Task.isCancelled else { return }; data = nil; self.error = error.localizedDescription }
    }
}
private struct FieldSalesRankingSettings: View {
    let workspace: UUID; let settings: FieldSalesRankingSnapshot.Settings
    @State private var selected = Set<String>()
    @State private var minimum = 10
    @State private var featured = "sales"
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section("Visible categories") { ForEach(fieldSalesRankingLabels.keys.sorted(), id: \.self) { key in Toggle(fieldSalesRankingLabels[key] ?? key, isOn: Binding(get: { selected.contains(key) }, set: { if $0 { selected.insert(key) } else { selected.remove(key) } })) } }
            Section {
                Stepper("Minimum opportunities: \(minimum)", value: $minimum, in: 1...1000)
                Picker("Featured ranking", selection: $featured) { ForEach(["sales","sold_value","collected_revenue"], id: \.self) { Text(fieldSalesRankingLabels[$0] ?? $0).tag($0) } }
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? "Saving…" : "Save settings") { Task { await save() } }.disabled(busy)
            }
        }.navigationTitle("Leaderboard settings")
        .onAppear { selected = Set(settings.leaderboard_categories); minimum = settings.minimum_close_opportunities; featured = settings.featured_ranking }
    }
    private func save() async {
        busy = true; error = nil
        struct Params: Encodable { let p_workspace: UUID; let p_categories: [String]; let p_minimum: Int; let p_featured: String }
        do {
            _ = try await SupabaseManager.shared.client.rpc("field_sales_ranking_settings", params: Params(p_workspace: workspace, p_categories: selected.sorted(), p_minimum: minimum, p_featured: featured)).execute()
            NotificationCenter.default.post(name: .fieldSalesChanged, object: nil); dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
