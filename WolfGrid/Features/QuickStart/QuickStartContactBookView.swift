import SwiftUI

private enum StandardModeContactBookTab: String, CaseIterable {
    case all = "All"
    case leads = "Leads"
    case notes = "Notes"
    case followUp = "Follow Up"
    case appointments = "Appointments"
}

struct QuickStartContactBookView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContactsViewModel()
    @State private var selectedTab: StandardModeContactBookTab = .all
    @State private var selectedContact: Contact?
    @State private var activities: [ContactActivity] = []
    @State private var isLoadingActivities = false

    private let contactsService = ContactsService.shared

    private var standardModeContacts: [Contact] {
        viewModel.filteredContacts.filter(isStandardModeContact)
    }

    private var activitiesByContact: [UUID: [ContactActivity]] {
        Dictionary(grouping: activities, by: \.contactId)
    }

    private var visibleContacts: [Contact] {
        switch selectedTab {
        case .all:
            return standardModeContacts
        case .leads:
            return standardModeContacts.filter(isLead)
        case .notes:
            return standardModeContacts.filter(hasNotes)
        case .followUp:
            return standardModeContacts.filter(hasFollowUp)
        case .appointments:
            return standardModeContacts.filter(hasAppointment)
        }
    }

    private var emptyTitle: String {
        switch selectedTab {
        case .all: return "No Standard Mode clients"
        case .leads: return "No Standard Mode leads"
        case .notes: return "No Standard Mode notes"
        case .followUp: return "No Standard Mode follow-ups"
        case .appointments: return "No Standard Mode appointments"
        }
    }

    private var emptyDescription: String {
        switch selectedTab {
        case .all: return "Clients saved from Standard Mode homes will appear here."
        case .leads: return "Leads saved from Standard Mode homes will appear here."
        case .notes: return "Notes saved from Standard Mode homes will appear here."
        case .followUp: return "Follow-ups scheduled from Standard Mode homes will appear here."
        case .appointments: return "Appointments booked from Standard Mode homes will appear here."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                tabs
                content
            }
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationTitle("Contact Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close contact book")
                }
            }
            .task {
                await loadContent()
            }
            .refreshable {
                await loadContent()
            }
            .sheet(item: $selectedContact, onDismiss: {
                Task { await loadContent() }
            }) { contact in
                editableContactSheet(contact)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.secondary)
            TextField("Search by name or address", text: $viewModel.searchText)
                .font(.system(size: 17))
                .textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                ForEach(StandardModeContactBookTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.rawValue)
                                .font(.system(size: 17, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            Rectangle()
                                .fill(selectedTab == tab ? Color.accent : Color.clear)
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading || isLoadingActivities {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleContacts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(emptyTitle)
                    .font(.system(size: 18, weight: .semibold))
                Text(emptyDescription)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(visibleContacts) { contact in
                    Button {
                        selectedContact = contact
                    } label: {
                        QuickStartContactRow(
                            contact: contact,
                            tab: selectedTab,
                            activities: activitiesByContact[contact.id] ?? []
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadContent() async {
        await viewModel.loadContacts()
        let contactIDs = viewModel.contacts
            .filter(isStandardModeContact)
            .map(\.id)

        guard !contactIDs.isEmpty else {
            activities = []
            return
        }

        isLoadingActivities = true
        defer { isLoadingActivities = false }
        do {
            activities = try await contactsService.fetchActivities(
                contactIDs: contactIDs,
                limit: max(500, contactIDs.count * 10)
            )
        } catch {
            activities = []
            print("❌ Error loading Standard Mode contact activities: \(error)")
        }
    }

    private func isStandardModeContact(_ contact: Contact) -> Bool {
        let tags = contactTags(contact)
        if tags.contains("standard_mode") || tags.contains("quick_start") {
            return true
        }

        // Legacy Standard Mode contacts were saved without a campaign or tags.
        // Do not pull newer tagged networking/imported records into this book.
        return tags.isEmpty
            && contact.campaignId == nil
            && contact.farmId == nil
            && contact.leadKind?.lowercased() != "scraped"
    }

    private func isLead(_ contact: Contact) -> Bool {
        let tags = contactTags(contact)
        if tags.contains("lead") { return true }
        if !tags.intersection(["note", "follow_up", "appointment"]).isEmpty {
            return false
        }
        // Before Standard Mode category tags existed, every saved client was a lead.
        return true
    }

    private func hasNotes(_ contact: Contact) -> Bool {
        if contactTags(contact).contains("note") || nonEmpty(contact.notes) != nil {
            return true
        }
        return activitiesByContact[contact.id]?.contains(where: {
            $0.type == .note && !isFollowUpActivity($0)
        }) == true
    }

    private func hasFollowUp(_ contact: Contact) -> Bool {
        if contactTags(contact).contains("follow_up")
            || contact.followUpAt != nil
            || contact.reminderDate != nil {
            return true
        }
        return activitiesByContact[contact.id]?.contains(where: isFollowUpActivity) == true
    }

    private func hasAppointment(_ contact: Contact) -> Bool {
        if contactTags(contact).contains("appointment") || contact.appointmentAt != nil {
            return true
        }
        return activitiesByContact[contact.id]?.contains(where: { $0.type == .meeting }) == true
    }

    private func isFollowUpActivity(_ activity: ContactActivity) -> Bool {
        guard activity.type == .note, let note = nonEmpty(activity.note)?.lowercased() else {
            return false
        }
        return note.contains("follow up")
            || note.contains("follow-up")
            || note.contains("type:") && note.contains("due:")
    }

    private func contactTags(_ contact: Contact) -> Set<String> {
        Set(
            (contact.tags ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func editableContactSheet(_ contact: Contact) -> some View {
        let binding = Binding<Contact>(
            get: {
                viewModel.contacts.first(where: { $0.id == contact.id }) ?? contact
            },
            set: { updated in
                if let index = viewModel.contacts.firstIndex(where: { $0.id == updated.id }) {
                    viewModel.contacts[index] = updated
                }
            }
        )

        return NavigationStack {
            ContactDetailSheet(
                contact: binding,
                onUpdate: { updated in
                    await viewModel.updateContact(updated)
                },
                onLogActivity: { contactId, type, note in
                    await viewModel.logActivity(contactID: contactId, type: type, note: note)
                },
                onCall: {},
                onText: {},
                onViewMap: {}
            )
            .padding(16)
            .navigationTitle("Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        selectedContact = nil
                    }
                }
            }
        }
    }
}

private struct QuickStartContactRow: View {
    let contact: Contact
    let tab: StandardModeContactBookTab
    let activities: [ContactActivity]

    private var sortedActivities: [ContactActivity] {
        activities.sorted { $0.timestamp > $1.timestamp }
    }

    private var latestNote: String? {
        if let notes = nonEmpty(contact.notes) { return notes }
        return sortedActivities
            .first(where: { activity in
                guard activity.type == .note, let note = activity.note?.lowercased() else { return false }
                return !note.contains("follow up") && !note.contains("follow-up") && !note.contains("due:")
            })
            .flatMap { nonEmpty($0.note) }
    }

    private var latestFollowUpNote: String? {
        sortedActivities
            .first(where: { activity in
                guard activity.type == .note, let note = activity.note?.lowercased() else { return false }
                return note.contains("follow up") || note.contains("follow-up") || note.contains("due:")
            })
            .flatMap { nonEmpty($0.note) }
    }

    private var latestMeeting: ContactActivity? {
        sortedActivities.first(where: { $0.type == .meeting })
    }

    private var followUpDate: Date? {
        contact.followUpAt ?? contact.reminderDate
    }

    private var appointmentDate: Date? {
        contact.appointmentAt ?? latestMeeting?.timestamp
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: "house.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(contact.fullName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(contact.address)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                tabDetail
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var tabDetail: some View {
        switch tab {
        case .notes:
            if let latestNote {
                detailText(latestNote)
            }
        case .followUp:
            if let followUpDate {
                detailText("Follow up: \(followUpDate.formatted(date: .abbreviated, time: .shortened))")
            }
            if let latestFollowUpNote {
                detailText(latestFollowUpNote)
            }
        case .appointments:
            if let appointmentDate {
                detailText("Appointment: \(appointmentDate.formatted(date: .abbreviated, time: .shortened))")
            }
            if let note = latestMeeting.flatMap({ nonEmpty($0.note) }) {
                detailText(note)
            }
        case .all, .leads:
            detailText("Last update: \(contact.updatedAt.formatted(date: .long, time: .omitted))")
        }
    }

    private func detailText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 14))
            .foregroundColor(.secondary)
            .lineLimit(2)
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

#Preview {
    QuickStartContactBookView()
}
