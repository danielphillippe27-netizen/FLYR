import SwiftUI

struct ContactsHubView: View {
    @StateObject private var viewModel = ContactsViewModel()
    @StateObject private var auth = AuthManager.shared
    @State private var showFilters = false
    @State private var showNewContact = false
    @State private var showDetailSheet = false
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar + Filter Button
                searchBarSection
                
                // Segmented Control
                segmentedControlSection
                
                // Content
                contentSection
            }
            
            // Floating Add Button
            floatingAddButton
        }
        .navigationTitle("CRM")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showFilters) {
            filtersSheet
        }
        .sheet(isPresented: $showNewContact) {
            newContactSheet
        }
        .sheet(isPresented: $showDetailSheet) {
            if let contact = viewModel.selectedContact {
                detailSheet(for: contact)
            }
        }
        .task {
            await viewModel.loadContacts()
        }
        .refreshable {
            await viewModel.loadContacts()
        }
    }
    
    // MARK: - Search Bar Section
    
    private var searchBarSection: some View {
        HStack(spacing: 12) {
            // Search Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.muted)
                    .font(.system(size: 16))
                
                TextField("Search contacts...", text: $viewModel.searchText)
                    .font(.system(size: 15))
                    .foregroundColor(.text)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.15))
            .cornerRadius(10)
            
            // Filter Button
            Button(action: { showFilters = true }) {
                ZStack {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(viewModel.hasActiveFilters ? .accent : .muted)
                    
                    if viewModel.hasActiveFilters {
                        Circle()
                            .fill(Color.error)
                            .frame(width: 8, height: 8)
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Segmented Control
    
    private var segmentedControlSection: some View {
        Picker("Contacts Tab", selection: $viewModel.currentTab) {
            ForEach(ContactsTab.allCases, id: \.self) { tab in
                Text(tab.rawValue)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onChange(of: viewModel.currentTab) { _ in
            // Reload when tab changes
            Task {
                await viewModel.loadContacts()
            }
        }
    }
    
    // MARK: - Content Section
    
    private var contentSection: some View {
        Group {
            switch viewModel.currentTab {
            case .all:
                allContactsView
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .campaigns:
                campaignsView
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .farms:
                farmsView
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .smartLists:
                smartListsView
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.currentTab)
    }
    
    // MARK: - All Contacts View
    
    private var allContactsView: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredContacts.isEmpty {
                emptyStateView(message: "No contacts found")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.filteredContacts) { contact in
                            ContactCardView(
                                contact: contact,
                                onTap: {
                                    viewModel.selectedContact = contact
                                    showDetailSheet = true
                                },
                                onLogActivity: {
                                    viewModel.selectedContact = contact
                                    showDetailSheet = true
                                },
                                onViewMap: {
                                    // TODO: Open map with contact location
                                },
                                onDelete: {
                                    Task {
                                        await viewModel.deleteContact(contact)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80) // Space for floating button
                }
            }
        }
    }
    
    // MARK: - Campaigns View
    
    private var campaignsView: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let grouped = viewModel.contactsByCampaign
                if grouped.isEmpty {
                    emptyStateView(message: "No campaign contacts")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(grouped.keys), id: \.self) { campaignId in
                                CampaignGroupSection(
                                    campaignId: campaignId,
                                    contacts: grouped[campaignId] ?? [],
                                    onContactTap: { contact in
                                        viewModel.selectedContact = contact
                                        showDetailSheet = true
                                    },
                                    onDelete: { contact in
                                        Task {
                                            await viewModel.deleteContact(contact)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                    }
                }
            }
        }
    }
    
    // MARK: - Farms View
    
    private var farmsView: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let grouped = viewModel.contactsByFarm
                if grouped.isEmpty {
                    emptyStateView(message: "No farm contacts")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(grouped.keys), id: \.self) { farmId in
                                FarmGroupSection(
                                    farmId: farmId,
                                    contacts: grouped[farmId] ?? [],
                                    onContactTap: { contact in
                                        viewModel.selectedContact = contact
                                        showDetailSheet = true
                                    },
                                    onDelete: { contact in
                                        Task {
                                            await viewModel.deleteContact(contact)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 80)
                    }
                }
            }
        }
    }
    
    // MARK: - Smart Lists View
    
    private var smartListsView: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(SmartListType.allCases, id: \.self) { listType in
                            SmartListSection(
                                type: listType,
                                contacts: viewModel.getSmartList(listType),
                                onContactTap: { contact in
                                    viewModel.selectedContact = contact
                                    showDetailSheet = true
                                },
                                onDelete: { contact in
                                    Task {
                                        await viewModel.deleteContact(contact)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80)
                }
            }
        }
    }
    
    // MARK: - Floating Add Button
    
    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showNewContact = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accent)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Filters Sheet
    
    private var filtersSheet: some View {
        NavigationStack {
            ContactFiltersView(
                filterStatus: $viewModel.filterStatus,
                filterCampaignId: $viewModel.filterCampaignId,
                filterFarmId: $viewModel.filterFarmId,
                onClear: {
                    viewModel.clearFilters()
                },
                hasActiveFilters: viewModel.hasActiveFilters
            )
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showFilters = false
                        Task {
                            await viewModel.loadContacts()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - New Contact Sheet
    
    private var newContactSheet: some View {
        NavigationStack {
            NewContactView(
                onSave: { contact in
                    Task {
                        await viewModel.addContact(contact)
                        showNewContact = false
                    }
                },
                onCancel: {
                    showNewContact = false
                }
            )
        }
    }
    
    // MARK: - Detail Sheet
    
    private func detailSheet(for contact: Contact) -> some View {
        BottomSheet(
            height: .large,
            isPresented: $showDetailSheet
        ) {
            ContactDetailSheet(
                contact: Binding(
                    get: { viewModel.selectedContact ?? contact },
                    set: { viewModel.selectedContact = $0 }
                ),
                onUpdate: { updatedContact in
                    await viewModel.updateContact(updatedContact)
                },
                onLogActivity: { contactId, type, note in
                    await viewModel.logActivity(contactID: contactId, type: type, note: note)
                },
                onCall: {
                    if let phone = contact.phone, let url = URL(string: "tel://\(phone)") {
                        UIApplication.shared.open(url)
                    }
                },
                onText: {
                    if let phone = contact.phone, let url = URL(string: "sms://\(phone)") {
                        UIApplication.shared.open(url)
                    }
                },
                onViewMap: {
                    // TODO: Open map with contact location
                    showDetailSheet = false
                }
            )
        }
    }
    
    // MARK: - Empty State
    
    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundColor(.muted)
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Campaign Group Section

struct CampaignGroupSection: View {
    let campaignId: UUID
    let contacts: [Contact]
    let onContactTap: (Contact) -> Void
    let onDelete: (Contact) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("Campaign")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.text)
                    Text("(\(contacts.count))")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.muted)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.muted)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                ForEach(contacts) { contact in
                    ContactCardView(
                        contact: contact,
                        onTap: { onContactTap(contact) },
                        onLogActivity: { onContactTap(contact) },
                        onViewMap: {},
                        onDelete: { onDelete(contact) }
                    )
                }
            }
        }
    }
}

// MARK: - Farm Group Section

struct FarmGroupSection: View {
    let farmId: UUID
    let contacts: [Contact]
    let onContactTap: (Contact) -> Void
    let onDelete: (Contact) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text("Farm")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.text)
                    Text("(\(contacts.count))")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.muted)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.muted)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                ForEach(contacts) { contact in
                    ContactCardView(
                        contact: contact,
                        onTap: { onContactTap(contact) },
                        onLogActivity: { onContactTap(contact) },
                        onViewMap: {},
                        onDelete: { onDelete(contact) }
                    )
                }
            }
        }
    }
}

// MARK: - Smart List Section

struct SmartListSection: View {
    let type: SmartListType
    let contacts: [Contact]
    let onContactTap: (Contact) -> Void
    let onDelete: (Contact) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Text(type.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.text)
                    Text("(\(contacts.count))")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.muted)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.muted)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                if contacts.isEmpty {
                    Text("No contacts in this list")
                        .font(.system(size: 14))
                        .foregroundColor(.muted)
                        .padding(.vertical, 8)
                } else {
                    ForEach(contacts) { contact in
                        ContactCardView(
                            contact: contact,
                            onTap: { onContactTap(contact) },
                            onLogActivity: { onContactTap(contact) },
                            onViewMap: {},
                            onDelete: { onDelete(contact) }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - New Contact View

struct NewContactView: View {
    @State private var fullName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var status: ContactStatus = .new
    @State private var notes = ""
    
    let onSave: (Contact) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        Form {
            Section("Contact Information") {
                TextField("Full Name", text: $fullName)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                TextField("Address", text: $address)
            }
            
            Section("Status") {
                Picker("Status", selection: $status) {
                    ForEach(ContactStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
            }
            
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 100)
            }
        }
        .navigationTitle("New Contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    let contact = Contact(
                        fullName: fullName,
                        phone: phone.isEmpty ? nil : phone,
                        email: email.isEmpty ? nil : email,
                        address: address,
                        status: status,
                        notes: notes.isEmpty ? nil : notes
                    )
                    onSave(contact)
                }
                .disabled(fullName.isEmpty || address.isEmpty)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContactsHubView()
    }
}





