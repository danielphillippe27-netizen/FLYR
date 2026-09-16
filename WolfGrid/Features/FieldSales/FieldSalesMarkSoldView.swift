import SwiftUI
import Supabase

private struct SaleEntrySnapshot: Decodable {
    let enabled: Bool; let needs_setup: Bool?; let currency: String?; let today: String?; let verification_required: Bool?
    let can_assign: Bool?; let can_override_duplicate: Bool?; let has_more_contacts: Bool?
    let contacts: [Contact]?; let representatives: [Representative]?; let selected: Selected?; let appointments: [Appointment]?; let duplicates: [Duplicate]?
    struct Contact: Decodable, Identifiable { let id: UUID; let name: String; let address: String? }
    struct Representative: Decodable, Identifiable { let id: UUID; let name: String }
    struct Selected: Decodable { let id: UUID; let name: String; let address: String?; let rep_id: UUID; let setter_id: UUID; let closer_id: UUID; let appointment_id: UUID?; let opportunity_id: UUID? }
    struct Appointment: Decodable, Identifiable { let id: UUID; let scheduled_at: String }
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
                SaleEntryForm(workspace: workspace, data: d, selected: selected, busy: $busy, saved: saved, change: { context = [:] }).id(selected.id)
            } else {
                List {
                    if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await reload() } }; Button("Choose another prospect") { context = [:] } }
                    if let d = data {
                        if !d.enabled || d.needs_setup == true { Text("Set up Sales before recording a sale.") }
                        else {
                            Section { TextField("Name, address, phone or email", text: $search).onSubmit { context["search"] = search }; Button("Search prospects") { context["search"] = search } }
                            ForEach(d.contacts ?? []) { c in Button { context["contact_id"] = c.id.uuidString } label: { VStack(alignment: .leading) { Text(c.name); if let address = c.address { Text(address).font(.caption).foregroundStyle(.secondary) } } } }
                            if d.has_more_contacts == true { Text("Refine your search to find more prospects.").font(.caption) }
                            if d.contacts?.isEmpty == true { Text("No accessible prospects match.") }
                        }
                    } else if error == nil { ProgressView("Loading sale details…") }
                }
            }
        }.navigationTitle("Mark as sold").navigationBarTitleDisplayMode(.inline)
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
    @State private var product = ""
    @State private var notes = ""
    @State private var soldOn = Date()
    @State private var completion = Date()
    @State private var hasCompletion = false
    @State private var rep: UUID
    @State private var setter: UUID
    @State private var closer: UUID
    @State private var appointment: UUID?
    @State private var split = false
    @State private var setterPercent = "50"
    @State private var job = ""
    @State private var reason = ""
    @State private var request = UUID()
    @State private var error: String?
    @State private var initialized = false
    init(workspace: UUID, data: SaleEntrySnapshot, selected: SaleEntrySnapshot.Selected, busy: Binding<Bool>, saved: @escaping (UUID)->Void, change: @escaping ()->Void) {
        self.workspace = workspace; self.data = data; self.selected = selected; _busy = busy; self.saved = saved; self.change = change
        _rep = State(initialValue: selected.rep_id); _setter = State(initialValue: selected.setter_id); _closer = State(initialValue: selected.closer_id); _appointment = State(initialValue: selected.appointment_id)
    }
    private var duplicate: Bool { data.duplicates?.isEmpty == false }
    private var format: DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }
    var body: some View {
        Form {
            Section { Text(selected.name).font(.headline); if let address = selected.address { Text(address).foregroundStyle(.secondary) }; Button("Change prospect", action: change).disabled(busy) }
            Section("Contract value (\(data.currency ?? ""))") { TextField("0.00", text: $amount).keyboardType(.decimalPad).font(.largeTitle).monospacedDigit() }
            if duplicate {
                Section("Existing sale") {
                    Text("An existing sale may already be associated with this customer.")
                    ForEach(data.duplicates ?? []) { s in NavigationLink("\(s.product.isEmpty ? "Sale" : s.product) · \(s.sold_on) · \(s.status)") { FieldSalesRecordView(sale: s.id) } }
                    if data.can_override_duplicate == true { TextField("Separate job identifier", text: $job); TextField("Why is this a separate job?", text: $reason) }
                    else { Text("A manager can confirm a legitimate separate job.").font(.caption) }
                }
            }
            Section {
                DisclosureGroup("Sale details & attribution") {
                    TextField("Product / service", text: $product)
                    DatePicker("Sold date", selection: $soldOn, in: ...(format.date(from: data.today ?? "") ?? Date()), displayedComponents: .date)
                    Toggle("Expected completion date", isOn: $hasCompletion)
                    if hasCompletion { DatePicker("Expected completion", selection: $completion, in: soldOn..., displayedComponents: .date) }
                    Picker("Appointment", selection: $appointment) { Text("No linked appointment").tag(UUID?.none); ForEach(data.appointments ?? []) { Text($0.scheduled_at).tag(Optional($0.id)) } }
                    if data.can_assign == true {
                        repPicker("Primary rep", selection: $rep); repPicker("Setter", selection: $setter); repPicker("Closer", selection: $closer)
                        Toggle("Split revenue credit", isOn: $split)
                        if split { TextField("Setter credit (%)", text: $setterPercent).keyboardType(.decimalPad); Text("Closer receives the remaining share.").font(.caption) }
                    }
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
    private func repPicker(_ label: String, selection: Binding<UUID>) -> some View { Picker(label, selection: selection) { ForEach(data.representatives ?? []) { Text($0.name).tag($0.id) } } }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        struct Credit: Encodable { let user_id: UUID; let role: String; let basis_points: Int }
        struct Payload: Encodable { let request_id: UUID; let contact_id: UUID; let opportunity_id: UUID?; let appointment_id: UUID?; let value_minor: String; let product: String; let sold_on: String; let expected_completion_on: String?; let notes: String; let rep_id: UUID; let setter_id: UUID; let closer_id: UUID; let credits: [Credit]?; let job_identifier: String?; let duplicate_override_reason: String? }
        struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: Payload }
        struct Result: Decodable { let id: UUID }
        do {
            var credits: [Credit]?
            if split {
                guard setter != closer, setterPercent.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil, let percent = Decimal(string: setterPercent), percent >= 0, percent <= 100 else { throw NSError(domain:"Sale",code:1,userInfo:[NSLocalizedDescriptionKey:"Choose different setter and closer reps and a valid credit percentage."]) }
                let bp = NSDecimalNumber(decimal: percent*100).intValue
                credits = [Credit(user_id:setter,role:"setter",basis_points:bp),Credit(user_id:closer,role:"closer",basis_points:10000-bp)]
            }
            let payload = Payload(request_id:request,contact_id:selected.id,opportunity_id:selected.opportunity_id,appointment_id:appointment,value_minor:try FieldSalesService.minorUnits(amount,currency:data.currency ?? "CAD"),product:product,sold_on:format.string(from:soldOn),expected_completion_on:hasCompletion ? format.string(from:completion) : nil,notes:notes,rep_id:rep,setter_id:setter,closer_id:closer,credits:credits,job_identifier:duplicate ? job : nil,duplicate_override_reason:duplicate ? reason : nil)
            let result: Result = try await SupabaseManager.shared.client.rpc("field_sales_command", params:Params(p_workspace:workspace,p_action:"submit",p_data:payload)).execute().value
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(name:.fieldSalesChanged,object:nil); saved(result.id)
        } catch { self.error = error.localizedDescription }
    }
}
