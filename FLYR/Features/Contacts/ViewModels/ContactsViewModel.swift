import SwiftUI
import Combine
import Supabase

// MARK: - Contacts Tab

enum ContactsTab: String, CaseIterable {
    case all = "All"
    case campaigns = "Campaigns"
    case farms = "Farms"
    case smartLists = "Smart Lists"
}

// MARK: - Smart List Type

enum SmartListType: String, CaseIterable {
    case newThisWeek = "New This Week"
    case noContact30Days = "No Contact in 30 Days"
    case needsFollowUpToday = "Needs Follow-Up Today"
    case topConversions = "Top Conversions"
}

// MARK: - Contacts View Model

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentTab: ContactsTab = .all
    @Published var searchText: String = ""
    @Published var selectedContact: Contact?
    @Published var showFilters = false
    @Published var filterStatus: ContactStatus?
    @Published var filterCampaignId: UUID?
    @Published var filterFarmId: UUID?
    
    private let contactsService = ContactsService.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Debounce search text changes
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.loadContacts()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Load Contacts
    
    func loadContacts(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let filter = ContactFilter(
                status: filterStatus,
                campaignId: filterCampaignId,
                farmId: filterFarmId,
                searchText: nil // Search is done client-side
            )
            
            contacts = try await contactsService.fetchContacts(userID: userID, filter: filter)
        } catch {
            errorMessage = "Failed to load contacts: \(error.localizedDescription)"
            print("❌ Error loading contacts: \(error)")
        }
    }
    
    func loadContacts() async {
        guard let userID = AuthManager.shared.user?.id else {
            errorMessage = "User not authenticated"
            return
        }
        await loadContacts(for: userID)
    }
    
    // MARK: - Filtered Contacts
    
    var filteredContacts: [Contact] {
        var result: [Contact]
        
        switch currentTab {
        case .all:
            result = contacts
        case .campaigns:
            result = contacts.filter { $0.campaignId != nil }
        case .farms:
            result = contacts.filter { $0.farmId != nil }
        case .smartLists:
            result = smartListContacts
        }
        
        // Apply client-side search filtering
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            result = result.filter { contact in
                contact.fullName.lowercased().contains(searchLower) ||
                contact.address.lowercased().contains(searchLower) ||
                (contact.phone?.lowercased().contains(searchLower) ?? false) ||
                (contact.email?.lowercased().contains(searchLower) ?? false)
            }
        }
        
        return result
    }
    
    // MARK: - Grouped Contacts
    
    var contactsByCampaign: [UUID: [Contact]] {
        Dictionary(grouping: contacts.filter { $0.campaignId != nil }) { $0.campaignId! }
    }
    
    var contactsByFarm: [UUID: [Contact]] {
        Dictionary(grouping: contacts.filter { $0.farmId != nil }) { $0.farmId! }
    }
    
    // MARK: - Smart Lists
    
    var smartListContacts: [Contact] {
        // For now, return all contacts that match any smart list criteria
        // In a full implementation, you'd have a selected smart list
        return contacts.filter { contact in
            contact.isNewThisWeek ||
            contact.hasNoContactIn30Days ||
            contact.needsFollowUpToday ||
            contact.status == .hot
        }
    }
    
    func getSmartList(_ type: SmartListType) -> [Contact] {
        switch type {
        case .newThisWeek:
            return contacts.filter { $0.isNewThisWeek }
        case .noContact30Days:
            return contacts.filter { $0.hasNoContactIn30Days }
        case .needsFollowUpToday:
            return contacts.filter { $0.needsFollowUpToday }
        case .topConversions:
            return contacts
                .filter { $0.status == .hot }
                .sorted { ($0.lastContacted ?? Date.distantPast) > ($1.lastContacted ?? Date.distantPast) }
        }
    }
    
    // MARK: - Contact Actions
    
    func addContact(_ contact: Contact) async {
        guard let userID = AuthManager.shared.user?.id else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let newContact = try await contactsService.addContact(contact, userID: userID)
            await loadContacts(for: userID)
            selectedContact = newContact
        } catch {
            errorMessage = "Failed to add contact: \(error.localizedDescription)"
            print("❌ Error adding contact: \(error)")
        }
    }
    
    func updateContact(_ contact: Contact) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let updated = try await contactsService.updateContact(contact)
            if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
                contacts[index] = updated
            }
            selectedContact = updated
        } catch {
            errorMessage = "Failed to update contact: \(error.localizedDescription)"
            print("❌ Error updating contact: \(error)")
        }
    }
    
    func deleteContact(_ contact: Contact) async {
        guard let userID = AuthManager.shared.user?.id else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await contactsService.deleteContact(contact)
            contacts.removeAll { $0.id == contact.id }
            if selectedContact?.id == contact.id {
                selectedContact = nil
            }
        } catch {
            errorMessage = "Failed to delete contact: \(error.localizedDescription)"
            print("❌ Error deleting contact: \(error)")
        }
    }
    
    func logActivity(contactID: UUID, type: ActivityType, note: String?) async {
        do {
            _ = try await contactsService.logActivity(contactID: contactID, type: type, note: note)
            await loadContacts()
        } catch {
            errorMessage = "Failed to log activity: \(error.localizedDescription)"
            print("❌ Error logging activity: \(error)")
        }
    }
    
    // MARK: - Filter Management
    
    func clearFilters() {
        filterStatus = nil
        filterCampaignId = nil
        filterFarmId = nil
        Task {
            await loadContacts()
        }
    }
    
    var hasActiveFilters: Bool {
        filterStatus != nil || filterCampaignId != nil || filterFarmId != nil
    }
}

