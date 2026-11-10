import Foundation
import Supabase
import SwiftUI

struct FieldAppointment: Decodable, Identifiable, Sendable {
    let id: UUID
    let contact_id: UUID
    let contact_name: String
    let property_label: String?
    let campaign_id: UUID?
    let appointment_type: String
    let assignee_id: UUID?
    let setter_id: UUID?
    let setter_name: String?
    let assignee_name: String?
    let start_at: String
    let end_at: String
    let status: String
    let notes: String
    let version: Int
    let can_update: Bool
    let can_assign: Bool
    let history: [History]?

    struct History: Decodable, Sendable {
        let action: String
        let occurred_at: String
        let actor_name: String?
        let assignee_name: String?
        let reason: String?
    }

    var scheduledDate: Date? { FieldAppointments.date(start_at) }
    var active: Bool { status == "scheduled" || status == "confirmed" }
    var statusLabel: String {
        status == "legacy_unknown" ? "Outcome unknown" : status.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct FieldAppointmentAlert: Decodable, Identifiable, Sendable {
    let id: UUID
    let appointment_id: UUID
    let kind: String
    let start_at: String
    let contact_name: String
    var title: String {
        switch kind {
        case "assignment": return "Assigned"
        case "reschedule": return "Rescheduled"
        default: return "Coming up"
        }
    }
}

struct FieldAppointmentGate: Codable, Sendable {
    let enabled: Bool
    let can_write: Bool
}

struct FieldAppointmentList: Decodable, Sendable {
    let enabled: Bool
    let can_write: Bool
    let can_assign: Bool
    let appointments: [FieldAppointment]
}

struct FieldAppointmentOptions: Decodable, Sendable {
    struct Choice: Decodable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let address: String?
    }
    let contacts: [Choice]
    let representatives: [Choice]
}

struct FieldAppointmentMutation: Codable, Sendable {
    let user: UUID
    let workspace: UUID
    let action: String
    let data: [String: String]
}

enum FieldAppointments {
    enum Failure: LocalizedError {
        case accountChanged, queueFailed, conflict
        var errorDescription: String? {
            switch self {
            case .accountChanged: return "The account changed. Switch back to sync this appointment."
            case .queueFailed: return "The booking could not be saved on this device."
            case .conflict: return "This appointment changed. Review the latest details and try again."
            }
        }
    }

    private struct ListParameters: Encodable {
        let p_workspace: UUID
        let p_start: String?
        let p_end: String?
        let p_team: Bool
        let p_after_start: String?
        let p_after_id: UUID?
    }
    private struct Result: Decodable { let conflict: Bool? }

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    static func list(_ workspace: UUID, team: Bool = false, start: Date? = nil,
                     end: Date? = nil, after: FieldAppointment? = nil) async throws -> FieldAppointmentList {
        let formatter = ISO8601DateFormatter()
        return try await SupabaseManager.shared.client.rpc("field_appointment_list", params: ListParameters(
            p_workspace: workspace, p_start: start.map(formatter.string(from:)), p_end: end.map(formatter.string(from:)),
            p_team: team, p_after_start: after?.start_at, p_after_id: after?.id
        )).execute().value
    }

    static func options(_ workspace: UUID, search: String = "") async throws -> FieldAppointmentOptions {
        struct Params: Encodable { let p_workspace: UUID; let p_search: String }
        return try await SupabaseManager.shared.client.rpc("field_appointment_options",
            params: Params(p_workspace: workspace, p_search: search)).execute().value
    }

    static func alerts(_ workspace: UUID) async throws -> [FieldAppointmentAlert] {
        struct Params: Encodable { let p_workspace: UUID }
        struct Result: Decodable { let alerts: [FieldAppointmentAlert] }
        let result: Result = try await SupabaseManager.shared.client.rpc("field_appointment_alerts",
            params: Params(p_workspace: workspace)).execute().value
        return result.alerts
    }

    static func detail(_ workspace: UUID, id: UUID) async throws -> FieldAppointment {
        struct Params: Encodable { let p_workspace: UUID; let p_id: UUID }
        return try await SupabaseManager.shared.client.rpc("field_appointment_detail",
            params: Params(p_workspace: workspace, p_id: id)).execute().value
    }

    @MainActor
    static func gate(user: UUID, workspace: UUID) async -> FieldAppointmentGate? {
        let key = "fieldAppointmentsGate.\(user.uuidString).\(workspace.uuidString)"
        if !NetworkMonitor.shared.isOnline {
            return UserDefaults.standard.data(forKey: key).flatMap {
                try? JSONDecoder().decode(FieldAppointmentGate.self, from: $0)
            }
        }
        guard let result = try? await list(workspace, end: Date(timeIntervalSince1970: 0)),
              AuthManager.shared.user?.id == user, WorkspaceContext.shared.workspaceId == workspace else { return nil }
        let gate = FieldAppointmentGate(enabled: result.enabled, can_write: result.can_write)
        UserDefaults.standard.set(try? JSONEncoder().encode(gate), forKey: key)
        return gate
    }

    @MainActor
    static func command(_ mutation: FieldAppointmentMutation) async throws {
        guard AuthManager.shared.user?.id == mutation.user else { throw Failure.accountChanged }
        struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: [String: String] }
        let result: Result = try await SupabaseManager.shared.client.rpc("field_appointment_command", params: Params(
            p_workspace: mutation.workspace, p_action: mutation.action, p_data: mutation.data
        )).execute().value
        if result.conflict == true { throw Failure.conflict }
    }

    @MainActor
    static func book(_ mutation: FieldAppointmentMutation) async throws -> String {
        guard AuthManager.shared.user?.id == mutation.user,
              WorkspaceContext.shared.workspaceId == mutation.workspace else { throw Failure.accountChanged }
        guard let id = mutation.data["id"], let request = mutation.data["request_id"],
              let entry = await OutboxRepository.shared.enqueue(
                entityType: "field_appointment", entityId: id, operation: .bookFieldAppointment,
                payload: mutation, clientMutationId: request
              ) else { throw Failure.queueFailed }
        await OfflineSyncCoordinator.shared.syncPendingChanges()
        return await OutboxRepository.shared.appointmentSyncState(entryID: entry) ?? "pending"
    }
}

extension Notification.Name {
    static let fieldAppointmentsChanged = Notification.Name("fieldAppointmentsChanged")
}

struct FieldAppointmentBookingButton: View {
    var contactID: UUID?
    var contactName: String?
    var campaignID: UUID?
    var addressID: UUID?
    var initialDate: Date?
    var onSaved: (() -> Void)?

    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var gate: FieldAppointmentGate?
    @State private var open = false

    var body: some View {
        Group {
            if gate?.can_write == true, let user = auth.user?.id, let workspaceID = workspace.workspaceId {
                Button { open = true } label: {
                    Label("Book appointment", systemImage: "calendar.badge.plus").frame(minHeight: 44)
                }
                .sheet(isPresented: $open) {
                    FieldAppointmentBooking(user: user, workspace: workspaceID,
                        contactID: contactID, contactName: contactName, campaignID: campaignID,
                        addressID: addressID, initialDate: initialDate, onSaved: onSaved)
                }
            }
        }
        .task(id: "\(auth.user?.id.uuidString ?? ""):\(workspace.workspaceId?.uuidString ?? "")") {
            gate = nil
            guard let user = auth.user?.id, let workspaceID = workspace.workspaceId else { return }
            let next = await FieldAppointments.gate(user: user, workspace: workspaceID)
            if !Task.isCancelled { gate = next }
        }
    }
}

private struct FieldAppointmentBooking: View {
    let user: UUID
    let workspace: UUID
    let contactID: UUID?
    let contactName: String?
    let campaignID: UUID?
    let addressID: UUID?
    let onSaved: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var chosenContact: UUID?
    @State private var newContact = false
    @State private var newName = ""
    @State private var newPhone = ""
    @State private var newContactID = UUID()
    @State private var assignee: UUID?
    @State private var date: Date
    @State private var options: FieldAppointmentOptions?
    @State private var search = ""
    @State private var notes = ""
    @State private var busy = false
    @State private var result: String?
    @State private var error: String?
    @State private var pendingMutation: FieldAppointmentMutation?

    init(user: UUID, workspace: UUID, contactID: UUID?, contactName: String?, campaignID: UUID?,
         addressID: UUID?, initialDate: Date?, onSaved: (() -> Void)?) {
        self.user = user
        self.workspace = workspace
        self.contactID = contactID
        self.contactName = contactName
        self.campaignID = campaignID
        self.addressID = addressID
        self.onSaved = onSaved
        _chosenContact = State(initialValue: contactID)
        _date = State(initialValue: initialDate ?? Date().addingTimeInterval(3600))
    }

    var body: some View {
        NavigationStack {
            Form {
                if addressID != nil && contactID == nil {
                    Toggle("Create a contact", isOn: $newContact)
                }
                if newContact {
                    TextField("Name", text: $newName).textContentType(.name)
                    TextField("Phone (optional)", text: $newPhone).keyboardType(.phonePad)
                } else if let contactName {
                    LabeledContent("Contact", value: contactName)
                } else {
                    TextField("Find a contact", text: $search).onSubmit { Task { await loadOptions() } }
                    Picker("Contact", selection: $chosenContact) {
                        Text("Choose contact").tag(UUID?.none)
                        ForEach(options?.contacts ?? []) { choice in
                            Text([choice.name, choice.address].compactMap { $0 }.joined(separator: " · ")).tag(Optional(choice.id))
                        }
                    }
                }
                DatePicker("Date and time", selection: $date)
                if (options?.representatives.count ?? 0) > 1 {
                    Picker("Assign closer", selection: $assignee) {
                        Text("Assign to me").tag(UUID?.none)
                        ForEach(options?.representatives.filter { $0.id != user } ?? []) { choice in
                            Text(choice.name).tag(Optional(choice.id))
                        }
                    }
                }
                DisclosureGroup("Additional details") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                if let result { Text(result).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red) }
                if result == nil {
                    Button(busy ? "Saving…" : "Save appointment") { Task { await save() } }
                        .disabled(busy || (newContact ? newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : chosenContact == nil))
                }
            }
            .navigationTitle("Book appointment")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .task { await loadOptions() }
        }
    }

    private func loadOptions() async {
        guard NetworkMonitor.shared.isOnline else { return }
        do { options = try await FieldAppointments.options(workspace, search: search) }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func save() async {
        guard let contact = newContact ? newContactID : chosenContact, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        var fields = [
            "contact_id": contact.uuidString,
            "start_at": ISO8601DateFormatter().string(from: date),
            "timezone": TimeZone.current.identifier,
            "notes": notes
        ]
        if newContact {
            fields["new_contact_name"] = newName
            fields["new_contact_phone"] = newPhone
        }
        fields["assignee_id"] = assignee?.uuidString
        fields["campaign_id"] = campaignID?.uuidString
        fields["campaign_address_id"] = addressID?.uuidString
        if let previous = pendingMutation,
           previous.data.filter({ $0.key != "id" && $0.key != "request_id" }) == fields {
            fields = previous.data
        } else {
            fields["id"] = UUID().uuidString
            fields["request_id"] = UUID().uuidString
        }
        let mutation = FieldAppointmentMutation(user: user, workspace: workspace, action: "book", data: fields)
        pendingMutation = mutation
        do {
            let status = try await FieldAppointments.book(mutation)
            onSaved?()
            if status == "synced" { dismiss() }
            else if status == "pending" || status == "processing" { result = "Pending Sync" }
            else { result = "Sync Failed. Review this booking in My Appointments." }
        } catch { self.error = error.localizedDescription }
    }
}

struct FieldAppointmentsHome: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared

    var body: some View {
        if let user = auth.user?.id, let workspaceID = workspace.workspaceId {
            FieldAppointmentListView(user: user, workspace: workspaceID).id("\(user):\(workspaceID)")
        } else {
            ActivityView(initialFilter: .appointments, filters: [.appointments], navigationTitle: "Appointments")
        }
    }
}

private struct FieldAppointmentListView: View {
    let user: UUID
    let workspace: UUID
    @State private var gate: FieldAppointmentGate?
    @State private var loaded = false
    @State private var list: FieldAppointmentList?
    @State private var queued: [OutboxEntry] = []
    @State private var page: [FieldAppointment] = []
    @State private var alerts: [FieldAppointmentAlert] = []
    @State private var team = false
    @State private var error: String?
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        Group {
            if !loaded {
                ProgressView("Loading appointments")
            } else if gate?.enabled != true && (list?.appointments.isEmpty ?? true) && queued.isEmpty {
                ActivityView(initialFilter: .appointments, filters: [.appointments], navigationTitle: "Appointments")
            } else {
                List {
                    Section {
                        FieldAppointmentBookingButton(onSaved: { Task { await load() } })
                        if list?.can_assign == true {
                            Toggle("View team appointments", isOn: $team)
                        }
                    }
                    if !alerts.isEmpty {
                        Section("Appointment alerts") {
                            ForEach(alerts) { alert in
                                NavigationLink {
                                    FieldAppointmentDetailView(user: user, workspace: workspace,
                                        id: alert.appointment_id, canWrite: gate?.can_write == true)
                                } label: {
                                    Text("\(alert.title) · \(alert.contact_name)")
                                }
                            }
                        }
                    }
                    if !queued.isEmpty {
                        Section("Bookings on this device") {
                            ForEach(queued, id: \.id) { entry in
                                let mutation = entry.decodedPayload(FieldAppointmentMutation.self)
                                VStack(alignment: .leading) {
                                    Text(entry.status == "pending" || entry.status == "processing" ? "Pending Sync" : "Sync Failed")
                                        .font(.headline)
                                    if let time = mutation?.data["start_at"], let date = FieldAppointments.date(time) {
                                        Text(date, format: .dateTime)
                                    }
                                    if let message = entry.errorMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    Section(team ? "Team appointments" : "My appointments") {
                        if let error { Text(error).foregroundStyle(.red) }
                        ForEach(page) { appointment in
                            NavigationLink {
                                FieldAppointmentDetailView(user: user, workspace: workspace, id: appointment.id,
                                    canWrite: gate?.can_write == true)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appointment.contact_name).font(.headline)
                                    Text(appointment.property_label ?? appointment.appointment_type)
                                        .foregroundStyle(.secondary)
                                    if let date = appointment.scheduledDate { Text(date, format: .dateTime).font(.subheadline) }
                                    Text(appointment.statusLabel).font(.caption)
                                }
                            }
                        }
                        if page.isEmpty && error == nil { Text("No appointments found.").foregroundStyle(.secondary) }
                        if let last = page.last, page.count.isMultiple(of: 100) {
                            Button("Load more") { Task { await loadPage(after: last) } }
                        }
                    }
                    NavigationLink("Legacy appointment activity") {
                        ActivityView(initialFilter: .appointments, filters: [.appointments], navigationTitle: "Appointment history")
                    }
                }
                .navigationTitle("Appointments")
                .refreshable { await load() }
                .onChange(of: team) { _, _ in Task { await loadPage() } }
            }
        }
        .task(id: network.isOnline) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .fieldAppointmentsChanged)) { _ in Task { await load() } }
    }

    private func load() async {
        gate = await FieldAppointments.gate(user: user, workspace: workspace)
        queued = await OutboxRepository.shared.unresolvedFieldAppointments(user: user, workspace: workspace)
        if network.isOnline {
            await loadPage()
            if gate?.enabled == true { alerts = (try? await FieldAppointments.alerts(workspace)) ?? [] }
        } else { alerts = [] }
        loaded = true
    }

    private func loadPage(after: FieldAppointment? = nil) async {
        do {
            let result = try await FieldAppointments.list(workspace, team: team, after: after)
            guard !Task.isCancelled else { return }
            list = result
            if after == nil { page = result.appointments }
            else { page.append(contentsOf: result.appointments) }
            error = nil
        } catch {
            if gate?.enabled == true { self.error = error.localizedDescription }
        }
    }
}

struct FieldAppointmentDetailView: View {
    let user: UUID
    let workspace: UUID
    let id: UUID
    let canWrite: Bool
    @State private var item: FieldAppointment?
    @State private var options: FieldAppointmentOptions?
    @State private var action: String?
    @State private var rescheduledDate = Date()
    @State private var assignee: UUID?
    @State private var reason = ""
    @State private var error: String?
    @State private var busy = false
    @State private var lastMutation: FieldAppointmentMutation?

    var body: some View {
        Form {
            if let item {
                Section {
                    LabeledContent("Contact", value: item.contact_name)
                    LabeledContent("Status", value: item.statusLabel)
                    if let setter = item.setter_name { LabeledContent("Booked by", value: setter) }
                    if let assignee = item.assignee_name { LabeledContent("Assigned to", value: assignee) }
                    if let date = item.scheduledDate { LabeledContent("Scheduled") { Text(date, format: .dateTime) } }
                    if let address = item.property_label { LabeledContent("Property", value: address) }
                    if !item.notes.isEmpty { Text(item.notes) }
                }
                if item.status == "held" && item.can_update {
                    FieldRoofingSaleButton(contactID: item.contact_id, appointmentID: item.id)
                }
                if canWrite && item.can_update && item.active {
                    Section("Actions") {
                        if item.status == "scheduled" { Button("Confirm") { Task { await change("confirm") } }.disabled(busy) }
                        if item.scheduledDate.map({ $0 <= Date() }) == true {
                            Button("Mark held") { Task { await change("held") } }.disabled(busy)
                            Button("No show") { Task { await change("no_show") } }.disabled(busy)
                        }
                        Button("Reschedule") { rescheduledDate = item.scheduledDate ?? Date(); action = "reschedule" }
                        Button("Cancel appointment", role: .destructive) { reason = ""; action = "cancel" }
                        if item.can_assign { Button("Reassign") { Task { await loadAssignees(item) } } }
                    }
                    if let action {
                        Section {
                            if action == "reschedule" { DatePicker("New date and time", selection: $rescheduledDate) }
                            else if action == "cancel" { TextField("Cancellation reason", text: $reason) }
                            else {
                                Picker("Representative", selection: $assignee) {
                                    Text("Choose representative").tag(UUID?.none)
                                    ForEach(options?.representatives ?? []) { rep in Text(rep.name).tag(Optional(rep.id)) }
                                }
                            }
                            Button("Save") { Task { await change(action) } }
                                .disabled(busy || (action == "assign" && assignee == nil) ||
                                    (action == "cancel" && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        }
                    }
                }
                if let events = item.history, !events.isEmpty {
                    Section("History") {
                        ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                            LabeledContent(event.action.replacingOccurrences(of: "_", with: " ").capitalized) {
                                if let date = FieldAppointments.date(event.occurred_at) { Text(date, format: .dateTime) }
                            }
                            if let actor = event.actor_name { Text(actor).font(.caption).foregroundStyle(.secondary) }
                            if event.action == "assign", let assignee = event.assignee_name {
                                Text("Assigned to " + assignee).font(.caption)
                            }
                            if let reason = event.reason { Text(reason).font(.caption) }
                        }
                    }
                }
            } else if error == nil { ProgressView("Loading appointment") }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Appointment")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do { item = try await FieldAppointments.detail(workspace, id: id) }
        catch { self.error = error.localizedDescription }
    }

    private func loadAssignees(_ appointment: FieldAppointment) async {
        do {
            options = try await FieldAppointments.options(workspace)
            assignee = appointment.assignee_id
            action = "assign"
        } catch { self.error = error.localizedDescription }
    }

    private func change(_ operation: String) async {
        guard let item, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        var fields = ["id": id.uuidString, "version": String(item.version)]
        if operation == "assign" { fields["assignee_id"] = assignee?.uuidString }
        if operation == "cancel" { fields["reason"] = reason }
        if operation == "reschedule" {
            fields["start_at"] = ISO8601DateFormatter().string(from: rescheduledDate)
            fields["timezone"] = TimeZone.current.identifier
        }
        if let lastMutation, lastMutation.action == operation,
           lastMutation.data.filter({ $0.key != "request_id" }) == fields {
            fields = lastMutation.data
        } else { fields["request_id"] = UUID().uuidString }
        let mutation = FieldAppointmentMutation(user: user, workspace: workspace, action: operation, data: fields)
        lastMutation = mutation
        do {
            try await FieldAppointments.command(mutation)
            action = nil
            NotificationCenter.default.post(name: .fieldAppointmentsChanged, object: nil)
            await load()
        } catch FieldAppointments.Failure.conflict {
            await load()
            self.error = FieldAppointments.Failure.conflict.localizedDescription
        } catch { self.error = error.localizedDescription }
    }
}
