import SwiftUI

struct FieldSalesRootView: View {
    var leadID: UUID? = nil
    var leaderboardOnly = false
    var appointmentID: UUID? = nil
    var opportunityID: UUID? = nil
    var propertyKey: String? = nil
    var campaignID: UUID? = nil
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    private var appointmentContext: [String:String] {
        guard let appointmentID else { return [:] }
        var context = ["appointment_id": appointmentID.uuidString]
        if let leadID { context["contact_id"] = leadID.uuidString }
        return context
    }
    var body: some View {
        Group {
            if let user = auth.user?.id, let space = workspace.workspaceId {
                FieldSalesGate(workspace: space, user: user, leadID: leadID, leaderboardOnly: leaderboardOnly, initial: appointmentContext)
                    .id("\(user):\(space)")
            } else { ContentUnavailableView("Sales · Beta", systemImage: "chart.line.uptrend.xyaxis", description: Text("Sign in and select a workspace.")) }
        }
        .navigationTitle("Sales")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct FieldSalesGate: View {
    let workspace: UUID; let user: UUID; let leadID: UUID?; let leaderboardOnly: Bool; let initial: [String:String]
    @State private var data: FieldSalesSnapshot?
    @State private var error: String?
    var body: some View {
        Group {
            if let d = data {
                if !d.enabled {
                    ContentUnavailableView {
                        Label("Sales isn’t enabled", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Sales hasn’t been activated for this workspace yet. Once enabled, you can set its currency and timezone, then record and review sales here.")
                    } actions: {
                        Button("Check again") { Task { await reload() } }
                    }
                } else if d.pro_sales_version != nil && d.currency != nil && d.timezone != nil && d.needs_setup != true {
                    if leaderboardOnly { FieldSalesLeaderboardView() }
                    else { FieldSalesProDashboard(workspace: workspace, data: d, initial: initial) }
                } else { FieldSalesScreen(workspace:workspace,user:user,leadID:leadID,leaderboardOnly:leaderboardOnly) }
            } else if let error {
                ContentUnavailableView {
                    Label("Sales couldn’t load", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await reload() } }
                }
            } else { ProgressView("Loading Sales…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
    }
    private func reload() async { do { let next = try await FieldSalesService.bootstrap(workspace); guard !Task.isCancelled else { return }; data = next; error = nil } catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
}

private struct FieldSalesScreen: View {
    let workspace: UUID
    let user: UUID
    let leadID: UUID?
    let leaderboardOnly: Bool
    @StateObject private var model = FieldSalesModel()
    @Environment(\.scenePhase) private var scene
    @State private var period = "month"
    @State private var team = false
    @State private var rep: UUID?
    @State private var campaign: UUID?
    @State private var status = ""
    @State private var recording = false
    @State private var editing: FieldSalesSnapshot.Sale?
    @State private var replacement = false
    @State private var cancelling: FieldSalesSnapshot.Sale?
    @State private var reason = ""
    @State private var actionError: String?
    @State private var busy = false
    @State private var revenueRank = false
    private var filter: FieldSalesService.Filter {
        .init(p_workspace: workspace, p_period: period, p_team: team, p_rep: team ? rep : nil, p_campaign: campaign, p_status: status.isEmpty ? nil : status)
    }
    var body: some View {
        Group {
            if leaderboardOnly && model.data?.pro_sales_version != nil { FieldSalesLeaderboardView() }
            else { salesList }
        }
        .navigationTitle(leaderboardOnly ? "Sales leaderboard · Beta" : "Sales · Beta")
        .task(id: filter) { await reload() }
        .onAppear { if leadID != nil { recording = true } }
        .onDisappear { model.cancelPending() }
        .refreshable { await reload() }
        .onChange(of: scene) { _, phase in if phase == .active { Task { await reload() } } }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .sheet(isPresented: $recording) {
            if let d = model.data {
                NavigationStack { FieldSaleEditor(data: d, workspace: workspace, initial: editing, replacement: replacement, leadID: leadID) }
            }
        }
        .alert("Cancel sale", isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } })) {
            TextField("Reason", text: $reason)
            Button("Cancel sale", role: .destructive) { if let sale = cancelling { Task { await review("cancel", sale, reason: reason) } } }
            Button("Keep sale", role: .cancel) { cancelling = nil }
        } message: { Text("The record and its history will remain. Verified totals will be adjusted.") }
    }
    private var salesList: some View {
        List {
            if let error = model.error { Section { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } } } }
            if let d = model.data, d.enabled {
                if d.needs_setup == true {
                    if d.role == "owner" || d.role == "admin" { FieldSalesSettings(data: d, workspace: workspace) }
                    else { Text("An owner must select the reporting currency and timezone.") }
                } else {
                    Section { NavigationLink("Pipeline & follow-ups · Beta") { FieldSalesPipelineRootView() } }
                    if d.pro_sales_version != nil { Section { NavigationLink("Performance reports") { FieldSalesReportView() }; NavigationLink("Goals & pace") { FieldSalesGoalsView() } } }
                    content(d)
                }
            } else if model.loading { ProgressView("Loading Sales…") }
            else if model.error == nil { Text("Sales is not enabled for this workspace.") }
        }
    }
    @ViewBuilder private func content(_ d: FieldSalesSnapshot) -> some View {
        let rankRevenue = revenueRank && d.ranking?.contains(where: { $0.revenue_minor != nil }) == true
        Section {
            Picker("Period", selection: $period) { Text("This week").tag("week"); Text("This month").tag("month"); Text("Last week").tag("previous_week"); Text("Last month").tag("previous_month"); Text("This quarter").tag("quarter"); Text("This year").tag("year") }
            if !leaderboardOnly {
                Toggle("Team sales", isOn: $team)
                if team { Picker("Representative", selection: $rep) { Text("All representatives").tag(nil as UUID?); ForEach(d.ranking ?? []) { Text($0.rep_name).tag(Optional($0.rep_id)) } } }
                Picker("Status", selection: $status) { Text("All statuses").tag(""); Text("Pending").tag("pending"); Text("Verified").tag("verified"); Text("Cancelled").tag("cancelled") }
            }
            Picker("Campaign", selection: $campaign) { Text("All campaigns").tag(nil as UUID?); ForEach(d.options?.campaigns ?? []) { Text($0.name).tag(Optional($0.id)) } }
            if d.manager && !leaderboardOnly { Button("Review pending sales") { team = true; rep = nil; status = "pending" } }
        }
        if !leaderboardOnly {
            if let t = d.totals {
                Section("Verified production") {
                    LabeledContent("Sales · Beta", value: String(t.sales))
                    LabeledContent("Contract value", value: FieldSalesService.money(t.revenue_minor, currency: d.currency))
                    Text("\(d.currency ?? "") · \(d.timezone ?? "")").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Wolfy’s next step") {
                Text(d.coaching ?? "Set a monthly target.")
                if let m = d.metrics {
                    Text("\(m.doors) doors → \(m.conversations) conversations → \(m.leads) new leads → \(m.appointments) elapsed appointments").font(.subheadline)
                    LabeledContent("Sales per 100 doors", value: m.sales_per_100_doors.map { String(format: "%.2f", $0) } ?? "Unavailable")
                    Text("Production ratio; separate from linked conversion cohorts.").font(.caption)
                    LabeledContent("Lead cohort", value: ratio(m.lead_converted, m.leads))
                    LabeledContent("Appointment cohort", value: ratio(m.appointment_converted, m.appointments))
                    if m.unlinked_sales > 0 { Text("\(m.unlinked_sales) sales lack an appointment link; appointment conversion is unavailable.").font(.caption) }
                    Text("Cohorts track source records from this period. As of \(d.as_of ?? "").").font(.caption).foregroundStyle(.secondary)
                }
            }
            FieldSalesGoal(data: d, workspace: workspace, rep: team ? rep : user).id("\(team):\(String(describing: rep)):\(d.goal?.target ?? 0)")
            Section(status == "pending" ? "Pending verification" : "Recent sales") {
                Button("Convert appointment · Beta") { editing = nil; replacement = false; recording = true }
                if let actionError { Text(actionError).foregroundStyle(.red) }
                if d.sales?.isEmpty != false { Text("No sales match these filters.").foregroundStyle(.secondary) }
                ForEach(d.sales ?? []) { sale in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(sale.rep_name) · \(sale.status.capitalized)").font(.headline)
                        Text("\(sale.sold_on) · \(FieldSalesService.money(sale.value_minor, currency: sale.currency))")
                        if let cid = sale.campaign_id { Text(d.options?.campaigns.first { $0.id == cid }?.name ?? "Campaign").font(.caption) }
                        if let notes = sale.notes, !notes.isEmpty { Text(notes).font(.subheadline) }
                        if let reason = sale.cancellation_reason { Text("Reason: \(reason)").font(.caption) }
                        if d.pro_sales_version != nil { NavigationLink("Sale details & payments") { FieldSalesRecordView(sale: sale.id) } }
                        HStack {
                            if d.manager || sale.contact_id != nil { NavigationLink("History · Beta") { FieldSaleHistoryView(workspace: workspace, sale: sale.id) } }
                            if sale.can_edit { Button("Edit") { editing = sale; replacement = false; recording = true } }
                            if sale.can_verify { Button("Verify") { Task { await review("verify", sale) } } }
                            if sale.can_cancel { Button("Cancel", role: .destructive) { cancelling = sale; reason = "" } }
                            if sale.status == "cancelled", sale.contact_id != nil { Button("Replace") { editing = sale; replacement = true; recording = true } }
                        }.buttonStyle(.bordered).disabled(busy)
                    }.padding(.vertical, 4)
                }
                if d.sales?.count == 200 { Text("Showing the latest 200 sales. Narrow filters to find older records.").font(.caption) }
            }
        }
        if d.pro_sales_version != nil {
            Section { NavigationLink("Team leaderboards") { FieldSalesLeaderboardView() } }
        } else {
        Section("Team leaderboard") {
            if d.ranking?.contains(where: { $0.revenue_minor != nil }) == true { Toggle("Rank by revenue", isOn: $revenueRank) }
            ForEach((d.ranking ?? []).sorted { rankRevenue ? (Decimal(string: $0.revenue_minor ?? "0") ?? 0) > (Decimal(string: $1.revenue_minor ?? "0") ?? 0) : $0.sales > $1.sales }) { row in
                LabeledContent(row.rep_name, value: rankRevenue ? FieldSalesService.money(row.revenue_minor, currency: d.currency) : "\(row.sales) sales")
            }
        }
        }
        if !leaderboardOnly {
            Section("Recent team wins") { ForEach(d.feed ?? []) { win in
                VStack(alignment: .leading) { Text("\(win.rep_name) recorded a verified sale"); Text(win.sold_on).font(.caption); if win.value_minor != nil { Text(FieldSalesService.money(win.value_minor, currency: d.currency)) } }
            } }
            if d.manager { Section { DisclosureGroup("Sales settings · Beta") { FieldSalesSettings(data: d, workspace: workspace) } } }
        }
    }
    private func ratio(_ n: Int?, _ denominator: Int) -> String { guard let n, denominator > 0 else { return "Unavailable" }; return "\(n) / \(denominator) (\(Int((Double(n) / Double(denominator) * 100).rounded()))%)" }
    private func reload() async { await model.load(filter) }
    private func review(_ action: String, _ sale: FieldSalesSnapshot.Sale, reason: String = "") async {
        busy = true; actionError = nil
        do { try await FieldSalesService.command(workspace, action, ["id": sale.id.uuidString, "version": String(sale.version), "reason": reason]) }
        catch { actionError = error.localizedDescription }
        busy = false
    }
}

private struct FieldSaleEditor: View {
    let data: FieldSalesSnapshot
    let workspace: UUID
    let initial: FieldSalesSnapshot.Sale?
    let replacement: Bool
    let leadID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var contact = ""
    @State private var rep = ""
    @State private var appointment = ""
    @State private var amount = ""
    @State private var soldOn = ""
    @State private var notes = ""
    @State private var requestID = UUID()
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        Form {
            Picker("Existing lead", selection: Binding(get: { contact }, set: { contact = $0; appointment = "" })) { Text("Select lead").tag(""); ForEach(data.options?.leads ?? []) { Text($0.name).tag($0.id.uuidString) } }
            Text("Campaign and territory follow the selected lead’s campaign.").font(.caption)
            Picker("Representative", selection: $rep) { ForEach(data.ranking ?? []) { Text($0.rep_name).tag($0.rep_id.uuidString) } }.disabled(!data.manager)
            Picker("Appointment (required)", selection: $appointment) { Text("Select appointment").tag(""); ForEach((data.options?.appointments ?? []).filter { $0.contact_id.uuidString == contact }) { Text($0.scheduled_at).tag($0.id.uuidString) } }
            TextField("Contract value (\(data.currency ?? ""))", text: $amount).keyboardType(.decimalPad)
            TextField("Sale date (YYYY-MM-DD)", text: $soldOn).keyboardType(.numbersAndPunctuation)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
            Text("Pending until verified by an authorized manager.").font(.caption)
            if let error { Text(error).foregroundStyle(.red) }
            Button("Save sale") { Task { await save() } }.disabled(busy || contact.isEmpty || appointment.isEmpty)
        }.navigationTitle(initial != nil && !replacement ? "Edit sale" : "Convert appointment · Beta")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
        .onAppear {
            contact = (initial?.contact_id ?? leadID)?.uuidString ?? ""; rep = (initial?.rep_id ?? data.user_id)?.uuidString ?? ""
            appointment = initial?.appointment_id?.uuidString ?? ""; amount = FieldSalesService.editableMoney(initial?.value_minor, currency: data.currency)
            soldOn = initial?.sold_on ?? data.today ?? ""; notes = initial?.notes ?? ""
        }
    }
    private func save() async {
        busy = true; error = nil
        do {
            var payload = ["request_id": requestID.uuidString, "contact_id": contact, "rep_id": rep, "appointment_id": appointment,
                           "value_minor": try FieldSalesService.minorUnits(amount, currency: data.currency ?? "CAD"), "sold_on": soldOn, "notes": notes]
            if let initial { if replacement { payload["replaces_id"] = initial.id.uuidString } else { payload["id"] = initial.id.uuidString; payload["version"] = String(initial.version) } }
            try await FieldSalesService.command(workspace, initial != nil && !replacement ? "edit" : "submit", payload)
            dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}

struct FieldSalesSettings: View {
    let data: FieldSalesSnapshot; let workspace: UUID
    @State private var currency = ""; @State private var timezone = ""; @State private var visible = false
    @State private var error: String?; @State private var busy = false
    var body: some View {
        Group {
            Picker("Reporting currency", selection: $currency) { Text("Select currency").tag(""); ForEach(["CAD","USD","EUR","GBP","AUD","NZD","JPY","CHF"], id: \.self) { Text($0).tag($0) } }
            TextField("Timezone, e.g. America/Toronto", text: $timezone).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text("Currency and timezone lock after the first sale.").font(.caption)
            Toggle("Show team revenue and contract values", isOn: $visible)
            if let error { Text(error).foregroundStyle(.red) }
            Button("Save settings") { Task {
                busy = true
                do { try await FieldSalesService.command(workspace, "settings", ["currency": currency, "timezone": timezone, "team_revenue_visible": String(visible)]); error = nil }
                catch { self.error = error.localizedDescription }; busy = false
            } }.disabled(busy || currency.isEmpty || timezone.isEmpty)
        }.onAppear { currency = data.currency ?? ""; timezone = data.timezone ?? ""; visible = data.team_revenue_visible ?? false }
    }
}

private struct FieldSalesGoal: View {
    let data: FieldSalesSnapshot; let workspace: UUID; let rep: UUID?
    @State private var target = ""; @State private var error: String?; @State private var busy = false
    var body: some View {
        Section("Monthly sales target") {
            if let g = data.goal { Text("\(g.completed) / \(g.target.map(String.init) ?? "—") sales"); if let t = g.target { ProgressView(value: Double(min(g.completed,t)), total: Double(t)) } }
            if rep == data.user_id || (rep == nil && data.manager) {
                TextField("Target (blank to clear)", text: $target).keyboardType(.numberPad)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save target") { Task {
                    busy = true
                    do {
                        var payload = ["month": data.month ?? "", "rep_id": rep?.uuidString ?? ""]
                        if !target.isEmpty { payload["target"] = target }
                        try await FieldSalesService.command(workspace, "goal", payload); error = nil
                    } catch { self.error = error.localizedDescription }; busy = false
                } }.disabled(busy)
            }
        }.onAppear { target = data.goal?.target.map(String.init) ?? "" }
    }
}

private struct FieldSaleHistoryView: View {
    let workspace: UUID; let sale: UUID
    @State private var events: [FieldSalesService.HistoryEvent] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(event.actor) · \(event.action)").font(.headline)
                    Text(event.created_at).font(.caption)
                    if let version = event.version, let status = event.status { Text("Version \(version) · \(status)") }
                    if let value = event.value_minor { Text(FieldSalesService.money(value, currency: event.currency)) }
                    if let date = event.sold_on { Text("Sale date: \(date)") }
                    if let reason = event.reason { Text(reason) }
                }
            }
        }.navigationTitle("Sale history · Beta").task { await reload() }.refreshable { await reload() }
    }
    private func reload() async {
        do { let value = try await FieldSalesService.history(workspace, sale: sale); guard !Task.isCancelled else { return }; events = value; error = nil }
        catch { guard !Task.isCancelled else { return }; self.error = error.localizedDescription }
    }
}
