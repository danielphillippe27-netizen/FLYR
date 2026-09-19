import SwiftUI
import Supabase

private struct SaleEntrySnapshot: Decodable {
    let capabilities: [String: Bool]?
    let enabled: Bool; let needs_setup: Bool?; let currency: String?; let today: String?; let verification_required: Bool?
    let can_override_duplicate: Bool?; let has_more_appointments: Bool?
    let appointment_options: [AppointmentOption]?; let selected: Selected?; let duplicates: [Duplicate]?
    struct AppointmentOption: Decodable, Identifiable { let id: UUID; let contact_id: UUID; let name: String; let address: String?; let scheduled_at: String; let note: String? }
    struct Selected: Decodable { let id: UUID; let name: String; let address: String?; let rep_id: UUID; let appointment_id: UUID; let appointment_at: String; let appointment_note: String? }
    struct Duplicate: Decodable, Identifiable { let id: UUID; let product: String; let sold_on: String; let status: String }
}
struct FieldSalesMarkSoldView: View {
    let workspace: UUID; let initial: [String:String]; let saved: (UUID) -> Void
    @State private var context: [String:String]
    @State private var data: SaleEntrySnapshot?
    @State private var error: String?
    @State private var search = ""
    @State private var busy = false
    @State private var generation = UUID()
    @Environment(\.dismiss) private var dismiss
    init(workspace: UUID, initial: [String:String] = [:], saved: @escaping (UUID) -> Void) { self.workspace = workspace; self.initial = initial; self.saved = saved; _context = State(initialValue: initial) }
    var body: some View {
        Group {
            if let d = data, let selected = d.selected {
                SaleEntryForm(workspace: workspace, data: d, selected: selected, busy: $busy, saved: saved, change: { context = [:] }).id(selected.appointment_id)
            } else {
                List {
                    if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } }; Button("Choose another appointment") { context = [:] } }
                    if let d = data {
                        if !d.enabled || d.needs_setup == true { Text("Set up Sales before recording a sale.") }
                        else {
                            Section { Text("Choose a past appointment. Sales cannot be created directly from a lead.").font(.subheadline); TextField("Customer, address or appointment note", text: $search).onSubmit { context = ["search":search] }; Button("Search appointments") { context = ["search":search] } }
                            ForEach(d.appointment_options ?? []) { appointment in Button { context = ["appointment_id":appointment.id.uuidString,"contact_id":appointment.contact_id.uuidString] } label: { VStack(alignment: .leading) { Text(appointment.name); Text(appointment.scheduled_at).font(.caption).foregroundStyle(.secondary); if let address = appointment.address { Text(address).font(.caption).foregroundStyle(.secondary) }; if let note = appointment.note, !note.isEmpty { Text(note).font(.subheadline) } } } }
                            if d.has_more_appointments == true { Text("Refine your search to find more appointments.").font(.caption) }
                            if d.appointment_options?.isEmpty == true { Text("No eligible past appointments are waiting to be converted.") }
                        }
                    } else if error == nil { ProgressView("Loading sale details…") }
                }
            }
        }.navigationTitle("Convert appointment").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
        .task(id: context) { await reload() }
        .onDisappear { generation = UUID() }
    }
    private func reload() async {
        let ticket = UUID(); generation = ticket; data = nil; error = nil
        struct Params: Encodable { let p_workspace: UUID; let p_context: [String:String] }
        do { let next: SaleEntrySnapshot = try await SupabaseManager.shared.client.rpc("field_sales_entry", params: Params(p_workspace: workspace, p_context: context)).execute().value; guard generation == ticket, !Task.isCancelled else { return }; data = next }
        catch { guard generation == ticket, !Task.isCancelled else { return }; self.error = error.localizedDescription }
    }
}
private struct SaleEntryForm: View {
    let workspace: UUID; let data: SaleEntrySnapshot; let selected: SaleEntrySnapshot.Selected; @Binding var busy: Bool; let saved: (UUID) -> Void; let change: () -> Void
    @State private var amount = ""
    @State private var commissionEnabled = false
    @State private var commissionPercentage = ""
    @State private var commissionFixedFee = false
    @State private var commissionFee = ""
    @State private var product = ""
    @State private var notes = ""
    @State private var soldOn = Date()
    @State private var completion = Date()
    @State private var hasCompletion = false
    @State private var job = ""
    @State private var reason = ""
    @State private var request = UUID()
    @State private var error: String?
    @State private var initialized = false
    init(workspace: UUID, data: SaleEntrySnapshot, selected: SaleEntrySnapshot.Selected, busy: Binding<Bool>, saved: @escaping (UUID)->Void, change: @escaping ()->Void) {
        self.workspace = workspace; self.data = data; self.selected = selected; _busy = busy; self.saved = saved; self.change = change
    }
    private var duplicate: Bool { data.duplicates?.isEmpty == false }
    private var format: DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }
    var body: some View {
        Form {
            Section { Text(selected.name).font(.headline); if let address = selected.address { Text(address).foregroundStyle(.secondary) }; Text("Appointment · \(selected.appointment_at)").font(.caption).foregroundStyle(.secondary); if let note = selected.appointment_note, !note.isEmpty { Text(note) }; Button("Choose another appointment", action: change).disabled(busy) }
            Section("Contract value (\(data.currency ?? ""))") { TextField("0.00", text: $amount).keyboardType(.decimalPad).font(.largeTitle).monospacedDigit() }
            if data.capabilities?["commission"] == true {
                Section("Commission") {
                    Toggle("Commission", isOn: $commissionEnabled).disabled(busy)
                    if commissionEnabled {
                        Picker("Commission type", selection: $commissionFixedFee) {
                            Text("Percentage").tag(false)
                            Text("Fixed fee").tag(true)
                        }.pickerStyle(.segmented).disabled(busy)
                        if commissionFixedFee {
                            TextField("Fixed fee (\(data.currency ?? "CAD"))", text: $commissionFee).keyboardType(.decimalPad).disabled(busy)
                        } else {
                            TextField("Commission (%)", text: $commissionPercentage).keyboardType(.decimalPad).disabled(busy)
                        }
                        if let calculated = try? commissionMinor() {
                            LabeledContent("Expected commission", value: FieldSalesService.money(calculated, currency: data.currency))
                        }
                        Text("Counts after verification; payment is tracked separately.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if duplicate {
                Section("Existing sale") {
                    Text("An existing sale may already be associated with this customer.")
                    ForEach(data.duplicates ?? []) { s in NavigationLink("\(s.product.isEmpty ? "Sale" : s.product) · \(s.sold_on) · \(s.status)") { FieldSalesRecordView(sale: s.id) } }
                    if data.can_override_duplicate == true { TextField("Separate job identifier", text: $job); TextField("Why is this a separate job?", text: $reason) }
                    else { Text("A manager can confirm a legitimate separate job.").font(.caption) }
                }
            }
            Section {
                DisclosureGroup("Sale details") {
                    TextField("Product / service", text: $product)
                    DatePicker("Sold date", selection: $soldOn, in: ...(format.date(from: data.today ?? "") ?? Date()), displayedComponents: .date)
                    Toggle("Expected completion date", isOn: $hasCompletion)
                    if hasCompletion { DatePicker("Expected completion", selection: $completion, in: soldOn..., displayedComponents: .date) }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }
            Section {
                Text(data.verification_required == true ? "The sale will await verification before it counts toward official totals." : "The sale will count toward official totals immediately.").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? "Saving…" : "Confirm sale") { Task { await save() } }.fontWeight(.semibold).disabled(busy || amount.isEmpty || (duplicate && (data.can_override_duplicate != true || job.isEmpty || reason.isEmpty)))
            }
        }.task { guard !initialized else { return }; soldOn = format.date(from: data.today ?? "") ?? Date(); completion = soldOn; initialized = true }
    }
    private func commissionMinor() throws -> String {
        if commissionFixedFee { return try FieldSalesService.minorUnits(commissionFee, currency: data.currency ?? "CAD") }
        return try FieldSalesService.commissionMinorUnits(value: amount, percentage: commissionPercentage, currency: data.currency ?? "CAD")
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        struct Payload: Encodable { let request_id: UUID; let contact_id: UUID; let appointment_id: UUID; let value_minor: String; let commission_minor: String?; let product: String; let sold_on: String; let expected_completion_on: String?; let notes: String; let job_identifier: String?; let duplicate_override_reason: String? }
        struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: Payload }
        struct Result: Decodable { let id: UUID }
        do {
            let payload = Payload(request_id:request,contact_id:selected.id,appointment_id:selected.appointment_id,value_minor:try FieldSalesService.minorUnits(amount,currency:data.currency ?? "CAD"),commission_minor:data.capabilities?["commission"] == true && commissionEnabled ? try commissionMinor() : nil,product:product,sold_on:format.string(from:soldOn),expected_completion_on:hasCompletion ? format.string(from:completion) : nil,notes:notes,job_identifier:duplicate ? job : nil,duplicate_override_reason:duplicate ? reason : nil)
            let result: Result = try await SupabaseManager.shared.client.rpc("field_sales_command", params:Params(p_workspace:workspace,p_action:"submit",p_data:payload)).execute().value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name:.fieldSalesChanged,object:nil); saved(result.id)
        } catch { self.error = error.localizedDescription }
    }
}
