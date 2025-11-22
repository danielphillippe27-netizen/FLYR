import SwiftUI

struct ContactDetailSheet: View {
    @Binding var contact: Contact
    @State private var activities: [ContactActivity] = []
    @State private var isLoadingActivities = false
    @State private var editedNotes: String = ""
    @State private var showLogActivity = false
    @State private var newActivityType: ActivityType = .note
    @State private var newActivityNote: String = ""
    
    let onUpdate: (Contact) async -> Void
    let onLogActivity: (UUID, ActivityType, String?) async -> Void
    let onCall: () -> Void
    let onText: () -> Void
    let onViewMap: () -> Void
    
    private let contactsService = ContactsService.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header: Avatar + Name + Tags
                headerSection
                
                Divider()
                    .background(Color.border)
                
                // Recent Activity
                activitySection
                
                Divider()
                    .background(Color.border)
                
                // Notes
                notesSection
                
                Divider()
                    .background(Color.border)
                
                // Reminders
                remindersSection
                
                Divider()
                    .background(Color.border)
                
                // Action Buttons
                actionButtonsSection
            }
        }
        .task {
            await loadActivities()
        }
        .sheet(isPresented: $showLogActivity) {
            logActivitySheet
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                // Avatar placeholder
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(contact.fullName.prefix(1).uppercased())
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.text)
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(contact.fullName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.text)
                    
                    // Tags
                    HStack(spacing: 8) {
                        if contact.campaignId != nil {
                            TagView(text: "Campaign", color: .error)
                        }
                        if contact.farmId != nil {
                            TagView(text: "Farm", color: .success)
                        }
                        StatusBadge(status: contact.status)
                    }
                }
            }
            
            // Address (tappable)
            Button(action: onViewMap) {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accent)
                    Text(contact.address)
                        .font(.system(size: 15))
                        .foregroundColor(.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Activity Section
    
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.text)
            
            if isLoadingActivities {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if activities.isEmpty {
                Text("No activity yet")
                    .font(.system(size: 14))
                    .foregroundColor(.muted)
                    .padding(.vertical, 8)
            } else {
                ForEach(activities.prefix(10)) { activity in
                    ActivityRow(activity: activity)
                }
            }
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.text)
            
            TextEditor(text: $editedNotes)
                .font(.system(size: 15))
                .foregroundColor(.text)
                .frame(minHeight: 100)
                .padding(12)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
                .onAppear {
                    editedNotes = contact.notes ?? ""
                }
                .onChange(of: editedNotes) { newValue in
                    Task {
                        var updatedContact = contact
                        updatedContact.notes = newValue.isEmpty ? nil : newValue
                        await onUpdate(updatedContact)
                    }
                }
        }
    }
    
    // MARK: - Reminders Section
    
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reminders")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.text)
            
            if let reminderDate = contact.reminderDate {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.warning)
                    Text("Follow-up: \(reminderDate, style: .date)")
                        .font(.system(size: 14))
                        .foregroundColor(.text)
                    Spacer()
                    Button("Clear") {
                        Task {
                            var updatedContact = contact
                            updatedContact.reminderDate = nil
                            await onUpdate(updatedContact)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accent)
                }
                .padding(12)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            } else {
                Button(action: {
                    // Set reminder for 3 days from now
                    Task {
                        var updatedContact = contact
                        updatedContact.reminderDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())
                        await onUpdate(updatedContact)
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accent)
                        Text("Add Follow-Up Date")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.accent)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ActionButton(
                    icon: "phone.fill",
                    label: "Call",
                    color: .success,
                    action: onCall
                )
                
                ActionButton(
                    icon: "message.fill",
                    label: "Text",
                    color: .info,
                    action: onText
                )
            }
            
            HStack(spacing: 12) {
                ActionButton(
                    icon: "map.fill",
                    label: "Map",
                    color: .warning,
                    action: onViewMap
                )
                
                ActionButton(
                    icon: "plus.circle.fill",
                    label: "Log Activity",
                    color: .accent,
                    action: { showLogActivity = true }
                )
            }
        }
    }
    
    // MARK: - Log Activity Sheet
    
    private var logActivitySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Activity Type Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity Type")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.text)
                    
                    Picker("Type", selection: $newActivityType) {
                        ForEach(ActivityType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                // Note Field
                VStack(alignment: .leading, spacing: 12) {
                    Text("Note (Optional)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.text)
                    
                    TextEditor(text: $newActivityNote)
                        .font(.system(size: 15))
                        .foregroundColor(.text)
                        .frame(minHeight: 100)
                        .padding(12)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                }
                
                Spacer()
                
                // Save Button
                Button(action: {
                    Task {
                        await onLogActivity(contact.id, newActivityType, newActivityNote.isEmpty ? nil : newActivityNote)
                        newActivityNote = ""
                        showLogActivity = false
                        await loadActivities()
                    }
                }) {
                    Text("Log Activity")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accent)
                        .cornerRadius(12)
                }
            }
            .padding(20)
            .navigationTitle("Log Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showLogActivity = false
                        newActivityNote = ""
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadActivities() async {
        isLoadingActivities = true
        defer { isLoadingActivities = false }
        
        do {
            activities = try await contactsService.fetchActivities(contactID: contact.id)
        } catch {
            print("❌ Error loading activities: \(error)")
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: ContactActivity
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.type.icon)
                .font(.system(size: 16))
                .foregroundColor(.accent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.displayText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.text)
                
                Text(activity.timeAgoDisplay)
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ContactDetailSheet(
        contact: .constant(Contact.mockContacts[0]),
        onUpdate: { _ in },
        onLogActivity: { _, _, _ in },
        onCall: {},
        onText: {},
        onViewMap: {}
    )
    .padding()
    .background(Color.bgSecondary)
}





