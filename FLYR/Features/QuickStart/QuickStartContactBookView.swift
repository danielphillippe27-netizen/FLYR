import SwiftUI

private enum QuickStartContactBookTab: String, CaseIterable {
    case all = "All"
    case leads = "Leads"
    case contacts = "Contacts"
    case clients = "Clients"
    case unqualified = "Unqualified"
}

struct QuickStartContactBookView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContactsViewModel()
    @State private var selectedTab: QuickStartContactBookTab = .all
    @State private var selectedContact: Contact?

    private var quickStartContacts: [Contact] {
        viewModel.filteredContacts.filter { contact in
            (contact.tags ?? "").lowercased().contains("quick_start")
                || (contact.campaignId == nil && contact.farmId == nil)
        }
    }

    private var visibleContacts: [Contact] {
        switch selectedTab {
        case .all:
            return quickStartContacts
        case .leads:
            return quickStartContacts.filter { $0.status == .hot || $0.status == .warm }
        case .contacts:
            return quickStartContacts.filter { $0.status == .new }
        case .clients:
            return quickStartContacts.filter { $0.status == .cold }
        case .unqualified:
            return quickStartContacts.filter { $0.status == .cold }
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
                await viewModel.loadContacts()
            }
            .refreshable {
                await viewModel.loadContacts()
            }
            .sheet(item: $selectedContact) { contact in
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
                ForEach(QuickStartContactBookTab.allCases, id: \.self) { tab in
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
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleContacts.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("No Quick Start contacts yet")
                    .font(.system(size: 18, weight: .semibold))
                Text("Contacts saved from Quick Start homes will appear here.")
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
                        QuickStartContactRow(contact: contact)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.visible)
                }
            }
            .listStyle(.plain)
        }
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
                Text("Last update: \(contact.updatedAt.formatted(date: .long, time: .omitted))")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    QuickStartContactBookView()
}
