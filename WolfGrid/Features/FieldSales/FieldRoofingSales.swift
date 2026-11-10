import SwiftUI
import Supabase

struct FieldRoofingEntry: Decodable {
    struct Booking: Decodable, Identifiable {
        let id: UUID
        let contact_id: UUID
        let contact_name: String
        let start_at: String
        let setter_name: String?
        let assignee_name: String?
    }
    struct Deal: Decodable, Identifiable { let id: UUID; let contact_id: UUID; let label: String? }
    let enabled: Bool
    let can_write: Bool?
    let can_assign_closer: Bool?
    let actor_id: UUID?
    let currency: String?
    let today: String?
    let contact_id: UUID?
    let opportunity_id: UUID?
    let field_appointment_id: UUID?
    let required_fields: [String]?
    let contacts: [FieldAppointmentOptions.Choice]?
    let representatives: [FieldAppointmentOptions.Choice]?
    let appointments: [Booking]?
    let opportunities: [Deal]?

    static func load(_ workspace: UUID, context: [String: String] = [:]) async throws -> Self {
        struct Params: Encodable { let p_workspace: UUID; let p_context: [String: String] }
        return try await SupabaseManager.shared.client.rpc("field_sales_roofing_entry",
            params: Params(p_workspace: workspace, p_context: context)).execute().value
    }
}

struct FieldSalesMarkSoldView: View {
    let workspace: UUID
    var initial: [String: String] = [:]
    let saved: (UUID) -> Void
    @State private var gate: Bool?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if gate == true {
                FieldRoofingSaleView(workspace: workspace, context: initial, saved: saved)
            } else if gate == false {
                LegacyFieldSalesMarkSoldView(workspace: workspace, initial: initial, saved: saved)
            } else {
                ProgressView("Loading sale entry")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            }
        }
        .task {
            let result = try? await FieldRoofingEntry.load(workspace)
            if !Task.isCancelled { gate = result?.enabled == true }
        }
    }
}

struct FieldRoofingSaleButton: View {
    let contactID: UUID
    var appointmentID: UUID?
    @ObservedObject private var workspace = WorkspaceContext.shared
    @ObservedObject private var auth = AuthManager.shared
    @State private var available = false
    @State private var recording = false
    @State private var recordedID: UUID?

    var body: some View {
        Group {
            if available, let space = workspace.workspaceId {
                Button("Record sale") { recording = true }.frame(minHeight: 44)
                    .sheet(isPresented: $recording) {
                        NavigationStack {
                            FieldRoofingSaleView(workspace: space, context: appointmentID.map {
                                ["field_appointment_id": $0.uuidString, "contact_id": contactID.uuidString]
                            } ?? ["contact_id": contactID.uuidString, "sale_source": "door"]) { id in
                                recordedID = id
                                recording = false
                            }
                        }
                    }
                if let recordedID { NavigationLink("Open saved sale") { FieldSalesRecordView(sale: recordedID) } }
            }
        }
        .task(id: "\(workspace.workspaceId?.uuidString ?? ""):\(auth.user?.id.uuidString ?? "")") {
            available = false
            recordedID = nil
            guard let space = workspace.workspaceId, auth.user != nil else { return }
            let result = try? await FieldRoofingEntry.load(space)
            if !Task.isCancelled { available = result?.can_write == true }
        }
    }
}

struct FieldRoofingSaleView: View {
    let workspace: UUID
    let context: [String: String]
    let saved: (UUID) -> Void
    @State private var entry: FieldRoofingEntry?
    @State private var source = "appointment"
    @State private var booking: UUID?
    @State private var contact: UUID?
    @State private var deal: UUID?
    @State private var closer: UUID?
    @State private var amount = ""
    @State private var soldOn = ""
    @State private var details: [String: String] = [:]
    @State private var search = ""
    @State private var busy = false
    @State private var error: String?
    @State private var previous: [String: String] = [:]
    @Environment(\.dismiss) private var dismiss

    private let fields = [("product", "Service"), ("job_identifier", "Job reference"), ("proof_reference", "Proof reference")]
    private var selectedBooking: FieldRoofingEntry.Booking? {
        source == "appointment" ? entry?.appointments?.first(where: { $0.id == booking }) : nil
    }
    private var selectedContact: UUID? { source == "appointment" ? selectedBooking?.contact_id : contact }

    var body: some View {
        Form {
            if let entry, entry.can_write == true {
                if entry.contact_id == nil {
                    Section {
                        TextField("Find a customer", text: $search).onSubmit { Task { await load() } }
                        Button("Search") { Task { await load() } }
                    }
                }
                Section {
                    if entry.field_appointment_id == nil {
                        Picker("Source", selection: $source) {
                            Text("Held appointment").tag("appointment")
                            Text("Sold at the door").tag("door")
                        }
                    }
                    if source == "appointment" {
                        Picker("Held appointment", selection: $booking) {
                            Text("Choose appointment").tag(UUID?.none)
                            ForEach(entry.appointments ?? []) { item in
                                Text(item.contact_name + (FieldAppointments.date(item.start_at).map {
                                    " · " + $0.formatted(date: .abbreviated, time: .shortened)
                                } ?? "")).tag(Optional(item.id))
                            }
                        }
                        if let setter = selectedBooking?.setter_name { LabeledContent("Booked by", value: setter) }
                        if let assignee = selectedBooking?.assignee_name { LabeledContent("Assigned to", value: assignee) }
                    } else {
                        Picker("Contact", selection: $contact) {
                            Text("Choose contact").tag(UUID?.none)
                            ForEach(entry.contacts ?? []) { item in Text(item.name).tag(Optional(item.id)) }
                        }
                    }
                    let matching = entry.opportunities?.filter { $0.contact_id == selectedContact } ?? []
                    if !matching.isEmpty {
                        Picker("Opportunity", selection: $deal) {
                            Text("New opportunity").tag(UUID?.none)
                            ForEach(matching) { item in Text(item.label ?? "Existing opportunity").tag(Optional(item.id)) }
                        }
                    }
                    TextField("Contract amount (\(entry.currency ?? ""))", text: $amount).keyboardType(.decimalPad)
                    ForEach(fields.filter { entry.required_fields?.contains($0.0) == true }, id: \.0) { key, title in
                        detailField(key, title)
                    }
                }
                DisclosureGroup("Additional details") {
                    TextField("Sold date (YYYY-MM-DD)", text: $soldOn)
                    if entry.can_assign_closer == true {
                        Picker("Actual closer", selection: $closer) {
                            Text("Me").tag(UUID?.none)
                            ForEach(entry.representatives?.filter { $0.id != entry.actor_id } ?? []) { rep in
                                Text(rep.name).tag(Optional(rep.id))
                            }
                        }
                    }
                    ForEach(fields.filter { entry.required_fields?.contains($0.0) != true }, id: \.0) { key, title in
                        detailField(key, title)
                    }
                    detailField("notes", "Notes")
                }
                Button(busy ? "Saving…" : "Save sale") { Task { await submit(entry) } }
                    .disabled(busy || selectedContact == nil || amount.isEmpty)
            } else if entry != nil { Text("Sale entry is unavailable for this workspace.") }
            else if error == nil { ProgressView("Loading sale details") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Record sale")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
        .task { await load() }
    }

    private func detailField(_ key: String, _ title: String) -> some View {
        TextField(title, text: Binding(get: { details[key] ?? "" }, set: { details[key] = $0 }))
    }

    private func load() async {
        do {
            let result = try await FieldRoofingEntry.load(workspace, context: context.merging(["search": search]) { _, new in new })
            if entry == nil {
                source = context["sale_source"] == "door" ? "door" : "appointment"
                booking = result.field_appointment_id
                contact = result.contact_id
                deal = result.opportunity_id
                soldOn = result.today ?? ""
            }
            entry = result
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func submit(_ entry: FieldRoofingEntry) async {
        guard let contact = selectedContact, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: [String: String] }
        struct Result: Decodable { let id: UUID }
        do {
            var data = details
            data["contact_id"] = contact.uuidString
            data["field_appointment_id"] = selectedBooking?.id.uuidString
            data["opportunity_id"] = entry.opportunities?.first(where: { $0.id == deal && $0.contact_id == contact })?.id.uuidString
            data["closer_id"] = closer?.uuidString
            data["sale_source"] = source
            data["client_contract_version"] = "2"
            data["value_minor"] = try FieldSalesService.minorUnits(amount, currency: entry.currency ?? "CAD")
            data["sold_on"] = soldOn
            data["request_id"] = previous.filter({ $0.key != "request_id" }) == data
                ? previous["request_id"] : UUID().uuidString
            previous = data
            let result: Result = try await SupabaseManager.shared.client.rpc("field_sales_command",
                params: Params(p_workspace: workspace, p_action: "submit", p_data: data)).execute().value
            NotificationCenter.default.post(name: .fieldSalesChanged, object: nil)
            saved(result.id)
        } catch { self.error = error.localizedDescription }
    }
}
