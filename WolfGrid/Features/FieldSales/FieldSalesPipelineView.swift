import SwiftUI
import Supabase

private struct SalesWorkbenchData: Decodable {
    let enabled: Bool
    var needs_setup: Bool?
    var role: String?
    var currency: String?
    var stages: [Stage]?
    var opportunities: [Opportunity]?
    var tasks: [FollowUp]?
    var summary: [Summary]?
    var leads: [Lead]?
    var task_leads: [Lead]?
    var scope: String?
    var money_visible: Bool?
    var losses: [Loss]?
    var open_pipeline: OpenPipeline?
    struct Loss: Decodable { let reason: String; let count: Int; let percent: String }
    struct OpenPipeline: Decodable { let count: Int; let value_minor: String?; let missing_values: Int; let stalled: Int }
    struct Stage: Decodable, Identifiable { let key: String; let label: String; let position: Int; let probability: Int; let kind: String; var id: String { key } }
    struct Opportunity: Decodable, Identifiable {
        let contact_id: UUID; let contact_name: String; let stage_key: String; let expected_value_minor: String?; let expected_close: String?; let notes: String; let version: Int; let loss_reason: String?; let loss_note: String?; let stalled: Bool?
        var id: UUID { contact_id }
    }
    struct FollowUp: Decodable, Identifiable { let id: UUID; let contact_id: UUID; let contact_name: String; let title: String; let kind: String; let due_at: String; let status: String; let version: Int }
    struct Summary: Decodable, Identifiable { let key: String; let label: String; let count: Int; let value_minor: String?; let weighted_minor: String?; let missing_values: Int; var id: String { key } }
    struct Lead: Decodable, Identifiable { let id: UUID; let name: String }
}

struct FieldSalesPipelineRootView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        if let user = auth.user?.id, let space = context.workspaceId {
            FieldSalesPipelineScreen(workspace: space).id("\(user):\(space)")
        } else { Text("Sign in and select a workspace.") }
    }
}

private struct FieldSalesPipelineScreen: View {
    let workspace: UUID
    @Environment(\.scenePhase) private var scene
    @State private var data: SalesWorkbenchData?
    @State private var error: String?
    @State private var generation = 0
    @State private var adding = false
    @State private var tasking = false
    @State private var editing: SalesWorkbenchData.Opportunity?
    @State private var busy = false
    @State private var completed = false
    @State private var pipelineFilter = "all"
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if let d = data, d.enabled, d.needs_setup != true {
                Section { Text("Expected pipeline value is an estimate. Only separately verified sales earn revenue and leaderboard credit.").font(.caption) }
                Section(d.scope == "self" ? "My pipeline" : "Workspace pipeline") {
                    ForEach((d.summary ?? []).filter { $0.count>0 }) { row in
                        VStack(alignment: .leading) {
                            Text("\(row.label): \(row.count) opportunities").font(.headline)
                            if let value = row.value_minor { Text("\(FieldSalesService.money(value, currency: d.currency)) known value"); Text("\(FieldSalesService.money(row.weighted_minor, currency: d.currency)) weighted estimate").font(.caption) }
                            if row.missing_values > 0 { Text("\(row.missing_values) values unavailable").font(.caption) }
                        }
                    }
                }
                if let pipeline = d.open_pipeline { Section("Open pipeline") { Text("\(pipeline.count) opportunities"); if let value = pipeline.value_minor { Text("\(FieldSalesService.money(value,currency:d.currency)) potential value") }; Text("\(pipeline.stalled) unchanged for 72 hours · \(pipeline.missing_values) missing values").font(.caption) } }
                if let losses = d.losses, !losses.isEmpty { Section("Current lost opportunities") { ForEach(losses, id: \.reason) { l in Button("\(l.reason.replacingOccurrences(of: "_", with: " ")) · \(l.count) (\(l.percent)%)") { pipelineFilter = "loss:" + l.reason } } } }
                Section { Picker("Inspect opportunities",selection:$pipelineFilter) { Text("All").tag("all"); Text("Unchanged for 72 hours").tag("stalled"); ForEach(d.losses ?? [],id:\.reason) { Text("Lost: " + $0.reason.replacingOccurrences(of:"_",with:" ")).tag("loss:" + $0.reason) } } }
                Section {
                    Button("Add opportunity · Beta") { editing = nil; adding = true }
                    Button("Add follow-up · Beta") { tasking = true }
                }
                opportunitySections(d)
                Section("My follow-ups · Beta") {
                    Toggle("Completed in last 30 days", isOn: $completed)
                    ForEach((d.tasks ?? []).filter { $0.status == (completed ? "done" : "pending") }) { t in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(t.title).font(.headline); Text("\(t.contact_name) · \(t.kind)")
                            Text(t.due_at).font(.caption)
                            HStack {
                                Button(completed ? "Reopen" : "Complete") { Task { await updateTask(t, status: completed ? "pending" : "done") } }
                                if !completed { Button("Cancel", role: .destructive) { Task { await updateTask(t, status: "cancelled") } } }
                            }.buttonStyle(.bordered).disabled(busy)
                        }
                    }
                }
                if d.role == "owner" || d.role == "admin" {
                    Section("Stages · Beta") {
                        ForEach(d.stages ?? []) { stage in NavigationLink("Edit \(stage.label)") { SalesStageEditor(workspace: workspace, initial: stage) } }
                        NavigationLink("Add stage · Beta") { SalesStageEditor(workspace: workspace, initial: nil) }
                    }
                }
            } else if data == nil && error == nil { ProgressView() }
            else if data?.needs_setup == true { Text("Set up currency and timezone in Sales first.") }
        }
        .navigationTitle("Pipeline · Beta")
        .task { await reload() }.refreshable { await reload() }
        .onChange(of: scene) { _, phase in if phase == .active { Task { await reload() } } }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .sheet(isPresented: $adding) { if let d = data { NavigationStack { SalesOpportunityEditor(workspace: workspace, data: d, initial: editing) } } }
        .sheet(isPresented: $tasking) { if let d = data { NavigationStack { SalesTaskEditor(workspace: workspace, data: d) } } }
    }
    private func visibleOpportunities(_ d: SalesWorkbenchData, stage: SalesWorkbenchData.Stage) -> [SalesWorkbenchData.Opportunity] {
        (d.opportunities ?? []).filter { opportunity in
            guard opportunity.stage_key == stage.key else { return false }
            if pipelineFilter == "all" { return true }
            if pipelineFilter == "stalled" { return opportunity.stalled == true }
            let lossFilter = "loss:" + (opportunity.loss_reason ?? "unspecified")
            return stage.kind == "lost" && pipelineFilter == lossFilter
        }
    }

    @ViewBuilder private func opportunitySections(_ d: SalesWorkbenchData) -> some View {
        ForEach(d.stages ?? []) { stage in
            let opportunities = visibleOpportunities(d, stage: stage)
            if !opportunities.isEmpty {
                Section("\(stage.label) · Beta") {
                    ForEach(opportunities) { opportunity in
                        opportunityRow(opportunity, stage: stage, currency: d.currency)
                    }
                }
            }
        }
    }

    private func opportunityRow(_ opportunity: SalesWorkbenchData.Opportunity, stage: SalesWorkbenchData.Stage, currency: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(opportunity.contact_name).font(.headline)
            if opportunity.stalled == true { Text("Unchanged for 72 hours").font(.caption) }
            if let reason = opportunity.loss_reason {
                Text("Lost: " + reason.replacingOccurrences(of: "_", with: " ")).font(.caption)
            }
            Text(opportunity.expected_value_minor == nil ? "Value unavailable" : FieldSalesService.money(opportunity.expected_value_minor, currency: currency))
            if let close = opportunity.expected_close { Text("Expected close: \(close)").font(.caption) }
            Button("Edit") { editing = opportunity; adding = true }
            if stage.kind != "lost" { Text("Create or complete an appointment before recording a sale.").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func reload() async {
        generation += 1; let ticket = generation
        struct Params: Encodable { let p_workspace: UUID }
        do {
            let result: SalesWorkbenchData = try await SupabaseManager.shared.client.rpc("field_sales_workbench", params: Params(p_workspace: workspace)).execute().value
            guard ticket == generation, !Task.isCancelled else { return }; data = result; error = nil
        } catch { guard ticket == generation, !Task.isCancelled else { return }; data = nil; self.error = error.localizedDescription }
    }
    private func updateTask(_ task: SalesWorkbenchData.FollowUp, status: String) async {
        busy = true; defer { busy = false }
        do { try await pipelineCommand(workspace, "task_status", ["id": task.id.uuidString, "version": String(task.version), "status": status]) }
        catch { self.error = error.localizedDescription }
    }
}

private func pipelineCommand(_ workspace: UUID, _ action: String, _ data: [String: String]) async throws {
    struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: [String: String] }
    _ = try await SupabaseManager.shared.client.rpc("field_sales_pipeline_command", params: Params(p_workspace: workspace, p_action: action, p_data: data)).execute()
    await MainActor.run { NotificationCenter.default.post(name: .fieldSalesChanged, object: nil) }
}

private struct SalesOpportunityEditor: View {
    let workspace: UUID; let data: SalesWorkbenchData; let initial: SalesWorkbenchData.Opportunity?
    @Environment(\.dismiss) private var dismiss
    @State private var contact = ""
    @State private var stage = "new"
    @State private var amount = ""
    @State private var close = ""
    @State private var notes = ""
    @State private var lossReason = ""
    @State private var lossNote = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            Picker("Lead", selection: $contact) { ForEach(data.leads ?? []) { Text($0.name).tag($0.id.uuidString) } }.disabled(initial != nil)
            Picker("Stage", selection: $stage) { ForEach((data.stages ?? []).filter { $0.kind != "won" || $0.key == initial?.stage_key }) { Text($0.label).tag($0.key) } }
            if data.money_visible != false { TextField("Expected value (\(data.currency ?? ""), optional)", text: $amount).keyboardType(.decimalPad) }
            if data.stages?.first(where: { $0.key == stage })?.kind == "lost" { Picker("Loss reason",selection:$lossReason) { Text("Select reason").tag(""); ForEach(["price","competitor","no_decision","unable_to_contact","financing","timing","not_qualified","cancelled","other"],id:\.self) { Text($0.replacingOccurrences(of:"_",with:" ")).tag($0) } }; TextField("Loss note (optional)",text:$lossNote,axis:.vertical) }
            TextField("Expected close YYYY-MM-DD (optional)", text: $close)
            TextField("Notes", text: $notes, axis: .vertical)
            if let error { Text(error).foregroundStyle(.red) }
            Button("Save opportunity") { Task { await save() } }.disabled(busy || contact.isEmpty)
        }.navigationTitle("Opportunity · Beta").toolbar { Button("Close") { dismiss() } }
        .onAppear { contact = initial?.contact_id.uuidString ?? data.leads?.first?.id.uuidString ?? ""; stage = initial?.stage_key ?? data.stages?.first?.key ?? "new"; amount = FieldSalesService.editableMoney(initial?.expected_value_minor, currency: data.currency); close = initial?.expected_close ?? ""; notes = initial?.notes ?? ""; lossReason = initial?.loss_reason ?? ""; lossNote = initial?.loss_note ?? "" }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let value = amount.isEmpty ? "" : (Decimal(string: amount) == 0 ? "0" : try FieldSalesService.minorUnits(amount, currency: data.currency ?? "CAD"))
            var p = ["contact_id": contact, "stage_key": stage, "expected_value_minor": value, "expected_close": close, "notes": notes,"loss_reason":lossReason,"loss_note":lossNote]
            if let initial { p["version"] = String(initial.version) }
            try await pipelineCommand(workspace, "opportunity", p); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct SalesTaskEditor: View {
    let workspace: UUID; let data: SalesWorkbenchData
    @Environment(\.dismiss) private var dismiss
    @State private var id = UUID()
    @State private var contact = ""
    @State private var title = ""
    @State private var kind = "call"
    @State private var due = Date()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Picker("Lead", selection: $contact) { ForEach(data.task_leads ?? data.leads ?? []) { Text($0.name).tag($0.id.uuidString) } }
            TextField("Task", text: $title)
            Picker("Type", selection: $kind) { ForEach(["call","email","text","visit","task"], id: \.self) { Text($0.capitalized).tag($0) } }
            DatePicker("Due", selection: $due)
            if let error { Text(error).foregroundStyle(.red) }
            Button("Save follow-up") { Task {
                busy = true; defer { busy = false }
                do { try await pipelineCommand(workspace, "task", ["id": id.uuidString, "contact_id": contact, "title": title, "kind": kind, "due_at": ISO8601DateFormatter().string(from: due)]); dismiss() }
                catch { self.error = error.localizedDescription }
            } }.disabled(busy || contact.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.navigationTitle("Follow-up · Beta").toolbar { Button("Close") { dismiss() } }
        .onAppear { contact = (data.task_leads ?? data.leads)?.first?.id.uuidString ?? "" }
    }
}

private struct SalesStageEditor: View {
    let workspace: UUID; let initial: SalesWorkbenchData.Stage?
    @Environment(\.dismiss) private var dismiss
    @State private var key = "stage_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).lowercased()
    @State private var label = ""
    @State private var position = 6
    @State private var probability = 0
    @State private var kind = "open"
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            TextField("Stage name", text: $label)
            Stepper("Order: \(position)", value: $position, in: 0...100)
            Stepper("Probability: \(probability)%", value: $probability, in: 0...100)
            Picker("Outcome", selection: $kind) { ForEach(["open","won","lost"], id: \.self) { Text($0.capitalized).tag($0) } }
            Text("Probabilities weight estimates; they do not predict outcomes.").font(.caption)
            if let error { Text(error).foregroundStyle(.red) }
            Button("Save stage") { Task {
                busy = true; defer { busy = false }
                do { try await pipelineCommand(workspace, "stage", ["key": initial?.key ?? key, "label": label, "position": String(position), "probability": String(probability), "kind": kind]); dismiss() }
                catch { self.error = error.localizedDescription }
            } }.disabled(busy || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.navigationTitle("Stage · Beta")
        .onAppear { if let initial { label = initial.label; position = initial.position; probability = initial.probability; kind = initial.kind } }
    }
}
