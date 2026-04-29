import SwiftUI

/// Session tab root: Start Session when idle; campaign map when a campaign is selected; path map for other sessions.
struct RecordHomeView: View {
    @EnvironmentObject private var uiState: AppUIState
    @ObservedObject private var sessionManager = SessionManager.shared

    private var activeRouteWorkContext: RouteWorkContext? {
        guard let ctx = uiState.selectedRouteWorkContext,
              let mapId = recordTabMapCampaignId,
              ctx.campaignId == mapId else {
            return nil
        }
        return ctx
    }

    /// One stable campaign id for the map so starting a session does not swap view branches (avoids full map reload).
    private var recordTabMapCampaignId: UUID? {
        sessionManager.campaignId ?? uiState.selectedMapCampaignId
    }

    private var inSessionMode: Bool {
        sessionManager.sessionId != nil || sessionManager.isActive
    }

    var body: some View {
        Group {
            if sessionManager.isNetworkingSession {
                NetworkingSessionView()
            } else if sessionManager.isActive, sessionManager.campaignId == nil {
                legacySessionFallbackView
            } else if let campaignId = recordTabMapCampaignId {
                CampaignMapView(
                    campaignId: campaignId.uuidString,
                    routeWorkContext: activeRouteWorkContext,
                    onDismissFromMap: inSessionMode ? nil : {
                        uiState.clearMapSelection()
                    }
                )
                .id(campaignId.uuidString.lowercased())
            } else {
                SessionStartView(showCancelButton: false)
            }
        }
        .toolbar(inSessionMode ? .hidden : .visible, for: .navigationBar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(inSessionMode ? .all : [])
        // End session summary is presented from MainTabView.fullScreenCover so it always shows on top
    }

    private var legacySessionFallbackView: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Legacy session detected")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.text)
                Text("This session format is no longer supported. End it and start a campaign session to continue.")
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)
                Button {
                    HapticManager.light()
                    SessionManager.shared.stop()
                } label: {
                    Text("End Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    RecordHomeView()
}

private struct PendingNetworkingFollowUp {
    let title: String
    let date: Date
    let kind: LocationCardFollowUpKind
    let notes: String
}

private struct PendingNetworkingAppointment {
    let title: String
    let start: Date
    let end: Date
    let notes: String
}

struct NetworkingSessionView: View {
    private enum LeadField: Hashable {
        case name
        case phone
        case email
        case notes
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var sessionManager = SessionManager.shared
    @FocusState private var focusedField: LeadField?
    @State private var isStarting = false
    @State private var isEndingSession = false
    @State private var startErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var isSavingLead = false

    @State private var leadName = ""
    @State private var leadPhone = ""
    @State private var leadEmail = ""
    @State private var leadNotes = ""

    @State private var pendingFollowUp: PendingNetworkingFollowUp?
    @State private var pendingAppointment: PendingNetworkingAppointment?
    @State private var showFollowUpEditor = false
    @State private var showAppointmentEditor = false
    @State private var shouldDismissAfterSummary = false

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    networkingHeader
                    headerCard
                    conversationCard
                    leadForm
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .task {
            await ensureNetworkingSession()
        }
        .onChange(of: sessionManager.sessionId) { _, newValue in
            if shouldDismissAfterSummary, newValue == nil, !sessionManager.isActive {
                shouldDismissAfterSummary = false
                dismiss()
            }
        }
        .sheet(isPresented: $showFollowUpEditor) {
            FollowUpEditorSheet(
                mode: pendingFollowUp == nil ? .add : .edit,
                initialTitle: pendingFollowUp?.title ?? "",
                initialDate: pendingFollowUp?.date ?? Date().addingTimeInterval(24 * 60 * 60),
                initialKind: pendingFollowUp?.kind ?? .call,
                initialNotes: pendingFollowUp?.notes ?? "",
                onCommit: { title, date, kind, notes in
                    pendingFollowUp = PendingNetworkingFollowUp(title: title, date: date, kind: kind, notes: notes)
                },
                onRemove: pendingFollowUp == nil ? nil : {
                    pendingFollowUp = nil
                }
            )
        }
        .sheet(isPresented: $showAppointmentEditor) {
            AppointmentEditorSheet(
                mode: pendingAppointment == nil ? .add : .edit,
                initialTitle: pendingAppointment?.title ?? "Meeting",
                initialStart: pendingAppointment?.start ?? Date().addingTimeInterval(60 * 60),
                initialEnd: pendingAppointment?.end ?? Date().addingTimeInterval(90 * 60),
                initialNotes: pendingAppointment?.notes ?? "",
                onCommit: { title, start, end, notes in
                    let hadAppointment = pendingAppointment != nil
                    pendingAppointment = PendingNetworkingAppointment(title: title, start: start, end: end, notes: notes)
                    if !hadAppointment {
                        sessionManager.recordAppointment()
                    }
                },
                onRemove: pendingAppointment == nil ? nil : {
                    pendingAppointment = nil
                }
            )
        }
        .alert("Couldn’t start networking session", isPresented: Binding(
            get: { startErrorMessage != nil },
            set: { if !$0 { startErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startErrorMessage ?? "")
        }
        .alert("Couldn’t save lead", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private var networkingHeader: some View {
        ZStack {
            Text("Networking")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.text)
                .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                endSessionButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var endSessionButton: some View {
        Button {
            Task { await endNetworkingSession() }
        } label: {
            Text(isEndingSession ? "Ending..." : "End Session")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isEndingSession)
    }

    private var headerCard: some View {
        VStack(spacing: 4) {
            Text(formattedElapsedTime)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.text)
            Text(sessionManager.isActive ? "Live now" : (isStarting ? "Starting..." : "Ready"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.accentDefault)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversations")
                .font(.flyrSubheadline)
                .foregroundColor(.muted)

            HStack(alignment: .center, spacing: 12) {
                Button {
                    sessionManager.adjustConversationCount(by: -1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.text)
                        .frame(width: 40, height: 40)
                        .background(Color.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Text("\(sessionManager.conversationsHad)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(.text)
                    .frame(maxWidth: .infinity)

                Button {
                    sessionManager.recordConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.info)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Button {
                sessionManager.recordConversation()
            } label: {
                Text("Tap for Conversation")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.info)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next Step")
                .font(.flyrSubheadline)
                .foregroundColor(.muted)

            HStack(spacing: 12) {
                Button {
                    showAppointmentEditor = true
                } label: {
                    actionPill(
                        title: "Appointment",
                        subtitle: pendingAppointment?.start.formatted(date: .abbreviated, time: .shortened) ?? "Add details"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showFollowUpEditor = true
                } label: {
                    actionPill(
                        title: "Follow Up",
                        subtitle: pendingFollowUp?.date.formatted(date: .abbreviated, time: .shortened) ?? "Add reminder"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func actionPill(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.text)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var leadForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lead")
                .font(.flyrHeadline)
                .foregroundColor(.text)

            networkingField("Name", text: $leadName, field: .name, keyboard: .default, capitalization: .words, submitLabel: .next)
            networkingField("Phone", text: $leadPhone, field: .phone, keyboard: .phonePad, capitalization: .never, disableAutocorrection: true, submitLabel: .next)
            networkingField("Email", text: $leadEmail, field: .email, keyboard: .emailAddress, capitalization: .never, disableAutocorrection: true, submitLabel: .next)

            TextField("Notes", text: $leadNotes)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundColor(.text)
                .focused($focusedField, equals: .notes)
                .submitLabel(.done)
                .onSubmit {
                    focusedField = nil
                }

            actionButtons

            if pendingAppointment != nil || pendingFollowUp != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let pendingAppointment {
                        Text("Appointment: \(pendingAppointment.title)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.muted)
                    }
                    if let pendingFollowUp {
                        Text("Follow-up: \(pendingFollowUp.kind.label) on \(pendingFollowUp.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.muted)
                    }
                }
            }

            Button {
                Task { await saveLead() }
            } label: {
                HStack {
                    Spacer()
                    if isSavingLead {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save Lead")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .background(canSaveLead ? Color.info : Color.gray.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canSaveLead || isSavingLead)
        }
    }

    private func networkingField(
        _ title: String,
        text: Binding<String>,
        field: LeadField,
        keyboard: UIKeyboardType,
        capitalization: TextInputAutocapitalization,
        disableAutocorrection: Bool = false,
        submitLabel: SubmitLabel = .done
    ) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(disableAutocorrection)
            .focused($focusedField, equals: field)
            .submitLabel(submitLabel)
            .onSubmit {
                switch field {
                case .name:
                    focusedField = .phone
                case .phone:
                    focusedField = .email
                case .email:
                    focusedField = .notes
                case .notes:
                    focusedField = nil
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.text)
    }

    private var formattedElapsedTime: String {
        let total = Int(sessionManager.elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var canSaveLead: Bool {
        [leadName, leadPhone, leadEmail, leadNotes].contains {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func ensureNetworkingSession() async {
        guard !sessionManager.isNetworkingSession else { return }
        guard sessionManager.sessionId == nil else { return }
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        do {
            try await sessionManager.startNetworkingSession()
        } catch {
            startErrorMessage = error.localizedDescription
        }
    }

    private func endNetworkingSession() async {
        guard !isEndingSession else { return }
        isEndingSession = true
        defer { isEndingSession = false }

        if sessionManager.sessionId != nil {
            shouldDismissAfterSummary = true
            await sessionManager.stopBuildingSession(presentSummary: true)
        } else {
            sessionManager.stop()
            shouldDismissAfterSummary = false
            dismiss()
        }
    }

    private func saveLead() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        isSavingLead = true
        saveErrorMessage = nil
        defer { isSavingLead = false }

        let trimmedName = leadName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = leadPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = leadEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = leadNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let lead = FieldLead(
            userId: userId,
            address: networkingLeadAddress,
            name: trimmedName.isEmpty ? nil : trimmedName,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            status: .interested,
            notes: combinedLeadNotes(baseNotes: trimmedNotes),
            qrCode: nil,
            campaignId: nil,
            sessionId: sessionManager.sessionId
        )

        do {
            let outcome = try await FieldLeadsService.shared.addLeadDetailed(
                lead,
                workspaceId: WorkspaceContext.shared.workspaceId
            )
            if outcome.createdNew {
                await MainActor.run {
                    sessionManager.recordLeadCreated()
                }
            }

            try? await persistContactMetadata(for: outcome.lead)
            NotificationCenter.default.post(name: .leadSavedFromSession, object: nil)

            await MainActor.run {
                HapticManager.success()
                leadName = ""
                leadPhone = ""
                leadEmail = ""
                leadNotes = ""
                pendingFollowUp = nil
                pendingAppointment = nil
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private var networkingLeadAddress: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Networking Session • \(formatter.string(from: sessionManager.startTime ?? Date()))"
    }

    private func combinedLeadNotes(baseNotes: String) -> String? {
        var parts: [String] = []
        if !baseNotes.isEmpty {
            parts.append(baseNotes)
        }
        if let pendingAppointment {
            parts.append("Appointment: \(pendingAppointment.title) on \(pendingAppointment.start.formatted(date: .abbreviated, time: .shortened))")
        }
        if let pendingFollowUp {
            parts.append("Follow-up: \(pendingFollowUp.kind.label) on \(pendingFollowUp.date.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func persistContactMetadata(for lead: FieldLead) async throws {
        var contact = Contact(
            id: lead.id,
            fullName: lead.name?.isEmpty == false ? (lead.name ?? "Lead") : "Lead",
            phone: lead.phone,
            email: lead.email,
            address: lead.address,
            campaignId: lead.campaignId,
            farmId: nil,
            gersId: nil,
            addressId: nil,
            tags: nil,
            status: .warm,
            lastContacted: Date(),
            notes: lead.notes,
            reminderDate: pendingFollowUp?.date,
            createdAt: lead.createdAt,
            updatedAt: Date()
        )

        if let pendingFollowUp {
            contact.reminderDate = pendingFollowUp.date
        }

        let updated = try await ContactsService.shared.updateContact(contact)

        if let pendingAppointment {
            let appointmentNote = "Appointment: \(pendingAppointment.title)\nStarts: \(pendingAppointment.start.formatted(date: .abbreviated, time: .shortened))\nEnds: \(pendingAppointment.end.formatted(date: .abbreviated, time: .shortened))\(pendingAppointment.notes.isEmpty ? "" : "\n\(pendingAppointment.notes)")"
            _ = try? await ContactsService.shared.logActivity(contactID: updated.id, type: .meeting, note: appointmentNote)
        }

        if let pendingFollowUp {
            let followUpNote = "\(pendingFollowUp.kind.label) follow-up on \(pendingFollowUp.date.formatted(date: .abbreviated, time: .shortened))\(pendingFollowUp.notes.isEmpty ? "" : "\n\(pendingFollowUp.notes)")"
            _ = try? await ContactsService.shared.logActivity(contactID: updated.id, type: .note, note: followUpNote)
        }
    }
}
