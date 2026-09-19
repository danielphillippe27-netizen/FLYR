import SwiftUI
import Supabase

private let goalLabels = ["doors":"Doors","conversations":"Conversations","leads":"Leads","appointments":"Appointments","sales":"Sales","sold_value":"Sold value","collected_revenue":"Collected revenue","commission":"Commission","close_rate":"Close rate","appointments_converted":"Appointments converted"]
private struct SalesGoalSnapshot: Decodable {
    let enabled: Bool; let needs_setup: Bool?; let currency: String?; let timezone: String?; let user_id: UUID?
    let goals: [Goal]?; let has_more: Bool?; let definitions: String?; let goal_permissions: [String:Bool]?; let goal_options: Options?; let goal_periods: [Period]?
    struct Goal: Decodable, Identifiable {
        let id: UUID; let version: Int; let title: String; let scope: String; let scope_id: UUID?; let metric: String; let unit: String
        let target: String; let actual: String?; let remaining: String?; let progress_percent: String?; let starts_on: String; let ends_on: String; let pace: String
        let required_daily: String?; let required_weekly: String?; let projected: String?; let projection_note: String?; let archived: Bool
    }
    struct Option: Decodable, Identifiable { let id: UUID; let name: String }
    struct Options: Decodable { let representatives: [Option]; let teams: [Option]; let campaigns: [Option] }
    struct Period: Decodable { let key: String; let start: String; let end: String }
}
private func saveSalesGoal(_ workspace: UUID, _ action: String, _ data: [String:String]) async throws {
    struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: [String:String] }
    _ = try await SupabaseManager.shared.client.rpc("field_sales_target_command", params: Params(p_workspace: workspace, p_action: action, p_data: data)).execute()
    NotificationCenter.default.post(name: .fieldSalesChanged, object: nil)
}
struct FieldSalesGoalsView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        Group {
            if let user = auth.user?.id, let workspace = context.workspaceId { SalesGoalsContent(workspace: workspace).id("\(user):\(workspace)") }
            else { ContentUnavailableView("Goals", systemImage: "target", description: Text("Sign in and select a workspace.")) }
        }
    }
}
private struct SalesGoalsContent: View {
    let workspace: UUID
    @State private var data: SalesGoalSnapshot?
    @State private var offset = 0
    @State private var archived = false
    @State private var error: String?
    @State private var busy = false
    @State private var generation = UUID()
    @Environment(\.scenePhase) private var scene
    private var filter: [String:String] { ["offset":String(offset),"limit":"50","archived":String(archived)] }
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } } }
            if let d = data {
                if !d.enabled || d.needs_setup == true { Text("Set up Sales to create goals.") }
                else {
                    Section {
                        NavigationLink("Create goal") { SalesGoalEditor(workspace: workspace, data: d, goal: nil) }
                        Toggle("Show archived goals", isOn: $archived).onChange(of: archived) { _, _ in offset = 0 }
                        Text("Calendar periods use \(d.timezone ?? "workspace time").").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(d.goals ?? []) { g in
                        Section {
                            Text(g.title).font(.headline)
                            Text("\(g.scope.capitalized) · \(goalLabels[g.metric] ?? g.metric) · \(g.starts_on) – \(g.ends_on)").font(.caption).foregroundStyle(.secondary)
                            Text("\(value(g, g.actual)) / \(value(g, g.target))").font(.title3).fontWeight(.semibold).monospacedDigit()
                            if let progress = g.progress_percent {
                                ProgressView(value: max(0, min(100, Double(progress) ?? 0)), total: 100).accessibilityLabel("\(g.title) progress")
                                Text("\(progress)% · \(value(g, g.remaining)) remaining").font(.subheadline)
                            }
                            Text(g.pace.replacingOccurrences(of: "_", with: " ").capitalized).font(.subheadline)
                            if let daily = g.required_daily { Text("Required: \(value(g, daily))/day").font(.subheadline) }
                            if let projected = g.projected { Text("Projected at current pace: \(value(g, projected))").font(.subheadline) }
                            if let note = g.projection_note { Text(note).font(.caption).foregroundStyle(.secondary) }
                            NavigationLink("Edit goal") { SalesGoalEditor(workspace: workspace, data: d, goal: g) }
                            Button(g.archived ? "Restore" : "Archive") { Task { await archive(g) } }.disabled(busy)
                        }
                    }
                    if d.goals?.isEmpty == true { Text("No visible goals yet.").foregroundStyle(.secondary) }
                    Section {
                        HStack { Button("Previous") { offset = max(0, offset-50) }.disabled(offset == 0); Spacer(); Button("Next") { offset += 50 }.disabled(d.has_more != true) }
                        if let definition = d.definitions { Text(definition).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } else if error == nil { ProgressView("Loading goals…") }
        }.navigationTitle("Goals & pace")
        .task(id: filter) { await reload() }.refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .onChange(of: scene) { _, phase in if phase == .active { Task { await reload() } } }
        .onDisappear { generation = UUID() }
    }
    private func value(_ goal: SalesGoalSnapshot.Goal, _ amount: String?) -> String {
        guard let amount else { return "—" }
        return goal.unit == "money" ? FieldSalesService.money(amount, currency: data?.currency) : amount + (goal.unit == "percent" ? "%" : "")
    }
    private func archive(_ goal: SalesGoalSnapshot.Goal) async {
        busy = true; defer { busy = false }
        do { try await saveSalesGoal(workspace, goal.archived ? "restore" : "archive", ["id":goal.id.uuidString,"version":String(goal.version)]); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        struct Params: Encodable { let p_workspace: UUID; let p_filter: [String:String] }
        do {
            let result: SalesGoalSnapshot = try await SupabaseManager.shared.client.rpc("field_sales_target_list", params: Params(p_workspace: workspace, p_filter: filter)).execute().value
            guard generation == ticket, !Task.isCancelled else { return }; data = result; error = nil
        } catch { guard generation == ticket, !Task.isCancelled else { return }; data = nil; self.error = error.localizedDescription }
    }
}
private struct SalesGoalEditor: View {
    let workspace: UUID; let data: SalesGoalSnapshot; let goal: SalesGoalSnapshot.Goal?
    @State private var scope = "rep"
    @State private var scopeID = ""
    @State private var metric = "sales"
    @State private var title = ""
    @State private var amount = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var request = UUID()
    @State private var initialized = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var monetary: Bool { ["sold_value","collected_revenue","commission"].contains(metric) }
    private var options: [SalesGoalSnapshot.Option] { scope == "team" ? data.goal_options?.teams ?? [] : scope == "campaign" ? data.goal_options?.campaigns ?? [] : data.goal_options?.representatives ?? [] }
    private var metrics: [String] {
        let own = scope == "rep" && scopeID.lowercased() == data.user_id?.uuidString.lowercased()
        return goalLabels.keys.sorted().filter { m in m == "commission" ? data.goal_permissions?["commission"] == true : !["sold_value","collected_revenue"].contains(m) || data.goal_permissions?[own ? "own_revenue" : "team_revenue"] == true }
    }
    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                if goal == nil {
                    Picker("Scope", selection: $scope) { Text("Individual rep").tag("rep"); if data.goal_permissions?["manage_team"] == true { Text("Team").tag("team"); Text("Workspace").tag("workspace"); Text("Campaign").tag("campaign") } }
                        .onChange(of: scope) { _, _ in scopeID = scope == "rep" ? data.user_id?.uuidString ?? "" : options.first?.id.uuidString ?? ""; metric = "sales" }
                    if scope != "workspace" { Picker(scope.capitalized, selection: $scopeID) { Text("Select").tag(""); ForEach(options) { Text($0.name).tag($0.id.uuidString) } }.onChange(of: scopeID) { _, _ in metric = "sales" } }
                    Picker("Metric", selection: $metric) { ForEach(metrics, id: \.self) { Text(goalLabels[$0] ?? $0).tag($0) } }.onChange(of: metric) { _, _ in if initialized { amount = "" } }
                }
                TextField(monetary ? "Target (\(data.currency ?? ""))" : metric == "close_rate" ? "Target (%)" : "Target", text: $amount).keyboardType(.decimalPad)
            }
            Section("Period") {
                ForEach(data.goal_periods ?? [], id: \.key) { period in Button("This \(period.key)") { apply(period.start, period.end) } }
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                Text("Dates are interpreted in \(data.timezone ?? "workspace time").").font(.caption).foregroundStyle(.secondary)
            }
            Section { if let error { Text(error).foregroundStyle(.red) }; Button(busy ? "Saving…" : "Save goal") { Task { await save() } }.disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty || amount.isEmpty || start > end || (scope != "workspace" && scopeID.isEmpty)) }
        }.navigationTitle(goal == nil ? "Create goal" : "Edit goal")
        .task { guard !initialized else { return }; scope = goal?.scope ?? "rep"; scopeID = goal?.scope_id?.uuidString ?? data.user_id?.uuidString ?? ""; metric = goal?.metric ?? "sales"; title = goal?.title ?? ""
            if let g = goal { amount = g.unit == "money" ? decimalAmount(g.target) : g.target; apply(g.starts_on,g.ends_on) }
            else if let p = data.goal_periods?.first(where: { $0.key == "month" }) { apply(p.start,p.end) }
            initialized = true
        }
    }
    private var formatter: DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }
    private func apply(_ a: String, _ b: String) { start = formatter.date(from:a) ?? Date(); end = formatter.date(from:b) ?? Date() }
    private func decimalAmount(_ value: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = data.currency ?? "CAD"
        var scale = Decimal(1); for _ in 0..<f.maximumFractionDigits { scale *= 10 }
        return NSDecimalNumber(decimal: (Decimal(string:value) ?? 0)/scale).stringValue
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do {
            var payload = ["title":title,"target":monetary ? try FieldSalesService.minorUnits(amount,currency:data.currency ?? "CAD") : amount,"starts_on":formatter.string(from:start),"ends_on":formatter.string(from:end)]
            if let g = goal { payload["id"] = g.id.uuidString; payload["version"] = String(g.version) }
            else { payload["request_id"] = request.uuidString; payload["scope"] = scope; payload["scope_id"] = scope == "workspace" ? "" : scopeID; payload["metric"] = metric }
            try await saveSalesGoal(workspace,goal == nil ? "create" : "update",payload); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
