import Foundation
import Supabase

actor FarmLeadService {
    static let shared = FarmLeadService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    private let offlineRepository = FarmOfflineRepository.shared
    private let outboxRepository = OutboxRepository.shared
    
    private init() {}
    
    // MARK: - Fetch Leads
    
    func fetchLeads(farmId: UUID) async throws -> [FarmLead] {
        if !NetworkMonitor.shared.isOnline {
            return await offlineRepository.getCachedLeads(farmId: farmId)
        }

        let response: [FarmLead] = try await client
            .from("farm_leads")
            .select()
            .eq("farm_id", value: farmId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        await offlineRepository.upsertLeads(response)
        return response
    }
    
    func fetchLeadsByTouch(touchId: UUID) async throws -> [FarmLead] {
        if !NetworkMonitor.shared.isOnline {
            return await offlineRepository.getCachedLeads(touchId: touchId)
        }

        let response: [FarmLead] = try await client
            .from("farm_leads")
            .select()
            .eq("touch_id", value: touchId)
            .order("created_at", ascending: false)
            .execute()
            .value

        await offlineRepository.upsertLeads(response, dirty: false, syncedAt: Date())
        return response
    }
    
    func fetchLead(id: UUID) async throws -> FarmLead? {
        if !NetworkMonitor.shared.isOnline {
            return await offlineRepository.getCachedLead(id: id)
        }

        let response: [FarmLead] = try await client
            .from("farm_leads")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        if let lead = response.first {
            await offlineRepository.upsertLeads([lead], dirty: false, syncedAt: Date())
            return lead
        }
        return nil
    }
    
    // MARK: - Add Lead
    
    func addLead(_ lead: FarmLead) async throws -> FarmLead {
        await offlineRepository.upsertLeads([lead], dirty: true, syncedAt: nil)

        guard NetworkMonitor.shared.isOnline else {
            await enqueueLead(lead, operation: .createFarmLead)
            return lead
        }

        do {
            let inserted = try await performRemoteAddLead(lead)
            await offlineRepository.markLeadSynced(id: inserted.id, lead: inserted)

            // Sync to CRM integrations (non-blocking)
            Task.detached(priority: .utility) {
                if let farm = try? await FarmService.shared.fetchFarm(id: inserted.farmId) {
                    let leadModel = LeadModel(from: inserted)
                    await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: farm.userId)
                }
            }

            return inserted
        } catch {
            await enqueueLead(lead, operation: .createFarmLead)
            return lead
        }
    }

    func performRemoteAddLead(_ lead: FarmLead) async throws -> FarmLead {
        var insertData: [String: AnyCodable] = [
            "id": AnyCodable(lead.id.uuidString),
            "farm_id": AnyCodable(lead.farmId.uuidString),
            "lead_source": AnyCodable(lead.leadSource.rawValue)
        ]
        
        if let touchId = lead.touchId {
            insertData["touch_id"] = AnyCodable(touchId.uuidString)
        }
        
        if let name = lead.name {
            insertData["name"] = AnyCodable(name)
        }
        
        if let phone = lead.phone {
            insertData["phone"] = AnyCodable(phone)
        }
        
        if let email = lead.email {
            insertData["email"] = AnyCodable(email)
        }
        
        if let address = lead.address {
            insertData["address"] = AnyCodable(address)
        }
        
        let response: [FarmLead] = try await client
            .from("farm_leads")
            .insert(insertData)
            .select()
            .execute()
            .value
        
        guard let inserted = response.first else {
            throw NSError(domain: "FarmLeadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to add lead"])
        }
        
        return inserted
    }
    
    // MARK: - Link Lead to Touch
    
    func linkLeadToTouch(leadId: UUID, touchId: UUID) async throws -> FarmLead {
        guard let current = try await fetchLead(id: leadId) else {
            throw NSError(domain: "FarmLeadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Lead is not available offline"])
        }

        let updated = FarmLead(
            id: current.id,
            farmId: current.farmId,
            touchId: touchId,
            leadSource: current.leadSource,
            name: current.name,
            phone: current.phone,
            email: current.email,
            address: current.address,
            createdAt: current.createdAt
        )

        return try await updateLead(updated)
    }
    
    // MARK: - Update Lead
    
    func updateLead(_ lead: FarmLead) async throws -> FarmLead {
        await offlineRepository.upsertLeads([lead], dirty: true, syncedAt: nil)

        guard NetworkMonitor.shared.isOnline else {
            await enqueueLead(lead, operation: .updateFarmLead)
            return lead
        }

        do {
            let updated = try await performRemoteUpdateLead(lead)
            await offlineRepository.markLeadSynced(id: updated.id, lead: updated)
            return updated
        } catch {
            await enqueueLead(lead, operation: .updateFarmLead)
            return lead
        }
    }

    func performRemoteUpdateLead(_ lead: FarmLead) async throws -> FarmLead {
        var updateData: [String: AnyCodable] = [
            "lead_source": AnyCodable(lead.leadSource.rawValue)
        ]
        
        if let touchId = lead.touchId {
            updateData["touch_id"] = AnyCodable(touchId.uuidString)
        } else {
            updateData["touch_id"] = AnyCodable(NSNull())
        }
        
        if let name = lead.name {
            updateData["name"] = AnyCodable(name)
        } else {
            updateData["name"] = AnyCodable(NSNull())
        }
        
        if let phone = lead.phone {
            updateData["phone"] = AnyCodable(phone)
        } else {
            updateData["phone"] = AnyCodable(NSNull())
        }
        
        if let email = lead.email {
            updateData["email"] = AnyCodable(email)
        } else {
            updateData["email"] = AnyCodable(NSNull())
        }
        
        if let address = lead.address {
            updateData["address"] = AnyCodable(address)
        } else {
            updateData["address"] = AnyCodable(NSNull())
        }
        
        let response: [FarmLead] = try await client
            .from("farm_leads")
            .update(updateData)
            .eq("id", value: lead.id)
            .select()
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmLeadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update lead"])
        }
        
        return updated
    }
    
    // MARK: - Delete Lead
    
    func deleteLead(id: UUID) async throws {
        await offlineRepository.deleteCachedLead(id: id)

        guard NetworkMonitor.shared.isOnline else {
            await enqueueDeleteLead(id: id)
            return
        }

        do {
            try await performRemoteDeleteLead(id: id)
        } catch {
            await enqueueDeleteLead(id: id)
        }
    }

    func performRemoteDeleteLead(id: UUID) async throws {
        try await client
            .from("farm_leads")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    private func enqueueLead(_ lead: FarmLead, operation: OutboxOperation) async {
        await outboxRepository.enqueue(
            entityType: "farm_lead",
            entityId: lead.id.uuidString,
            operation: operation,
            payload: FarmLeadOutboxPayload(lead: lead),
            dependencyKey: "farm_lead:\(lead.id.uuidString.lowercased())"
        )
    }

    private func enqueueDeleteLead(id: UUID) async {
        await outboxRepository.enqueue(
            entityType: "farm_lead",
            entityId: id.uuidString,
            operation: .deleteFarmLead,
            payload: DeleteFarmLeadOutboxPayload(leadId: id.uuidString),
            dependencyKey: "farm_lead:\(id.uuidString.lowercased())"
        )
    }
}
