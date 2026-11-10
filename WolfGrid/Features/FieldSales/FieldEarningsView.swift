import SwiftUI
import Supabase

private struct FieldEarningsSnapshot: Decodable {
    struct Summary: Decodable {
        let total_minor: String
        let pending_minor: String
        let approved_minor: String
        let paid_minor: String
        let adjustments_minor: String
        let sales: Int
        let appointments: Int
    }
    struct Entry: Decodable, Identifiable {
        struct Calculation: Decodable {
            let rate_bps: Int?
            let reason: String?
        }
        let id: UUID
        let kind: String
        let status: String
        let amount_minor: String
        let basis_minor: String?
        let currency: String
        let accrued_at: String
        let paid_at: String?
        let payment_reference: String?
        let source_label: String?
        let sale_id: UUID?
        let appointment_id: UUID?
        let plan_title: String?
        let plan_version: Int?
        let calculation: Calculation

        var title: String {
            switch kind {
            case "held_fee": return "Appointment fee"
            case "sale_fee": return "Sale fee"
            case "contract_percent": return "Contract commission"
            case "cash_percent": return "Collection commission"
            default: return kind.capitalized
            }
        }
    }
    let enabled: Bool
    let currency: String?
    let timezone: String?
    let count: Int?
    let summary: Summary?
    let entries: [Entry]?
}

struct FieldEarningsView: View {
    let workspace: UUID
    @State private var data: FieldEarningsSnapshot?
    @State private var period = "all"
    @State private var dateMode = "accrued"
    @State private var offset = 0
    @State private var failure: String?
    @State private var busy = false

    var body: some View {
        List {
            if data?.enabled == true {
                Section {
                    Picker("Period", selection: $period) {
                        Text("All time").tag("all")
                        Text("Last 30 days").tag("month")
                        Text("Last 7 days").tag("week")
                    }
                    Picker("Date basis", selection: $dateMode) {
                        Text("Accrued").tag("accrued")
                        Text("Paid").tag("paid")
                    }
                }
                if let summary = data?.summary {
                    Section("Earnings") {
                        Text(FieldSalesService.money(summary.total_minor, currency: data?.currency))
                            .font(.largeTitle.bold()).monospacedDigit()
                        metric("Pending", summary.pending_minor)
                        metric("Approved unpaid", summary.approved_minor)
                        metric("Paid", summary.paid_minor)
                        metric("Adjustments and reversals", summary.adjustments_minor)
                        LabeledContent("Credited sales", value: String(summary.sales))
                        LabeledContent("Credited appointments", value: String(summary.appointments))
                    }
                }
                Section("Details") {
                    if data?.entries?.isEmpty == true { Text("No earnings in this period.").foregroundStyle(.secondary) }
                    ForEach(data?.entries ?? []) { entry in
                        NavigationLink {
                            FieldEarningDetail(entry: entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.title)
                                    if let source = entry.source_label { Text(source).font(.caption).foregroundStyle(.secondary) }
                                    Text(entry.status.capitalized).font(.caption)
                                }
                                Spacer()
                                Text(FieldSalesService.money(entry.amount_minor, currency: entry.currency))
                                    .font(.headline).monospacedDigit()
                            }
                        }
                    }
                    if offset > 0 || offset + 100 < (data?.count ?? 0) {
                        HStack {
                            Button("Previous") { offset -= 100 }.disabled(busy || offset == 0)
                            Spacer()
                            Button("Next") { offset += 100 }.disabled(busy || offset + 100 >= (data?.count ?? 0))
                        }.buttonStyle(.borderless)
                    }
                }
            } else if data?.enabled == false { Text("Earnings are unavailable for this workspace.") }
            else if failure == nil { ProgressView("Loading earnings") }
            if let failure {
                Text(failure).foregroundStyle(.red)
                Button("Retry") { Task { await load() } }
            }
        }
        .navigationTitle("My Earnings")
        .task(id: "\(workspace):\(period):\(dateMode):\(offset)") { await load() }
        .onChange(of: period) { _, _ in offset = 0 }
        .onChange(of: dateMode) { _, _ in offset = 0 }
        .refreshable { await load() }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: FieldSalesService.money(value, currency: data?.currency))
    }

    private func load() async {
        busy = true
        defer { busy = false }
        struct Params: Encodable { let p_workspace: UUID; let p_filter: [String: String] }
        var filter = ["offset": String(offset), "date_mode": dateMode]
        if period != "all" {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = data?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
            let format = DateFormatter()
            format.calendar = calendar
            format.timeZone = calendar.timeZone
            format.locale = Locale(identifier: "en_US_POSIX")
            format.dateFormat = "yyyy-MM-dd"
            if let start = calendar.date(byAdding: .day, value: period == "week" ? -6 : -29, to: Date()) {
                filter["start_on"] = format.string(from: start)
            }
        }
        do {
            let result: FieldEarningsSnapshot = try await SupabaseManager.shared.client.rpc("field_earnings_list",
                params: Params(p_workspace: workspace, p_filter: filter)).execute().value
            guard !Task.isCancelled else { return }
            data = result
            failure = nil
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
    }
}

private struct FieldEarningDetail: View {
    let entry: FieldEarningsSnapshot.Entry
    var body: some View {
        Form {
            Section {
                Text(FieldSalesService.money(entry.amount_minor, currency: entry.currency))
                    .font(.largeTitle.bold()).monospacedDigit()
                LabeledContent("Status", value: entry.status.capitalized)
                if let name = entry.source_label { LabeledContent("Customer", value: name) }
                if let basis = entry.basis_minor {
                    LabeledContent("Calculation basis", value: FieldSalesService.money(basis, currency: entry.currency))
                }
                if let rate = entry.calculation.rate_bps {
                    LabeledContent("Rate", value: (Decimal(rate) / 100).description + "%")
                }
                if let plan = entry.plan_title {
                    LabeledContent("Plan", value: plan + " · v\(entry.plan_version ?? 1)")
                }
                if let reason = entry.calculation.reason { LabeledContent("Reason", value: reason) }
            }
            Section("Dates") {
                if let date = FieldAppointments.date(entry.accrued_at) {
                    LabeledContent("Accrued") { Text(date, format: .dateTime) }
                }
                if let paid = entry.paid_at, let date = FieldAppointments.date(paid) {
                    LabeledContent("Paid") { Text(date, format: .dateTime) }
                }
                if let reference = entry.payment_reference { LabeledContent("Payment reference", value: reference) }
            }
            if let sale = entry.sale_id { NavigationLink("View sale") { FieldSalesRecordView(sale: sale) } }
            if let appointment = entry.appointment_id, let user = AuthManager.shared.user?.id,
               let workspace = WorkspaceContext.shared.workspaceId {
                NavigationLink("View appointment") {
                    FieldAppointmentDetailView(user: user, workspace: workspace, id: appointment, canWrite: false)
                }
            }
        }.navigationTitle(entry.title)
    }
}
