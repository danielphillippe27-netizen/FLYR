import Foundation
import Supabase

actor FieldLeadsService {
    static let shared = FieldLeadsService()
    private let contactRepository = ContactRepository.shared

    struct AddLeadOutcome {
        let lead: FieldLead
        let createdNew: Bool
    }

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private init() {}

    private func shouldUseWorkspaceScope(
        workspaceId: UUID?,
        campaignId: UUID?
    ) -> Bool {
        workspaceId != nil && campaignId == nil
    }

    // MARK: - CRM sync status (field leads)

    /// Updates `sync_status` / `last_synced_at` on `contacts` and legacy `field_leads` for inbox UI.
    func applyCRMLifecycle(_ phase: FieldLeadCRMSyncLifecycle, userId: UUID) async {
        switch phase {
        case .started(let leadId):
            try? await patchLeadCRMStatus(leadId: leadId, userId: userId, status: .pending, setLastSynced: false)
        case .finished(let leadId, let status, _):
            try? await patchLeadCRMStatus(
                leadId: leadId,
                userId: userId,
                status: status,
                setLastSynced: status == .synced
            )
        }
    }

    private func patchLeadCRMStatus(
        leadId: UUID,
        userId: UUID,
        status: FieldLeadSyncStatus,
        setLastSynced: Bool
    ) async throws {
        var dict: [String: AnyCodable] = [
            "updated_at": AnyCodable(Date()),
            "sync_status": AnyCodable(status.rawValue),
        ]
        if setLastSynced {
            dict["last_synced_at"] = AnyCodable(Date())
        }
        _ = try await client
            .from("contacts")
            .update(dict)
            .eq("id", value: leadId)
            .eq("user_id", value: userId)
            .execute()
        _ = try await client
            .from("field_leads")
            .update(dict)
            .eq("id", value: leadId)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Fetch

    /// `contacts` is the primary lead store. Fall back to legacy `field_leads` rows only when needed.
    func fetchLeads(userId: UUID, workspaceId: UUID? = nil, campaignId: UUID? = nil, sessionId: UUID? = nil) async throws -> [FieldLead] {
        if await isOffline() {
            let cached = await fetchCachedLeads(userId: userId, workspaceId: workspaceId, campaignId: campaignId)
            if !cached.isEmpty {
                return cached
            }
        }

        do {
            let contacts = try await fetchContactLeadRows(
                userId: userId,
                workspaceId: workspaceId,
                campaignId: campaignId,
                sessionId: sessionId
            )
            if !contacts.isEmpty {
                await cacheLeadRows(contacts, userId: userId, workspaceId: workspaceId)
                return Self.deduplicated(contacts.map(Self.makeFieldLead(from:)))
            }
        } catch {
            print("⚠️ [FieldLeadsService] Contacts fetch failed, falling back to field_leads: \(error.localizedDescription)")
            let cached = await fetchCachedLeads(userId: userId, workspaceId: workspaceId, campaignId: campaignId)
            if !cached.isEmpty {
                return cached
            }
        }

        return Self.deduplicated(try await fetchLegacyLeads(
            userId: userId,
            workspaceId: workspaceId,
            campaignId: campaignId,
            sessionId: sessionId
        ))
    }

    // MARK: - Create

    /// Writes to `contacts` so house notes/appointments and lead inbox share one source of truth.
    func addLead(_ lead: FieldLead, workspaceId: UUID? = nil) async throws -> FieldLead {
        try await addLeadDetailed(lead, workspaceId: workspaceId).lead
    }

    /// Same as addLead, but tells the caller whether a new lead row was created.
    func addLeadDetailed(_ lead: FieldLead, workspaceId: UUID? = nil) async throws -> AddLeadOutcome {
        if let existing = try await findExistingContactLead(matching: lead, workspaceId: workspaceId) {
            let merged = Self.mergedLead(existing: existing, incoming: lead)
            let updated = try await updateLead(merged)

            Task.detached(priority: .utility) {
                let leadModel = LeadModel(from: updated)
                await LeadSyncManager.shared.syncLeadToCRM(
                    lead: leadModel,
                    userId: updated.userId,
                    trackFieldLeadCRMStatus: true
                )
            }

            return AddLeadOutcome(lead: updated, createdNew: false)
        }

        do {
            let inserted = try await insertContactLead(lead, workspaceId: workspaceId)

            Task.detached(priority: .utility) {
                let leadModel = LeadModel(from: inserted)
                await LeadSyncManager.shared.syncLeadToCRM(
                    lead: leadModel,
                    userId: inserted.userId,
                    trackFieldLeadCRMStatus: true
                )
            }

            return AddLeadOutcome(lead: inserted, createdNew: true)
        } catch {
            print("⚠️ [FieldLeadsService] Contact insert failed, falling back to field_leads: \(error.localizedDescription)")
            return AddLeadOutcome(
                lead: try await insertLegacyLead(lead, workspaceId: workspaceId),
                createdNew: true
            )
        }
    }

    func upsertLead(
        from contact: Contact,
        userId: UUID,
        workspaceId: UUID? = nil
    ) async throws -> FieldLead {
        let trimmedName = contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = contact.phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = contact.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = contact.notes?.trimmingCharacters(in: .whitespacesAndNewlines)

        let existing = try? await fetchContactLeadRows(
            userId: userId,
            workspaceId: workspaceId,
            campaignId: contact.campaignId,
            sessionId: nil,
            address: contact.address,
            limit: 1
        )

        if var matchedLead = existing?.map(Self.makeFieldLead(from:)).first {
            matchedLead.name = trimmedName.isEmpty ? matchedLead.name : trimmedName
            matchedLead.phone = trimmedPhone?.nilIfEmpty
            matchedLead.email = trimmedEmail?.nilIfEmpty
            matchedLead.notes = trimmedNotes?.nilIfEmpty
            matchedLead.status = matchedLead.status == .notHome || matchedLead.status == .noAnswer ? .interested : matchedLead.status
            matchedLead.updatedAt = Date()
            return try await updateLead(matchedLead)
        }

        let lead = FieldLead(
            userId: userId,
            address: contact.address,
            name: trimmedName.isEmpty ? nil : trimmedName,
            phone: trimmedPhone?.nilIfEmpty,
            email: trimmedEmail?.nilIfEmpty,
            status: .interested,
            notes: trimmedNotes?.nilIfEmpty,
            qrCode: nil,
            campaignId: contact.campaignId,
            sessionId: nil
        )
        return try await addLead(lead, workspaceId: workspaceId)
    }

    // MARK: - Update

    func updateLead(_ lead: FieldLead) async throws -> FieldLead {
        let workspaceId = await MainActor.run { WorkspaceContext.shared.workspaceId }
        let savedContact = try await ContactsService.shared.updateContact(
            Self.makeContact(from: lead),
            userID: lead.userId,
            workspaceId: workspaceId,
            syncToCRM: true
        )
        return Self.mergeLead(lead, with: savedContact)
    }

    // MARK: - Delete

    func deleteLead(_ lead: FieldLead) async throws {
        do {
            let response = try await client
                .from("contacts")
                .delete()
                .eq("id", value: lead.id)
                .select("id")
                .execute()

            let rows = try JSONDecoder.supabaseDates.decode([DeletedLeadRow].self, from: response.data)
            if !rows.isEmpty {
                return
            }
        } catch {
            print("⚠️ [FieldLeadsService] Contact delete failed, falling back to field_leads: \(error.localizedDescription)")
        }

        try await client
            .from("field_leads")
            .delete()
            .eq("id", value: lead.id)
            .execute()
    }

    func deleteLeads(_ leads: [FieldLead]) async throws {
        let ids = Array(Set(leads.map(\.id)))
        guard !ids.isEmpty else { return }

        var remainingIds = Set(ids)

        do {
            let response = try await client
                .from("contacts")
                .delete()
                .in("id", values: ids.map(\.uuidString))
                .select("id")
                .execute()

            let rows = try JSONDecoder.supabaseDates.decode([DeletedLeadRow].self, from: response.data)
            rows.forEach { remainingIds.remove($0.id) }

            if remainingIds.isEmpty {
                return
            }
        } catch {
            print("⚠️ [FieldLeadsService] Bulk contact delete failed, falling back to field_leads: \(error.localizedDescription)")
        }

        try await client
            .from("field_leads")
            .delete()
            .in("id", values: remainingIds.map(\.uuidString))
            .execute()
    }

    // MARK: - Contacts Primary Store

    private func findExistingContactLead(
        matching lead: FieldLead,
        workspaceId: UUID?
    ) async throws -> FieldLead? {
        let existingRows = try await fetchContactLeadRows(
            userId: lead.userId,
            workspaceId: workspaceId,
            campaignId: lead.campaignId,
            sessionId: nil,
            address: lead.address,
            limit: 1
        )
        return existingRows.first.map(Self.makeFieldLead(from:))
    }

    private func fetchContactLeadRows(
        userId: UUID,
        workspaceId: UUID?,
        campaignId: UUID?,
        sessionId: UUID?,
        address: String? = nil,
        limit: Int? = nil
    ) async throws -> [ContactLeadRow] {
        var query = client
            .from("contacts")
            .select("id,user_id,full_name,phone,email,address,status,notes,qr_code,campaign_id,session_id,external_crm_id,last_synced_at,sync_status,created_at,updated_at")

        if shouldUseWorkspaceScope(workspaceId: workspaceId, campaignId: campaignId),
           let workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        } else if campaignId == nil {
            query = query.eq("user_id", value: userId)
        }

        if let campaignId {
            query = query.eq("campaign_id", value: campaignId)
        }
        if let sessionId {
            query = query.eq("session_id", value: sessionId)
        }
        if let address {
            query = query.eq("address", value: address)
        }

        let response = try await query
            .order("updated_at", ascending: false)
            .limit(limit ?? 500)
            .execute()

        return try JSONDecoder.supabaseDates.decode([ContactLeadRow].self, from: response.data)
    }

    private func insertContactLead(_ lead: FieldLead, workspaceId: UUID?) async throws -> FieldLead {
        var insertData: [String: AnyCodable] = [
            "id": AnyCodable(lead.id),
            "user_id": AnyCodable(lead.userId),
            "full_name": AnyCodable(Self.contactFullName(from: lead.name)),
            "address": AnyCodable(lead.address),
            "status": AnyCodable(lead.status.rawValue),
            "created_at": AnyCodable(lead.createdAt),
            "updated_at": AnyCodable(lead.updatedAt)
        ]
        if lead.campaignId == nil, let workspaceId {
            insertData["workspace_id"] = AnyCodable(workspaceId)
        }
        if let phone = lead.phone { insertData["phone"] = AnyCodable(phone) }
        if let email = lead.email { insertData["email"] = AnyCodable(email) }
        if let notes = lead.notes { insertData["notes"] = AnyCodable(notes) }
        if let qrCode = lead.qrCode { insertData["qr_code"] = AnyCodable(qrCode) }
        if let campaignId = lead.campaignId { insertData["campaign_id"] = AnyCodable(campaignId) }
        if let sessionId = lead.sessionId { insertData["session_id"] = AnyCodable(sessionId) }
        if let externalCrmId = lead.externalCrmId { insertData["external_crm_id"] = AnyCodable(externalCrmId) }
        if let lastSyncedAt = lead.lastSyncedAt { insertData["last_synced_at"] = AnyCodable(lastSyncedAt) }
        if let syncStatus = lead.syncStatus { insertData["sync_status"] = AnyCodable(syncStatus.rawValue) }

        let response = try await client
            .from("contacts")
            .insert(insertData)
            .select("id,user_id,full_name,phone,email,address,status,notes,qr_code,campaign_id,session_id,external_crm_id,last_synced_at,sync_status,created_at,updated_at")
            .execute()

        let rows = try JSONDecoder.supabaseDates.decode([ContactLeadRow].self, from: response.data)
        guard let inserted = rows.first else {
            throw NSError(domain: "FieldLeadsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert contact lead"])
        }
        return Self.makeFieldLead(from: inserted)
    }

    private func updateContactLead(_ lead: FieldLead) async throws -> FieldLead? {
        var updateData: [String: AnyCodable] = [
            "full_name": AnyCodable(Self.contactFullName(from: lead.name)),
            "address": AnyCodable(lead.address),
            "status": AnyCodable(lead.status.rawValue),
            "updated_at": AnyCodable(Date())
        ]
        updateData["phone"] = AnyCodable(lead.phone as Any)
        updateData["email"] = AnyCodable(lead.email as Any)
        updateData["notes"] = AnyCodable(lead.notes as Any)
        updateData["qr_code"] = AnyCodable(lead.qrCode as Any)
        updateData["campaign_id"] = AnyCodable(lead.campaignId as Any)
        updateData["session_id"] = AnyCodable(lead.sessionId as Any)
        updateData["external_crm_id"] = AnyCodable(lead.externalCrmId as Any)
        updateData["last_synced_at"] = AnyCodable(lead.lastSyncedAt as Any)
        updateData["sync_status"] = AnyCodable(lead.syncStatus?.rawValue as Any)

        let response = try await client
            .from("contacts")
            .update(updateData)
            .eq("id", value: lead.id)
            .select("id,user_id,full_name,phone,email,address,status,notes,qr_code,campaign_id,session_id,external_crm_id,last_synced_at,sync_status,created_at,updated_at")
            .execute()

        let rows = try JSONDecoder.supabaseDates.decode([ContactLeadRow].self, from: response.data)
        return rows.first.map(Self.makeFieldLead(from:))
    }

    // MARK: - Legacy Fallback

    private func fetchLegacyLeads(
        userId: UUID,
        workspaceId: UUID?,
        campaignId: UUID?,
        sessionId: UUID?
    ) async throws -> [FieldLead] {
        var query = client
            .from("field_leads")
            .select()
        if shouldUseWorkspaceScope(workspaceId: workspaceId, campaignId: campaignId),
           let workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        } else if campaignId == nil {
            query = query.eq("user_id", value: userId)
        }
        if let campaignId {
            query = query.eq("campaign_id", value: campaignId)
        }
        if let sessionId {
            query = query.eq("session_id", value: sessionId)
        }

        let response: [FieldLead] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value

        return response
    }

    private func insertLegacyLead(_ lead: FieldLead, workspaceId: UUID?) async throws -> FieldLead {
        if let existing = try await findExistingLegacyLead(matching: lead, workspaceId: workspaceId) {
            let merged = Self.mergedLead(existing: existing, incoming: lead)
            let updated = try await updateLegacyLead(merged)

            Task.detached(priority: .utility) {
                let leadModel = LeadModel(from: updated)
                await LeadSyncManager.shared.syncLeadToCRM(
                    lead: leadModel,
                    userId: updated.userId,
                    trackFieldLeadCRMStatus: true
                )
            }

            return updated
        }

        var insertData: [String: AnyCodable] = [
            "id": AnyCodable(lead.id),
            "user_id": AnyCodable(lead.userId),
            "address": AnyCodable(lead.address),
            "status": AnyCodable(lead.status.rawValue),
            "created_at": AnyCodable(lead.createdAt),
            "updated_at": AnyCodable(lead.updatedAt)
        ]
        if lead.campaignId == nil, let workspaceId {
            insertData["workspace_id"] = AnyCodable(workspaceId)
        }
        if let name = lead.name { insertData["name"] = AnyCodable(name) }
        if let phone = lead.phone { insertData["phone"] = AnyCodable(phone) }
        if let email = lead.email { insertData["email"] = AnyCodable(email) }
        if let notes = lead.notes { insertData["notes"] = AnyCodable(notes) }
        if let qrCode = lead.qrCode { insertData["qr_code"] = AnyCodable(qrCode) }
        if let campaignId = lead.campaignId { insertData["campaign_id"] = AnyCodable(campaignId) }
        if let sessionId = lead.sessionId { insertData["session_id"] = AnyCodable(sessionId) }
        if let externalCrmId = lead.externalCrmId { insertData["external_crm_id"] = AnyCodable(externalCrmId) }
        if let lastSyncedAt = lead.lastSyncedAt { insertData["last_synced_at"] = AnyCodable(lastSyncedAt) }
        if let syncStatus = lead.syncStatus { insertData["sync_status"] = AnyCodable(syncStatus.rawValue) }

        let response: [FieldLead] = try await client
            .from("field_leads")
            .insert(insertData)
            .select()
            .execute()
            .value

        guard let inserted = response.first else {
            throw NSError(domain: "FieldLeadsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to insert field lead"])
        }

        Task.detached(priority: .utility) {
            let leadModel = LeadModel(from: inserted)
            await LeadSyncManager.shared.syncLeadToCRM(
                lead: leadModel,
                userId: inserted.userId,
                trackFieldLeadCRMStatus: true
            )
        }

        return inserted
    }

    private func findExistingLegacyLead(
        matching lead: FieldLead,
        workspaceId: UUID?
    ) async throws -> FieldLead? {
        var query = client
            .from("field_leads")
            .select()
            .eq("address", value: lead.address)

        if shouldUseWorkspaceScope(workspaceId: workspaceId, campaignId: lead.campaignId),
           let workspaceId {
            query = query.eq("workspace_id", value: workspaceId)
        } else if lead.campaignId == nil {
            query = query.eq("user_id", value: lead.userId)
        }
        if let campaignId = lead.campaignId {
            query = query.eq("campaign_id", value: campaignId)
        }
        if let sessionId = lead.sessionId {
            query = query.eq("session_id", value: sessionId)
        }

        let rows: [FieldLead] = try await query
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func updateLegacyLead(_ lead: FieldLead) async throws -> FieldLead {
        var updateData: [String: AnyCodable] = [
            "address": AnyCodable(lead.address),
            "status": AnyCodable(lead.status.rawValue),
            "updated_at": AnyCodable(Date())
        ]
        updateData["name"] = AnyCodable(lead.name as Any)
        updateData["phone"] = AnyCodable(lead.phone as Any)
        updateData["email"] = AnyCodable(lead.email as Any)
        updateData["notes"] = AnyCodable(lead.notes as Any)
        updateData["qr_code"] = AnyCodable(lead.qrCode as Any)
        updateData["campaign_id"] = AnyCodable(lead.campaignId as Any)
        updateData["session_id"] = AnyCodable(lead.sessionId as Any)
        updateData["external_crm_id"] = AnyCodable(lead.externalCrmId as Any)
        updateData["last_synced_at"] = AnyCodable(lead.lastSyncedAt as Any)
        updateData["sync_status"] = AnyCodable(lead.syncStatus?.rawValue as Any)

        let response: [FieldLead] = try await client
            .from("field_leads")
            .update(updateData)
            .eq("id", value: lead.id)
            .select()
            .execute()
            .value

        guard let updated = response.first else {
            throw NSError(domain: "FieldLeadsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update field lead"])
        }
        return updated
    }

    private static func makeFieldLead(from row: ContactLeadRow) -> FieldLead {
        FieldLead(
            id: row.id,
            userId: row.userId,
            address: row.address,
            name: normalizedDisplayName(row.fullName),
            phone: row.phone,
            email: row.email,
            status: fieldLeadStatus(from: row.status),
            notes: row.notes,
            qrCode: row.qrCode,
            campaignId: row.campaignId,
            sessionId: row.sessionId,
            externalCrmId: row.externalCrmId,
            lastSyncedAt: row.lastSyncedAt,
            syncStatus: row.syncStatus.flatMap(FieldLeadSyncStatus.init(rawValue:)),
            createdAt: row.createdAt,
            updatedAt: row.updatedAt
        )
    }

    private static func makeFieldLead(from contact: Contact, userId: UUID) -> FieldLead {
        FieldLead(
            id: contact.id,
            userId: userId,
            address: contact.address,
            name: normalizedDisplayName(contact.fullName),
            phone: contact.phone,
            email: contact.email,
            status: fieldLeadStatus(from: contact.status.rawValue),
            notes: contact.notes,
            qrCode: nil,
            campaignId: contact.campaignId,
            sessionId: nil,
            externalCrmId: nil,
            lastSyncedAt: nil,
            syncStatus: nil,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt
        )
    }

    private static func makeContact(from lead: FieldLead) -> Contact {
        Contact(
            id: lead.id,
            fullName: contactFullName(from: lead.name),
            phone: lead.phone,
            email: lead.email,
            address: lead.address,
            campaignId: lead.campaignId,
            farmId: nil,
            gersId: nil,
            addressId: nil,
            tags: nil,
            status: contactStatus(from: lead.status),
            lastContacted: lead.lastSyncedAt,
            notes: lead.notes,
            reminderDate: nil,
            createdAt: lead.createdAt,
            updatedAt: lead.updatedAt
        )
    }

    private static func mergeLead(_ lead: FieldLead, with contact: Contact) -> FieldLead {
        var merged = lead
        merged.address = contact.address
        merged.name = normalizedDisplayName(contact.fullName)
        merged.phone = contact.phone
        merged.email = contact.email
        merged.notes = contact.notes
        merged.campaignId = contact.campaignId
        merged.status = fieldLeadStatus(from: contact.status.rawValue)
        merged.updatedAt = contact.updatedAt
        return merged
    }

    private static func fieldLeadStatus(from contactStatus: String) -> FieldLeadStatus {
        switch contactStatus.lowercased() {
        case FieldLeadStatus.interested.rawValue, "hot", "warm":
            return .interested
        case FieldLeadStatus.qrScanned.rawValue:
            return .qrScanned
        case FieldLeadStatus.noAnswer.rawValue, "cold":
            return .noAnswer
        case FieldLeadStatus.notHome.rawValue, "new":
            return .notHome
        default:
            return .interested
        }
    }

    private static func contactStatus(from leadStatus: FieldLeadStatus) -> ContactStatus {
        switch leadStatus {
        case .interested, .qrScanned:
            return .hot
        case .noAnswer:
            return .cold
        case .notHome:
            return .new
        }
    }

    private static func normalizedDisplayName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "lead", "new contact":
            return nil
        default:
            return trimmed
        }
    }

    private static func contactFullName(from raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Lead" : trimmed
    }

    private static func mergedLead(existing: FieldLead, incoming: FieldLead) -> FieldLead {
        var merged = existing
        merged.name = preferredNonEmpty(incoming.name, fallback: existing.name)
        merged.phone = preferredNonEmpty(incoming.phone, fallback: existing.phone)
        merged.email = preferredNonEmpty(incoming.email, fallback: existing.email)
        merged.notes = preferredNonEmpty(incoming.notes, fallback: existing.notes)
        merged.status = incoming.status
        merged.qrCode = preferredNonEmpty(incoming.qrCode, fallback: existing.qrCode)
        merged.campaignId = incoming.campaignId ?? existing.campaignId
        merged.sessionId = incoming.sessionId ?? existing.sessionId
        merged.updatedAt = Date()
        return merged
    }

    private static func deduplicated(_ leads: [FieldLead]) -> [FieldLead] {
        var bestByKey: [String: FieldLead] = [:]
        for lead in leads {
            let key = dedupeKey(for: lead)
            if let current = bestByKey[key] {
                if lead.updatedAt > current.updatedAt {
                    bestByKey[key] = lead
                }
            } else {
                bestByKey[key] = lead
            }
        }
        return bestByKey.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func dedupeKey(for lead: FieldLead) -> String {
        let address = lead.address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let campaign = lead.campaignId?.uuidString.lowercased() ?? "none"
        return "\(address)|\(campaign)"
    }

    private static func preferredNonEmpty(_ primary: String?, fallback: String?) -> String? {
        let trimmedPrimary = primary?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = trimmedPrimary, !value.isEmpty {
            return value
        }
        let trimmedFallback = fallback?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = trimmedFallback, !value.isEmpty {
            return value
        }
        return nil
    }

    private func cacheLeadRows(_ rows: [ContactLeadRow], userId: UUID, workspaceId: UUID?) async {
        let contacts = rows.map { row in
            Contact(
                id: row.id,
                fullName: row.fullName,
                phone: row.phone,
                email: row.email,
                address: row.address,
                campaignId: row.campaignId,
                farmId: nil,
                gersId: nil,
                addressId: nil,
                tags: nil,
                status: Self.contactStatus(from: Self.fieldLeadStatus(from: row.status)),
                lastContacted: row.lastSyncedAt,
                notes: row.notes,
                reminderDate: nil,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
        }
        await contactRepository.upsertContacts(contacts, userId: userId, workspaceId: workspaceId, dirty: false, syncedAt: Date())
    }

    private func fetchCachedLeads(userId: UUID, workspaceId: UUID?, campaignId: UUID?) async -> [FieldLead] {
        let contacts = await contactRepository.fetchContacts(
            userId: userId,
            workspaceId: workspaceId,
            filter: ContactFilter(campaignId: campaignId)
        )
        return Self.deduplicated(contacts.map { Self.makeFieldLead(from: $0, userId: userId) })
    }

    private func isOffline() async -> Bool {
        await MainActor.run { !NetworkMonitor.shared.isOnline }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct ContactLeadRow: Decodable {
    let id: UUID
    let userId: UUID
    let fullName: String
    let phone: String?
    let email: String?
    let address: String
    let status: String
    let notes: String?
    let qrCode: String?
    let campaignId: UUID?
    let sessionId: UUID?
    let externalCrmId: String?
    let lastSyncedAt: Date?
    let syncStatus: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case phone
        case email
        case address
        case status
        case notes
        case qrCode = "qr_code"
        case campaignId = "campaign_id"
        case sessionId = "session_id"
        case externalCrmId = "external_crm_id"
        case lastSyncedAt = "last_synced_at"
        case syncStatus = "sync_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct DeletedLeadRow: Decodable {
    let id: UUID
}
