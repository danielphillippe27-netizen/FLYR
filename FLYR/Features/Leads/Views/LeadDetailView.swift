import SwiftUI
struct LeadDetailView: View {
    let lead: FieldLead
    var onConnectCRM: () -> Void
    var onDismiss: (() -> Void)?
    /// Called after successfully saving edits so the parent can refresh (e.g. update list and selectedLead).
    var onLeadUpdated: ((FieldLead) -> Void)?
    
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @State private var showPaywall = false
    @State private var integrations: [UserIntegration] = []
    @State private var showSyncSettings = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var isPushingToCRM = false
    @State private var pushToCRMSuccess: Bool? = nil
    
    // Editable fields wired to lead data
    @State private var editableName: String = ""
    @State private var editablePhone: String = ""
    @State private var editableEmail: String = ""
    @State private var editableNotes: String = ""
    @State private var isSaving = false
    private var hasEdits: Bool { editableName != (lead.name ?? "") || editablePhone != (lead.phone ?? "") || editableEmail != (lead.email ?? "") || editableNotes != (lead.notes ?? "") }
    
    // Appointment / task for CRM push (UI-only, not persisted on lead)
    @State private var appointmentDate: Date = Date()
    @State private var appointmentTitle: String = ""
    @State private var appointmentNotes: String = ""
    @State private var taskTitle: String = ""
    @State private var taskDueDate: Date = Date()
    
    init(lead: FieldLead, onConnectCRM: @escaping () -> Void, onDismiss: (() -> Void)? = nil, onLeadUpdated: ((FieldLead) -> Void)? = nil) {
        self.lead = lead
        self.onConnectCRM = onConnectCRM
        self.onDismiss = onDismiss
        self.onLeadUpdated = onLeadUpdated
    }
    
    private var connectedProvider: IntegrationProvider? {
        integrations.first { $0.isConnected }?.provider
    }
    
    private var lastSyncedText: String? {
        guard let at = lead.lastSyncedAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: at, relativeTo: Date())
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                appleStyleHeaderSection
                contactRowsSection
                addressSection
                appointmentsTasksSection
                fieldNotesMetadataSection
                if lead.qrCode != nil { qrSection }
                syncSection
                actionsSection
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.gray.opacity(0.15), Color.clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if hasEdits {
                    Button("Save") {
                        saveEdits()
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.accent)
                    .disabled(isSaving)
                }
            }
        }
        .task { await loadIntegrations() }
        .onAppear {
            editableName = lead.name ?? ""
            editablePhone = lead.phone ?? ""
            editableEmail = lead.email ?? ""
            editableNotes = lead.notes ?? ""
        }
        .sheet(isPresented: $showSyncSettings) {
            SyncSettingsView()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: shareItems)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    /// Appointments & Tasks: show full sections if Pro, else locked CTA that opens Paywall.
    @ViewBuilder
    private var appointmentsTasksSection: some View {
        if entitlementsService.canUsePro {
            appointmentSection
            taskSection
        } else {
            appointmentsTasksProGate
        }
    }
    
    private var appointmentsTasksProGate: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Appointments & Tasks")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.text)
                    Text("Pro feature — set appointments and tasks for CRM sync.")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                }
                Spacer(minLength: 0)
            }
            Button {
                showPaywall = true
            } label: {
                Label("Unlock with Pro", systemImage: "crown.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
    
    private var displayTitle: String {
        let name = (editableName.isEmpty ? lead.name : editableName) ?? ""
        if !name.isEmpty { return name }
        return lead.address
    }
    
    // MARK: - Apple-style header (name + circular action buttons, no avatar)
    private var appleStyleHeaderSection: some View {
        VStack(spacing: 36) {
            // Name (editable) — prominent, higher and larger like Apple Contacts
            TextField("Name", text: $editableName)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.text)
                .multilineTextAlignment(.center)
                .autocapitalization(.words)
            // Circular action buttons: Message, Phone, Email, Address
            HStack(spacing: 24) {
                circularActionButton(icon: "message.fill", isEnabled: phoneDigits(from: editablePhone) != nil) {
                    openSMS()
                }
                circularActionButton(icon: "phone.fill", isEnabled: phoneDigits(from: editablePhone) != nil) {
                    openPhone()
                }
                circularActionButton(icon: "envelope.fill", isEnabled: !(editableEmail.isEmpty && (lead.email ?? "").isEmpty)) {
                    openEmail()
                }
                circularActionButton(icon: "mappin.circle.fill", isEnabled: !lead.address.isEmpty) {
                    openMaps()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private func phoneDigits(from raw: String) -> String? {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        let digitsOnly = digits.filter { $0.isNumber }
        if digitsOnly.isEmpty { return nil }
        return (digits.hasPrefix("+") ? "+" : "") + digitsOnly
    }
    
    private func circularActionButton(icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(isEnabled ? .black : .gray)
                .frame(width: 50, height: 50)
                .background(isEnabled ? Color.accent : Color.gray.opacity(0.3))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
    
    private func openPhone() {
        guard let digits = phoneDigits(from: editablePhone.isEmpty ? (lead.phone ?? "") : editablePhone),
              let url = URL(string: "tel:\(digits)") else { return }
        UIApplication.shared.open(url)
    }
    
    private func openSMS() {
        guard let digits = phoneDigits(from: editablePhone.isEmpty ? (lead.phone ?? "") : editablePhone),
              let url = URL(string: "sms:\(digits)") else { return }
        UIApplication.shared.open(url)
    }
    
    private func openEmail() {
        let email = editableEmail.isEmpty ? (lead.email ?? "") : editableEmail
        guard !email.isEmpty, let url = URL(string: "mailto:\(email)") else { return }
        UIApplication.shared.open(url)
    }
    
    private func openMaps() {
        let encoded = lead.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        UIApplication.shared.open(url)
    }
    
    // MARK: - Appointment (for CRM push)
    private var appointmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Appointment (for CRM)", systemImage: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            DatePicker("Date & time", selection: $appointmentDate, in: Date()...)
                .datePickerStyle(.compact)
                .foregroundColor(.text)
            TextField("Title (optional)", text: $appointmentTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.text)
            TextField("Notes (optional)", text: $appointmentNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.text)
                .lineLimit(3...6)
        }
        .padding(16)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
    
    // MARK: - Task (for CRM push)
    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Task (for CRM)", systemImage: "checkmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            TextField("Task title", text: $taskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.text)
            DatePicker("Due date", selection: $taskDueDate, in: Date()...)
                .datePickerStyle(.compact)
                .foregroundColor(.text)
        }
        .padding(16)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(12)
    }
    
    // MARK: - Phone, Email, Notes rows
    private var contactRowsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            contactRow(icon: "phone.fill", label: "Phone", text: $editablePhone, placeholder: "Phone number", keyboardType: .phonePad)
            Divider().background(Color.border).padding(.vertical, 12)
            contactRow(icon: "envelope.fill", label: "Email", text: $editableEmail, placeholder: "Email", keyboardType: .emailAddress)
            Divider().background(Color.border).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.muted)
                TextEditor(text: $editableNotes)
                    .font(.system(size: 16))
                    .foregroundColor(.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88)
                    .padding(10)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(alignment: .topLeading) {
                        if editableNotes.isEmpty {
                            Text("Add notes…")
                                .font(.system(size: 16))
                                .foregroundColor(.muted)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
    
    private func contactRow(icon: String, label: String, text: Binding<String>, placeholder: String, keyboardType: UIKeyboardType = .default) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.muted)
                .frame(width: 24, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.muted)
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(.text)
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .sentences)
            }
        }
    }
    
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Label("Address", systemImage: "mappin.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.muted)
                Text(lead.address)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.text)
                    .lineLimit(2)
            }
            Button("Open in Maps") {
                let encoded = lead.address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "http://maps.apple.com/?q=\(encoded)") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.accent)
        }
    }
    
    private var fieldNotesMetadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Status:")
                    .foregroundColor(.muted)
                Text(lead.status.displayName)
                    .foregroundColor(.text)
            }
            .font(.system(size: 15))
            Text("Last: \(lead.createdAt, style: .date) at \(lead.createdAt, style: .time)")
                .font(.system(size: 14))
                .foregroundColor(.muted)
            if let sessionId = lead.sessionId {
                Text("Captured during Session")
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
            }
        }
    }
    
    private var qrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("QR Scan", systemImage: "qrcode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
            Text(lead.qrCode ?? "")
                .font(.system(size: 15))
                .foregroundColor(.text)
        }
    }
    
    private var syncSection: some View {
        Group {
            if let provider = connectedProvider {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Synced to \(provider.displayName)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.text)
                    }
                    if let t = lastSyncedText {
                        Text("Last sync: \(t)")
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                    }
                    Button("View in \(provider.displayName) →") {
                        // Phase 1: no deep link
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.12))
                .cornerRadius(12)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pro Tip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.text)
                    Text("Connect FUB to auto-sync this lead to your office.")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)
                    Button("Connect CRM →") {
                        showSyncSettings = true
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private var actionsSection: some View {
        HStack(spacing: 12) {
            Button(action: shareLead) {
                Label("Share Lead", systemImage: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            Button(action: pushToCRM) {
                Group {
                    if isPushingToCRM {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else if pushToCRMSuccess == true {
                        Label("Pushed", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Push to CRM", systemImage: "arrow.up.circle")
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(isPushingToCRM)
        }
    }
    
    private func saveEdits() {
        guard hasEdits else { return }
        isSaving = true
        var updated = lead
        updated.name = editableName.isEmpty ? nil : editableName
        updated.phone = editablePhone.isEmpty ? nil : editablePhone
        updated.email = editableEmail.isEmpty ? nil : editableEmail
        updated.notes = editableNotes.isEmpty ? nil : editableNotes
        updated.updatedAt = Date()
        Task {
            do {
                let saved = try await FieldLeadsService.shared.updateLead(updated)
                await MainActor.run {
                    isSaving = false
                    editableName = saved.name ?? ""
                    editablePhone = saved.phone ?? ""
                    editableEmail = saved.email ?? ""
                    editableNotes = saved.notes ?? ""
                    onLeadUpdated?(saved)
                }
            } catch {
                await MainActor.run { isSaving = false }
            }
        }
    }
    
    private func loadIntegrations() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        do {
            integrations = try await CRMIntegrationManager.shared.fetchIntegrations(userId: userId)
        } catch {}
    }
    
    private func shareLead() {
        var leadForShare = lead
        leadForShare.name = editableName.isEmpty ? lead.name : editableName
        leadForShare.phone = editablePhone.isEmpty ? lead.phone : editablePhone
        leadForShare.email = editableEmail.isEmpty ? lead.email : editableEmail
        leadForShare.notes = editableNotes.isEmpty ? lead.notes : editableNotes
        shareItems = [LeadsExportManager.shareableText(for: leadForShare)]
        showShareSheet = true
    }
    
    private func pushToCRM() {
        isPushingToCRM = true
        pushToCRMSuccess = nil
        var currentLead = lead
        currentLead.name = editableName.isEmpty ? lead.name : editableName
        currentLead.phone = editablePhone.isEmpty ? lead.phone : editablePhone
        currentLead.email = editableEmail.isEmpty ? lead.email : editableEmail
        currentLead.notes = editableNotes.isEmpty ? lead.notes : editableNotes
        let leadModel = LeadModel(from: currentLead)
        let appointment: LeadSyncAppointment? = (appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && appointmentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? nil : LeadSyncAppointment(date: appointmentDate, title: appointmentTitle.isEmpty ? nil : appointmentTitle, notes: appointmentNotes.isEmpty ? nil : appointmentNotes)
        let task: LeadSyncTask? = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : LeadSyncTask(title: taskTitle, dueDate: taskDueDate)
        Task {
            await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: lead.userId, appointment: appointment, task: task)
            await MainActor.run {
                isPushingToCRM = false
                pushToCRMSuccess = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run { pushToCRMSuccess = nil }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LeadDetailView(
            lead: FieldLead(
                userId: UUID(),
                address: "147 Bastedo Ave, Toronto, ON",
                name: "Ryan Secrest",
                phone: "+1 416 555 1234",
                email: "ryan@example.com",
                status: .notHome,
                notes: "Met wife, call back at 6pm. Left flyer on door.",
                sessionId: UUID()
            ),
            onConnectCRM: {}
        )
    }
}
