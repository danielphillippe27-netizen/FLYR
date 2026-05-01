import Foundation
import Supabase

actor ContactsService {
    static let shared = ContactsService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    private let contactRepository = ContactRepository.shared
    private let outboxRepository = OutboxRepository.shared
    
    private init() {}

    private func shouldUseWorkspaceScope(
        workspaceId: UUID?,
        campaignId: UUID?
    ) -> Bool {
        workspaceId != nil && campaignId == nil
    }
    
    // MARK: - Fetch Contacts
    
    /// - Parameters:
    ///   - userID: Legacy; used when workspaceId is nil for backward compatibility.
    ///   - workspaceId: When non-nil, scope by workspace (RLS allows workspace members); when nil, filter by user_id only.
    func fetchContacts(userID: UUID, workspaceId: UUID? = nil, filter: ContactFilter? = nil) async throws -> [Contact] {
        if await isOffline() {
            return await contactRepository.fetchContacts(userId: userID, workspaceId: workspaceId, filter: filter)
        }

        do {
            let contacts = try await performRemoteFetchContacts(userID: userID, workspaceId: workspaceId, filter: filter)
            await contactRepository.upsertContacts(contacts, userId: userID, workspaceId: workspaceId, dirty: false, syncedAt: Date())
            return contacts
        } catch {
            let cached = await contactRepository.fetchContacts(userId: userID, workspaceId: workspaceId, filter: filter)
            if !cached.isEmpty {
                return cached
            }
            throw error
        }
    }
    
    func fetchContactsByCampaign(userID: UUID, workspaceId: UUID? = nil, campaignID: UUID) async throws -> [Contact] {
        return try await fetchContacts(userID: userID, workspaceId: workspaceId, filter: ContactFilter(campaignId: campaignID))
    }
    
    func fetchContactsByFarm(userID: UUID, workspaceId: UUID? = nil, farmID: UUID) async throws -> [Contact] {
        return try await fetchContacts(userID: userID, workspaceId: workspaceId, filter: ContactFilter(farmId: farmID))
    }
    
    /// Fetches contacts for a specific address using FK relationship
    /// - Parameter addressId: The campaign_addresses.id to fetch contacts for
    /// - Returns: Array of contacts linked to this address
    func fetchContactsForAddress(addressId: UUID) async throws -> [Contact] {
        if await isOffline() {
            return await contactRepository.fetchContactsForAddress(addressId: addressId)
        }

        do {
            let contacts = try await performRemoteFetchContactsForAddress(addressId: addressId)
            await contactRepository.upsertContacts(contacts, userId: nil, workspaceId: nil, dirty: false, syncedAt: Date())
            return contacts
        } catch {
            let cached = await contactRepository.fetchContactsForAddress(addressId: addressId)
            if !cached.isEmpty {
                return cached
            }
            throw error
        }
    }

    /// Deletes every contact linked to this campaign address (`contact_activities` rows cascade).
    func deleteContactsForAddress(addressId: UUID) async throws {
        let contacts = await contactRepository.deleteContactsForAddress(addressId: addressId)
        for contact in contacts {
            try await deleteContact(contact, alreadyDeletedLocally: true)
        }
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
    ///   - workspaceId: When non-nil, set on insert for workspace-scoped contact.
    func addContact(
        _ contact: Contact,
        userID: UUID,
        workspaceId: UUID? = nil,
        addressId: UUID? = nil,
        syncToCRM: Bool = true
    ) async throws -> Contact {
        let normalizedInput = Self.normalized(contact, overrideAddressId: addressId)
        let cachedContext = await contactRepository.upsertContactLocally(
            normalizedInput,
            userId: userID,
            workspaceId: workspaceId,
            addressId: addressId
        )
        if let contactJSON = OfflineJSONCodec.encode(cachedContext.contact) {
            await outboxRepository.enqueue(
                entityType: "contact",
                entityId: cachedContext.contact.id.uuidString,
                operation: .upsertContact,
                payload: ContactOutboxPayload(
                    contactJSON: contactJSON,
                    userId: cachedContext.userId?.uuidString,
                    workspaceId: cachedContext.workspaceId?.uuidString,
                    addressId: cachedContext.contact.addressId?.uuidString,
                    syncToCRM: syncToCRM
                ),
                dependencyKey: "contact:\(cachedContext.contact.id.uuidString.lowercased())"
            )
        }
        await scheduleSyncIfPossible()
        return cachedContext.contact
    }

    private func findExistingContact(
        matching contact: Contact,
        userID: UUID,
        workspaceId: UUID?
    ) async throws -> Contact? {
        var query = client
            .from("contacts")
            .select()

        if shouldUseWorkspaceScope(workspaceId: workspaceId, campaignId: contact.campaignId),
           let workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        } else if contact.campaignId == nil {
            query = query.eq("user_id", value: userID)
        }

        if let campaignId = contact.campaignId {
            query = query.eq("campaign_id", value: campaignId)
        }

        if let addressId = contact.addressId {
            query = query.eq("address_id", value: addressId)
        } else {
            query = query.eq("address", value: contact.address)
        }

        let candidates: [Contact] = try await query
            .order("updated_at", ascending: false)
            .limit(20)
            .execute()
            .value

        return candidates.first {
            Self.isSameContactIdentity(existing: $0, incoming: contact)
        }
    }

    private static func isSameContactIdentity(existing: Contact, incoming: Contact) -> Bool {
        let hasExactAddressIdMatch: Bool = {
            guard let incomingAddressId = incoming.addressId, let existingAddressId = existing.addressId else { return false }
            return incomingAddressId == existingAddressId
        }()

        if let incomingAddressId = incoming.addressId, let existingAddressId = existing.addressId {
            if incomingAddressId != existingAddressId { return false }
        } else {
            let existingAddress = normalizedText(existing.address)
            let incomingAddress = normalizedText(incoming.address)
            if !existingAddress.isEmpty && !incomingAddress.isEmpty && existingAddress != incomingAddress {
                return false
            }
        }

        if let incomingCampaign = incoming.campaignId, let existingCampaign = existing.campaignId, incomingCampaign != existingCampaign {
            return false
        }

        let existingName = normalizedText(existing.fullName)
        let incomingName = normalizedText(incoming.fullName)
        let existingPhone = normalizedPhone(existing.phone)
        let incomingPhone = normalizedPhone(incoming.phone)
        let existingEmail = normalizedText(existing.email)
        let incomingEmail = normalizedText(incoming.email)

        let phoneMatches = !existingPhone.isEmpty && !incomingPhone.isEmpty && existingPhone == incomingPhone
        let emailMatches = !existingEmail.isEmpty && !incomingEmail.isEmpty && existingEmail == incomingEmail
        let nameMatches = !existingName.isEmpty && !incomingName.isEmpty && existingName == incomingName
        if phoneMatches || emailMatches || nameMatches {
            return true
        }

        // For exact address matches, treat placeholder-only records as same lead to avoid double inserts.
        if hasExactAddressIdMatch {
            let hasNoStrongIdentity = (existingPhone.isEmpty && existingEmail.isEmpty && existingName.isEmpty)
                || (incomingPhone.isEmpty && incomingEmail.isEmpty && incomingName.isEmpty)
            let hasPlaceholderName = isPlaceholderName(existing.fullName) || isPlaceholderName(incoming.fullName)
            if hasNoStrongIdentity || hasPlaceholderName {
                return true
            }
        }
        return false
    }

    private static func merged(existing: Contact, incoming: Contact) -> Contact {
        Contact(
            id: existing.id,
            fullName: preferredNonEmptyRequired(incoming.fullName, fallback: existing.fullName),
            phone: preferredNonEmptyOptional(incoming.phone, fallback: existing.phone),
            email: preferredNonEmptyOptional(incoming.email, fallback: existing.email),
            address: preferredNonEmptyRequired(incoming.address, fallback: existing.address),
            campaignId: incoming.campaignId ?? existing.campaignId,
            farmId: incoming.farmId ?? existing.farmId,
            gersId: preferredNonEmptyOptional(incoming.gersId, fallback: existing.gersId),
            addressId: incoming.addressId ?? existing.addressId,
            tags: preferredNonEmptyOptional(incoming.tags, fallback: existing.tags),
            status: existing.status == .new ? incoming.status : existing.status,
            lastContacted: incoming.lastContacted ?? existing.lastContacted,
            notes: preferredNonEmptyOptional(incoming.notes, fallback: existing.notes),
            reminderDate: incoming.reminderDate ?? existing.reminderDate,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )
    }

    private static func normalized(_ contact: Contact, overrideAddressId: UUID?) -> Contact {
        Contact(
            id: contact.id,
            fullName: contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: normalizedOptional(contact.phone),
            email: normalizedOptional(contact.email),
            address: contact.address.trimmingCharacters(in: .whitespacesAndNewlines),
            campaignId: contact.campaignId,
            farmId: contact.farmId,
            gersId: normalizedOptional(contact.gersId),
            addressId: overrideAddressId ?? contact.addressId,
            tags: normalizedOptional(contact.tags),
            status: contact.status,
            lastContacted: contact.lastContacted,
            notes: normalizedOptional(contact.notes),
            reminderDate: contact.reminderDate,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt
        )
    }

    private static func normalizedText(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func normalizedPhone(_ value: String?) -> String {
        guard let value else { return "" }
        return value.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func preferredNonEmptyOptional(_ primary: String?, fallback: String?) -> String? {
        if let value = normalizedOptional(primary) {
            return value
        }
        return normalizedOptional(fallback)
    }

    private static func preferredNonEmptyRequired(_ primary: String, fallback: String) -> String {
        if let value = normalizedOptional(primary) {
            return value
        }
        if let value = normalizedOptional(fallback) {
            return value
        }
        return ""
    }

    private static func isPlaceholderName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "lead" || normalized == "new contact"
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
    
    func updateContact(
        _ contact: Contact,
        userID: UUID? = nil,
        workspaceId: UUID? = nil,
        addressId: UUID? = nil,
        syncToCRM: Bool = true
    ) async throws -> Contact {
        let cachedContext = await contactRepository.upsertContactLocally(
            contact,
            userId: userID,
            workspaceId: workspaceId,
            addressId: addressId
        )
        if let contactJSON = OfflineJSONCodec.encode(cachedContext.contact) {
            await outboxRepository.enqueue(
                entityType: "contact",
                entityId: cachedContext.contact.id.uuidString,
                operation: .upsertContact,
                payload: ContactOutboxPayload(
                    contactJSON: contactJSON,
                    userId: cachedContext.userId?.uuidString,
                    workspaceId: cachedContext.workspaceId?.uuidString,
                    addressId: cachedContext.contact.addressId?.uuidString,
                    syncToCRM: syncToCRM
                ),
                dependencyKey: "contact:\(cachedContext.contact.id.uuidString.lowercased())"
            )
        }
        await scheduleSyncIfPossible()
        return cachedContext.contact
    }
    
    func deleteContact(_ contact: Contact) async throws {
        try await deleteContact(contact, alreadyDeletedLocally: false)
    }
    
    // MARK: - Activities
    
    func logActivity(contactID: UUID, type: ActivityType, note: String?) async throws -> ContactActivity {
        let activity = await contactRepository.addActivityLocally(
            contactId: contactID,
            type: type,
            note: note
        )
        await outboxRepository.enqueue(
            entityType: "contact_activity",
            entityId: activity.id.uuidString,
            operation: .createContactActivity,
            payload: ContactActivityOutboxPayload(
                localActivityId: activity.id.uuidString,
                contactId: activity.contactId.uuidString,
                type: activity.type.rawValue,
                note: activity.note,
                timestamp: OfflineDateCodec.string(from: activity.timestamp)
            ),
            dependencyKey: "contact:\(activity.contactId.uuidString.lowercased())"
        )
        await scheduleSyncIfPossible()
        return activity
    }
    
    func fetchActivities(contactID: UUID) async throws -> [ContactActivity] {
        if await isOffline() {
            return await contactRepository.fetchActivities(contactId: contactID)
        }

        do {
            let response: [ContactActivity] = try await client
                .from("contact_activities")
                .select()
                .eq("contact_id", value: contactID)
                .order("timestamp", ascending: false)
                .execute()
                .value
            await contactRepository.upsertActivities(response, dirty: false, syncedAt: Date())
            return response
        } catch {
            let cached = await contactRepository.fetchActivities(contactId: contactID)
            if !cached.isEmpty {
                return cached
            }
            throw error
        }
    }

    func performRemoteUpsertContact(
        _ contact: Contact,
        userID: UUID?,
        workspaceId: UUID?,
        addressId: UUID?,
        syncToCRM: Bool
    ) async throws -> Contact {
        if let updated = try await performRemoteUpdateContact(contact, addressId: addressId) {
            if syncToCRM, let userID {
                Task.detached(priority: .utility) {
                    let leadModel = LeadModel(from: updated)
                    await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: userID)
                }
            }
            return updated
        }
        guard let userID else {
            throw NSError(domain: "ContactsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing user ID for remote contact insert"])
        }
        return try await performRemoteAddContact(contact, userID: userID, workspaceId: workspaceId, addressId: addressId, syncToCRM: syncToCRM)
    }

    func performRemoteLogActivity(
        contactID: UUID,
        type: ActivityType,
        note: String?,
        timestamp: Date? = nil
    ) async throws -> ContactActivity {
        let activityTimestamp = ISO8601DateFormatter().string(from: timestamp ?? Date())
        let activityData: [String: AnyCodable] = [
            "contact_id": AnyCodable(contactID),
            "type": AnyCodable(type.rawValue),
            "note": AnyCodable(note as Any),
            "timestamp": AnyCodable(activityTimestamp)
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

    func performRemoteDeleteContact(contactId: UUID) async throws {
        try await client
            .from("contacts")
            .delete()
            .eq("id", value: contactId)
            .execute()
    }

    private func performRemoteFetchContacts(userID: UUID, workspaceId: UUID? = nil, filter: ContactFilter? = nil) async throws -> [Contact] {
        var query = client
            .from("contacts")
            .select()
        if shouldUseWorkspaceScope(workspaceId: workspaceId, campaignId: filter?.campaignId),
           let workspaceId = workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        } else if filter?.campaignId == nil {
            query = query.eq("user_id", value: userID)
        }

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
        }

        let response: [Contact] = try await query
            .order("updated_at", ascending: false)
            .execute()
            .value

        return response
    }

    private func performRemoteFetchContactsForAddress(addressId: UUID) async throws -> [Contact] {
        let response: [Contact] = try await client
            .from("contacts")
            .select()
            .eq("address_id", value: addressId)
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    private func performRemoteAddContact(
        _ contact: Contact,
        userID: UUID,
        workspaceId: UUID? = nil,
        addressId: UUID? = nil,
        syncToCRM: Bool = true
    ) async throws -> Contact {
        let contactToInsert = Self.normalized(contact, overrideAddressId: addressId)
        var insertData: [String: AnyCodable] = [
            "id": AnyCodable(contactToInsert.id),
            "user_id": AnyCodable(userID),
            "full_name": AnyCodable(contactToInsert.fullName),
            "phone": AnyCodable(contactToInsert.phone as Any),
            "email": AnyCodable(contactToInsert.email as Any),
            "address": AnyCodable(contactToInsert.address),
            "campaign_id": AnyCodable(contactToInsert.campaignId as Any),
            "farm_id": AnyCodable(contactToInsert.farmId as Any),
            "gers_id": AnyCodable(contactToInsert.gersId as Any),
            "address_id": AnyCodable(contactToInsert.addressId as Any),
            "tags": AnyCodable(contactToInsert.tags as Any),
            "status": AnyCodable(contactToInsert.status.rawValue),
            "last_contacted": AnyCodable(contactToInsert.lastContacted as Any),
            "notes": AnyCodable(contactToInsert.notes as Any),
            "reminder_date": AnyCodable(contactToInsert.reminderDate as Any)
        ]
        if contactToInsert.campaignId == nil, let workspaceId = workspaceId {
            insertData["workspace_id"] = AnyCodable(workspaceId)
        }
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

        if syncToCRM {
            Task.detached(priority: .utility) {
                let leadModel = LeadModel(from: inserted)
                await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: userID)
            }
        }

        return inserted
    }

    private func performRemoteUpdateContact(_ contact: Contact, addressId: UUID? = nil) async throws -> Contact? {
        var updateData: [String: AnyCodable] = [
            "full_name": AnyCodable(contact.fullName),
            "phone": AnyCodable(contact.phone as Any),
            "email": AnyCodable(contact.email as Any),
            "address": AnyCodable(contact.address),
            "campaign_id": AnyCodable(contact.campaignId as Any),
            "farm_id": AnyCodable(contact.farmId as Any),
            "gers_id": AnyCodable(contact.gersId as Any),
            "address_id": AnyCodable(contact.addressId as Any),
            "tags": AnyCodable(contact.tags as Any),
            "status": AnyCodable(contact.status.rawValue),
            "last_contacted": AnyCodable(contact.lastContacted as Any),
            "notes": AnyCodable(contact.notes as Any),
            "reminder_date": AnyCodable(contact.reminderDate as Any)
        ]

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

        return response.first
    }

    private func isOffline() async -> Bool {
        await MainActor.run { !NetworkMonitor.shared.isOnline }
    }

    private func scheduleSyncIfPossible() async {
        let shouldSchedule = await MainActor.run { NetworkMonitor.shared.isOnline }
        guard shouldSchedule else { return }
        await MainActor.run {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
    }

    private func deleteContact(_ contact: Contact, alreadyDeletedLocally: Bool) async throws {
        if !alreadyDeletedLocally {
            await contactRepository.deleteContacts(ids: [contact.id])
        }
        await outboxRepository.enqueue(
            entityType: "contact",
            entityId: contact.id.uuidString,
            operation: .deleteContact,
            payload: DeleteContactOutboxPayload(contactId: contact.id.uuidString),
            dependencyKey: "contact:\(contact.id.uuidString.lowercased())"
        )
        await scheduleSyncIfPossible()
    }
}

// MARK: - Contact Filter

struct ContactFilter {
    var status: ContactStatus? = nil
    var campaignId: UUID? = nil
    var farmId: UUID? = nil
    var searchText: String? = nil
}
