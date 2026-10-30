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
        if sessionManager.sessionId != nil || sessionManager.isActive {
            return sessionManager.campaignId ?? uiState.selectedMapCampaignId
        }
        return uiState.selectedMapCampaignId
    }

    private var inSessionMode: Bool {
        sessionManager.sessionId != nil || sessionManager.isActive
    }

    private var showingCampaignMap: Bool {
        recordTabMapCampaignId != nil
    }

    var body: some View {
        Group {
            if uiState.hasFullscreenMap {
                Color.bg
            } else if sessionManager.isNetworkingSession {
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
        .toolbar((inSessionMode || showingCampaignMap) ? .hidden : .visible, for: .navigationBar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(inSessionMode && !sessionManager.isNetworkingSession ? .all : [])
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
                    sessionManager.stop()
                } label: {
                    Text(sessionManager.isEndingSession ? "Ending..." : "End Session")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(sessionManager.isEndingSession)
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
        case firstName
        case lastName
        case socialHandle
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

    @State private var leadFirstName = ""
    @State private var leadLastName = ""
    @State private var leadSocialHandle = ""
    @State private var savedLead: FieldLead?
    @State private var leadDraftID = UUID()
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
                    conversationCard
                    leadForm
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActions
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.bg)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(formattedElapsedTime)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.text)
                Text(sessionManager.isActive ? "Live now" : (isStarting ? "Starting..." : "Ready"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.accentDefault)
            }
            .accessibilityElement(children: .combine)

            Text("Networking")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)

            endSessionButton
        }
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
                .accessibilityLabel("Decrease conversations")

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
                .accessibilityLabel("Increase conversations")
            }
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

            HStack(spacing: 12) {
                networkingField("First name", text: $leadFirstName, field: .firstName, keyboard: .default, capitalization: .words, submitLabel: .next)
                networkingField("Last name", text: $leadLastName, field: .lastName, keyboard: .default, capitalization: .words, submitLabel: .next)
            }
            networkingField("Phone", text: $leadPhone, field: .phone, keyboard: .phonePad, capitalization: .never, disableAutocorrection: true, submitLabel: .next)
            networkingField("Email", text: $leadEmail, field: .email, keyboard: .emailAddress, capitalization: .never, disableAutocorrection: true, submitLabel: .next)

            HStack(spacing: 6) {
                Text("@")
                    .foregroundColor(.muted)
                TextField("Social media handle", text: $leadSocialHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .socialHandle)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .notes }
                    .accessibilityLabel("Social media handle")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundColor(.text)

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
        }
        .disabled(isSavingLead)
    }

    private var bottomActions: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                focusedField = nil
                Task {
                    do {
                        _ = try await saveLead(resetAfterSave: true)
                    } catch {
                        saveErrorMessage = error.localizedDescription
                    }
                }
            } label: {
                Group {
                    if isSavingLead {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundColor(.white)
                .background(canSaveLead ? Color.info : Color.gray.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!canSaveLead || isSavingLead)
            .frame(maxWidth: .infinity)

            BusinessCardSendView(
                phone: leadPhone,
                email: leadEmail,
                saveLead: {
                    focusedField = nil
                    return try await saveLead(resetAfterSave: false)
                },
                networkingFirstName: leadFirstName,
                compact: true
            )
            .id(leadDraftID)
            .frame(maxWidth: .infinity)
            .disabled(isSavingLead)
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
                case .firstName:
                    focusedField = .lastName
                case .lastName:
                    focusedField = .phone
                case .phone:
                    focusedField = .email
                case .email:
                    focusedField = .socialHandle
                case .socialHandle:
                    focusedField = .notes
                case .notes:
                    focusedField = nil
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
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
        [leadFirstName, leadLastName, leadPhone, leadEmail, normalizedSocialHandle, leadNotes].contains {
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

    @MainActor
    private func saveLead(resetAfterSave: Bool) async throws -> UUID {
        guard !isSavingLead, canSaveLead else { throw BusinessCardAPI.failure("Enter this contact’s details first.") }
        guard let userId = AuthManager.shared.user?.id else { throw BusinessCardAPI.failure("Sign in to save this contact.") }
        isSavingLead = true
        saveErrorMessage = nil
        defer { isSavingLead = false }

        let trimmedName = [leadFirstName, leadLastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmedPhone = leadPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = leadEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = leadNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        let lead = FieldLead(
            id: savedLead?.id ?? leadDraftID,
            userId: userId,
            address: networkingLeadAddress,
            name: trimmedName.isEmpty ? nil : trimmedName,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            status: .interested,
            notes: combinedLeadNotes(baseNotes: trimmedNotes),
            qrCode: nil,
            campaignId: nil,
            sessionId: sessionManager.sessionId,
            createdAt: savedLead?.createdAt ?? Date()
        )

        let persistedLead: FieldLead
        if savedLead != nil {
            persistedLead = try await FieldLeadsService.shared.updateLead(lead)
        } else {
            let outcome = try await FieldLeadsService.shared.addLeadDetailed(
                lead,
                workspaceId: WorkspaceContext.shared.workspaceId
            )
            persistedLead = outcome.lead
            if outcome.createdNew {
                sessionManager.recordLeadCreated()
            }
        }
        savedLead = persistedLead
        try? await persistContactMetadata(for: persistedLead)
        NotificationCenter.default.post(name: .leadSavedFromSession, object: nil)
        HapticManager.success()

        if resetAfterSave {
            leadFirstName = ""
            leadLastName = ""
            leadSocialHandle = ""
            leadPhone = ""
            leadEmail = ""
            leadNotes = ""
            pendingFollowUp = nil
            pendingAppointment = nil
            savedLead = nil
            leadDraftID = UUID()
        }
        return persistedLead.id
    }

    private var normalizedSocialHandle: String {
        leadSocialHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop(while: { $0 == "@" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var networkingLeadAddress: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Networking Session • \(formatter.string(from: sessionManager.startTime ?? Date()))"
    }

    private func combinedLeadNotes(baseNotes: String) -> String? {
        var parts: [String] = []
        if !normalizedSocialHandle.isEmpty {
            parts.append("Social: @\(normalizedSocialHandle)")
        }
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
            _ = try? await ContactsService.shared.logActivity(
                contactID: updated.id,
                type: .meeting,
                note: appointmentNote,
                timestamp: pendingAppointment.start
            )
        }

        if let pendingFollowUp {
            let followUpNote = "\(pendingFollowUp.kind.label) follow-up on \(pendingFollowUp.date.formatted(date: .abbreviated, time: .shortened))\(pendingFollowUp.notes.isEmpty ? "" : "\n\(pendingFollowUp.notes)")"
            _ = try? await ContactsService.shared.logActivity(contactID: updated.id, type: .note, note: followUpNote)
        }

        try? await syncLinkedCalendarEvents(for: updated)
    }

    private func syncLinkedCalendarEvents(for contact: Contact) async throws {
        if let pendingAppointment {
            let eventType = FlyrCalendarEventType.appointment
            let sourceKind = CalendarEventSourceKind.contactAppointment.rawValue
            let event = FlyrCalendarEvent(
                id: FlyrCalendarEvent.linkedId(sourceKind: sourceKind, sourceId: contact.id, eventType: eventType),
                title: pendingAppointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? eventType.defaultTitle(contactName: contact.fullName)
                    : pendingAppointment.title,
                startAt: pendingAppointment.start,
                endAt: pendingAppointment.end,
                eventType: eventType.rawValue,
                contactId: contact.id,
                contactName: contact.fullName,
                contactAddress: contact.address,
                sourceKind: sourceKind,
                sourceId: contact.id,
                notes: pendingAppointment.notes.isEmpty ? contact.notes : pendingAppointment.notes,
                location: contact.address,
                colorKey: eventType.defaultColorKey
            )
            _ = try await FlyrCalendarService.shared.createEvent(event)
        }

        if let pendingFollowUp {
            let eventType = FlyrCalendarEventType.followUp
            let sourceKind = CalendarEventSourceKind.contactFollowUp.rawValue
            let event = FlyrCalendarEvent(
                id: FlyrCalendarEvent.linkedId(sourceKind: sourceKind, sourceId: contact.id, eventType: eventType),
                title: eventType.defaultTitle(contactName: contact.fullName),
                startAt: pendingFollowUp.date,
                endAt: Calendar.current.date(byAdding: .minute, value: 30, to: pendingFollowUp.date) ?? pendingFollowUp.date,
                eventType: eventType.rawValue,
                contactId: contact.id,
                contactName: contact.fullName,
                contactAddress: contact.address,
                sourceKind: sourceKind,
                sourceId: contact.id,
                notes: pendingFollowUp.notes.isEmpty ? contact.notes : pendingFollowUp.notes,
                location: contact.address,
                colorKey: eventType.defaultColorKey
            )
            _ = try await FlyrCalendarService.shared.createEvent(event)
        }
    }
}
