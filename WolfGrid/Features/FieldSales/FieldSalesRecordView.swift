import SwiftUI
import Supabase

struct FieldSaleRecord: Decodable, Identifiable {
    let id: UUID
    let version: Int
    let currency: String
    let status: String
    let sold_on: String
    let rep_name_snapshot: String
    let campaign_name_snapshot: String?
    let product: String
    let notes: String
    let value_minor: String?
    let completed_value_minor: String?
    let collected_revenue_minor: String?
    let net_sold_value_minor: String?
    let expected_completion_on: String?
    let fulfillment_status: String
    let attribution_method: String
    let attribution_confidence: String
    let property_snapshot: Property
    let cancellation_reason: String?
    let can_verify: Bool
    let can_complete: Bool
    let can_collect: Bool
    let can_cancel: Bool
    let credits: [Credit]
    let payments: [Payment]
    let events: [Event]
    let timeline: [TimelineItem]

    struct Property: Decodable { let address: String? }
    struct Credit: Decodable, Identifiable {
        let user_id: UUID; let rep_name: String; let role: String; let basis_points: Int
        let credited_value_minor: String?; let team_name: String?
        var id: UUID { user_id }
    }
    struct Payment: Decodable, Identifiable {
        let id: UUID; let kind: String; let amount_minor: String; let occurred_at: String; let note: String
    }
    struct Event: Decodable, Identifiable {
        let id: UUID; let action: String; let actor: String; let created_at: String; let reason: String?
    }
    struct TimelineItem: Decodable {
        let id: UUID; let kind: String; let at: String; let note: String?
    }

    static func load(workspace: UUID, sale: UUID) async throws -> FieldSaleRecord {
        struct Params: Encodable { let p_workspace: UUID; let p_sale: UUID }
        return try await SupabaseManager.shared.client.rpc("field_sales_record", params: Params(p_workspace: workspace, p_sale: sale)).execute().value
    }
}

struct FieldSalesRecordView: View {
    let sale: UUID
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var context = WorkspaceContext.shared
    var body: some View {
        Group {
            if let user = auth.user?.id, let workspace = context.workspaceId {
                FieldSalesRecordContent(workspace: workspace, sale: sale).id("\(user):\(workspace):\(sale)")
            } else { ContentUnavailableView("Sale details", systemImage: "doc.text", description: Text("Sign in and select a workspace.")) }
        }
    }
}

private struct FieldSalesRecordContent: View {
    let workspace: UUID
    let sale: UUID
    @Environment(\.scenePhase) private var scene
    @State private var record: FieldSaleRecord?
    @State private var error: String?
    @State private var generation = UUID()
    @State private var updating = false

    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } } } }
            if let s = record {
                Section {
                    Text(s.property_snapshot.address ?? (s.product.isEmpty ? "Sale details" : s.product)).font(.title2.bold())
                    Text("\(s.rep_name_snapshot) · \(s.sold_on)").foregroundStyle(.secondary)
                    Text(s.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    if let reason = s.cancellation_reason { Text(reason).font(.subheadline) }
                }
                Section("Revenue") {
                    moneyRow("Signed contract", s.value_minor, s.currency)
                    moneyRow("Completed value", s.completed_value_minor, s.currency)
                    moneyRow("Collected revenue", s.collected_revenue_minor, s.currency)
                    moneyRow("Net eligible sold value", s.net_sold_value_minor, s.currency)
                    Text("Collected revenue reflects recorded payments and refunds. Cancelling a contract does not record a cash refund.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Attribution") {
                    Text("\(s.attribution_method.replacingOccurrences(of: "_", with: " ")) · \(s.attribution_confidence) evidence").font(.caption).foregroundStyle(.secondary)
                    ForEach(s.credits) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(c.rep_name); Spacer(); Text("\(Double(c.basis_points) / 100, specifier: "%.2f")% credit") }
                            Text(c.role.replacingOccurrences(of: "_", with: " ").capitalized + (c.team_name.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                            if let value = c.credited_value_minor { Text(FieldSalesService.money(value, currency: s.currency)).font(.subheadline) }
                        }
                    }
                    Text("Credit shares divide one contract. Company sold value counts it once.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Job details") {
                    LabeledContent("Product / service", value: s.product.isEmpty ? "Not specified" : s.product)
                    LabeledContent("Campaign", value: s.campaign_name_snapshot ?? "Unassigned")
                    LabeledContent("Fulfillment", value: s.fulfillment_status.replacingOccurrences(of: "_", with: " ").capitalized)
                    LabeledContent("Expected completion", value: s.expected_completion_on ?? "Not scheduled")
                    if !s.notes.isEmpty { Text(s.notes) }
                }
                if s.can_verify || s.can_complete || s.can_collect || s.can_cancel {
                    Section { Button("Update sale") { updating = true }.fontWeight(.semibold) }
                }
                Section("Property timeline") {
                    ForEach(Array(s.timeline.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading) {
                            Text(entry.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                            Text(String(entry.at.prefix(10))).font(.caption).foregroundStyle(.secondary)
                            if let note = entry.note { Text(note).font(.subheadline) }
                        }
                    }
                }
                if !s.payments.isEmpty {
                    Section("Payment ledger") {
                        ForEach(s.payments) { p in
                            VStack(alignment: .leading) {
                                moneyRow(p.kind.capitalized, p.amount_minor, s.currency)
                                Text(String(p.occurred_at.prefix(10))).font(.caption).foregroundStyle(.secondary)
                                if !p.note.isEmpty { Text(p.note).font(.subheadline) }
                            }
                        }
                    }
                }
                Section {
                    DisclosureGroup("Audit history") {
                        ForEach(s.events) { event in
                            VStack(alignment: .leading) {
                                Text("\(event.actor) · \(event.action.replacingOccurrences(of: "_", with: " "))").font(.subheadline)
                                Text(String(event.created_at.prefix(10))).font(.caption).foregroundStyle(.secondary)
                                if let reason = event.reason { Text(reason).font(.subheadline) }
                            }
                        }
                    }
                }
            } else if error == nil { ProgressView("Loading sale…") }
        }
        .navigationTitle("Sale details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldSalesChanged)) { _ in Task { await reload() } }
        .onChange(of: scene) { _, value in if value == .active { Task { await reload() } } }
        .onDisappear { generation = UUID() }
        .sheet(isPresented: $updating) { if let s = record { NavigationStack { FieldSaleUpdateForm(workspace: workspace, sale: s) } } }
    }

    private func moneyRow(_ title: String, _ value: String?, _ currency: String) -> some View {
        LabeledContent(title, value: FieldSalesService.money(value, currency: currency)).monospacedDigit()
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket
        do {
            let next = try await FieldSaleRecord.load(workspace: workspace, sale: sale)
            guard generation == ticket, !Task.isCancelled else { return }
            record = next; error = nil
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            record = nil; self.error = error.localizedDescription
        }
    }
}

private struct FieldSaleUpdateForm: View {
    let workspace: UUID
    let sale: FieldSaleRecord
    @Environment(\.dismiss) private var dismiss
    @State private var action = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var reason = ""
    @State private var busy = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var fingerprint = ""
    private var actions: [(String, String)] {
        var values: [(String, String)] = []
        if sale.can_verify { values += [("verify", "Verify sale"), ("reject", "Reject submission")] }
        if sale.can_complete { values += [("complete", "Record completion")] }
        if sale.can_collect {
            if sale.status == "verified" { values += [("collect", "Record payment")] }
            values += [("refund_payment", "Record payment refund"), ("chargeback_payment", "Record payment chargeback")]
        }
        if sale.can_cancel { values += [("cancel", "Cancel sale")] }
        return values
    }
    private var payment: Bool { ["collect", "refund_payment", "chargeback_payment"].contains(action) }
    private var requiresReason: Bool { ["cancel", "reject"].contains(action) }
    var body: some View {
        Form {
            Picker("Action", selection: $action) { ForEach(actions, id: \.0) { entry in Text(entry.1).tag(entry.0) } }
            if payment { TextField("Amount (\(sale.currency))", text: $amount).keyboardType(.decimalPad) }
            if payment || action == "complete" {
                DatePicker(payment ? "Payment time" : "Completion date", selection: $date, in: ...Date(), displayedComponents: payment ? [.date, .hourAndMinute] : [.date])
                if payment { Text("Time is shown in your device timezone.").font(.caption).foregroundStyle(.secondary) }
            }
            TextField(requiresReason ? "Reason" : "Note (optional)", text: $reason, axis: .vertical).lineLimit(2...4)
            if let error { Text(error).foregroundStyle(.red) }
            Button(busy ? "Saving…" : (actions.first { $0.0 == action }?.1 ?? "Save")) { Task { await save() } }
                .disabled(busy || action.isEmpty || (payment && amount.isEmpty) || (requiresReason && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        }
        .navigationTitle("Update sale")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
        .onAppear { if action.isEmpty { action = actions.first?.0 ?? "" } }
    }
    private func save() async {
        busy = true; error = nil
        do {
            var payload = ["id": sale.id.uuidString, "version": String(sale.version), "reason": reason]
            if payment {
                payload["amount_minor"] = try FieldSalesService.minorUnits(amount, currency: sale.currency)
                payload["occurred_at"] = ISO8601DateFormatter().string(from: date); payload["note"] = reason
            }
            if action == "complete" {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                payload["completed_on"] = formatter.string(from: date)
            }
            let nextFingerprint = action + payload.keys.sorted().map { "\($0):\(payload[$0] ?? "")" }.joined(separator: "\n")
            if fingerprint != nextFingerprint { requestID = UUID(); fingerprint = nextFingerprint }
            payload["request_id"] = requestID.uuidString
            try await FieldSalesService.command(workspace, action, payload)
            dismiss()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
