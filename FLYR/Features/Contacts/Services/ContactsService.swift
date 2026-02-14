import Foundation
import Supabase

actor ContactsService {
    static let shared = ContactsService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch Contacts
    
    func fetchContacts(userID: UUID, filter: ContactFilter? = nil) async throws -> [Contact] {
        var query = client
            .from("contacts")
            .select()
            .eq("user_id", value: userID)
        
        if let filter = filter {
            if let status = filter.status {
                query = query.eq("status", value: status.rawValue)
            }
            if let campaignId = filter.campaignId {
                query = query.eq("campaign_id", value: campaignId)
            }
            if let farmId = filter.farmId {
                query = query.eq("farm_id", value: farmId)
            }
            // Note: Search filtering is done client-side for multi-field support
            // The searchText filter is applied in the ViewModel after fetching
        }
        
        let response: [Contact] = try await query
            .order("updated_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    func fetchContactsByCampaign(userID: UUID, campaignID: UUID) async throws -> [Contact] {
        return try await fetchContacts(userID: userID, filter: ContactFilter(campaignId: campaignID))
    }
    
    func fetchContactsByFarm(userID: UUID, farmID: UUID) async throws -> [Contact] {
        return try await fetchContacts(userID: userID, filter: ContactFilter(farmId: farmID))
    }
    
    /// Fetches contacts for a specific address using FK relationship
    /// - Parameter addressId: The campaign_addresses.id to fetch contacts for
    /// - Returns: Array of contacts linked to this address
    func fetchContactsForAddress(addressId: UUID) async throws -> [Contact] {
        let response: [Contact] = try await client
            .from("contacts")
            .select()
            .eq("address_id", value: addressId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    /// Fetches contacts for an address using text matching (fallback for legacy data)
    /// - Parameters:
    ///   - addressText: The address text to search for
    ///   - campaignId: The campaign ID to filter by
    /// - Returns: Array of contacts that match the address text
    func fetchContactsForAddressText(addressText: String, campaignId: UUID) async throws -> [Contact] {
        let response: [Contact] = try await client
            .from("contacts")
            .select()
            .ilike("address", pattern: "%\(addressText)%")
            .eq("campaign_id", value: campaignId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    /// Links a contact to an address via FK
    /// - Parameters:
    ///   - contactId: The contact ID to link
    ///   - addressId: The campaign_addresses.id to link to
    func linkContactToAddress(contactId: UUID, addressId: UUID) async throws {
        let updateData: [String: AnyCodable] = [
            "address_id": AnyCodable(addressId)
        ]
        
        try await client
            .from("contacts")
            .update(updateData)
            .eq("id", value: contactId)
            .execute()
    }
    
    // MARK: - Contact CRUD
    
    func addContact(_ contact: Contact, userID: UUID, addressId: UUID? = nil) async throws -> Contact {
        var contactToInsert = contact
        // Ensure user_id is set
        var insertData: [String: AnyCodable] = [
            "id": AnyCodable(contactToInsert.id),
            "user_id": AnyCodable(userID),
            "full_name": AnyCodable(contactToInsert.fullName),
            "phone": AnyCodable(contactToInsert.phone),
            "email": AnyCodable(contactToInsert.email),
            "address": AnyCodable(contactToInsert.address),
            "campaign_id": AnyCodable(contactToInsert.campaignId),
            "farm_id": AnyCodable(contactToInsert.farmId),
            "status": AnyCodable(contactToInsert.status.rawValue),
            "last_contacted": AnyCodable(contactToInsert.lastContacted),
            "notes": AnyCodable(contactToInsert.notes),
            "reminder_date": AnyCodable(contactToInsert.reminderDate)
        ]
        
        // Add address_id if provided
        if let addressId = addressId {
            insertData["address_id"] = AnyCodable(addressId)
        }
        
        let response: [Contact] = try await client
            .from("contacts")
            .insert(insertData)
            .select()
            .execute()
            .value
        
        guard let inserted = response.first else {
            throw NSError(domain: "ContactsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert contact"])
        }
        
        // Sync to CRM integrations (non-blocking)
        Task.detached(priority: .utility) {
            let leadModel = LeadModel(from: inserted)
            await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: userID)
        }
        
        return inserted
    }
    
    func updateContact(_ contact: Contact, addressId: UUID? = nil) async throws -> Contact {
        var updateData: [String: AnyCodable] = [
            "full_name": AnyCodable(contact.fullName),
            "phone": AnyCodable(contact.phone),
            "email": AnyCodable(contact.email),
            "address": AnyCodable(contact.address),
            "campaign_id": AnyCodable(contact.campaignId),
            "farm_id": AnyCodable(contact.farmId),
            "status": AnyCodable(contact.status.rawValue),
            "last_contacted": AnyCodable(contact.lastContacted),
            "notes": AnyCodable(contact.notes),
            "reminder_date": AnyCodable(contact.reminderDate)
        ]
        
        // Add address_id if provided
        if let addressId = addressId {
            updateData["address_id"] = AnyCodable(addressId)
        }
        
        let response: [Contact] = try await client
            .from("contacts")
            .update(updateData)
            .eq("id", value: contact.id)
            .select()
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "ContactsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update contact"])
        }
        
        return updated
    }
    
    func deleteContact(_ contact: Contact) async throws {
        try await client
            .from("contacts")
            .delete()
            .eq("id", value: contact.id)
            .execute()
    }
    
    // MARK: - Activities
    
    func logActivity(contactID: UUID, type: ActivityType, note: String?) async throws -> ContactActivity {
        let activityData: [String: AnyCodable] = [
            "contact_id": AnyCodable(contactID),
            "type": AnyCodable(type.rawValue),
            "note": AnyCodable(note),
            "timestamp": AnyCodable(Date())
        ]
        
        let response: [ContactActivity] = try await client
            .from("contact_activities")
            .insert(activityData)
            .select()
            .execute()
            .value
        
        guard let inserted = response.first else {
            throw NSError(domain: "ContactsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert activity"])
        }
        
        return inserted
    }
    
    func fetchActivities(contactID: UUID) async throws -> [ContactActivity] {
        let response: [ContactActivity] = try await client
            .from("contact_activities")
            .select()
            .eq("contact_id", value: contactID)
            .order("timestamp", ascending: false)
            .execute()
            .value
        
        return response
    }
}

// MARK: - Contact Filter

struct ContactFilter {
    var status: ContactStatus? = nil
    var campaignId: UUID? = nil
    var farmId: UUID? = nil
    var searchText: String? = nil
}

