import Foundation
import Supabase

actor FieldLeadsService {
    static let shared = FieldLeadsService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch
    
    func fetchLeads(userId: UUID, campaignId: UUID? = nil, sessionId: UUID? = nil) async throws -> [FieldLead] {
        var query = client
            .from("field_leads")
            .select()
            .eq("user_id", value: userId)
        
        if let campaignId = campaignId {
            query = query.eq("campaign_id", value: campaignId)
        }
        if let sessionId = sessionId {
            query = query.eq("session_id", value: sessionId)
        }
        
        let response: [FieldLead] = try await query
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Create
    
    func addLead(_ lead: FieldLead) async throws -> FieldLead {
        var insertData: [String: AnyCodable] = [
            "id": AnyCodable(lead.id),
            "user_id": AnyCodable(lead.userId),
            "address": AnyCodable(lead.address),
            "status": AnyCodable(lead.status.rawValue),
            "created_at": AnyCodable(lead.createdAt),
            "updated_at": AnyCodable(lead.updatedAt)
        ]
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

        // Sync to CRM integrations (non-blocking), same as FarmLeadService
        Task.detached(priority: .utility) {
            let leadModel = LeadModel(from: inserted)
            await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: inserted.userId)
        }

        return inserted
    }
    
    // MARK: - Update
    
    func updateLead(_ lead: FieldLead) async throws -> FieldLead {
        var updateData: [String: AnyCodable] = [
            "address": AnyCodable(lead.address),
            "status": AnyCodable(lead.status.rawValue),
            "updated_at": AnyCodable(Date())
        ]
        if let name = lead.name { updateData["name"] = AnyCodable(name) }
        if let phone = lead.phone { updateData["phone"] = AnyCodable(phone) }
        if let email = lead.email { updateData["email"] = AnyCodable(email) }
        if let notes = lead.notes { updateData["notes"] = AnyCodable(notes) }
        if let qrCode = lead.qrCode { updateData["qr_code"] = AnyCodable(qrCode) }
        if let campaignId = lead.campaignId { updateData["campaign_id"] = AnyCodable(campaignId) }
        if let sessionId = lead.sessionId { updateData["session_id"] = AnyCodable(sessionId) }
        if let externalCrmId = lead.externalCrmId { updateData["external_crm_id"] = AnyCodable(externalCrmId) }
        if let lastSyncedAt = lead.lastSyncedAt { updateData["last_synced_at"] = AnyCodable(lastSyncedAt) }
        if let syncStatus = lead.syncStatus { updateData["sync_status"] = AnyCodable(syncStatus.rawValue) }
        
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
    
    // MARK: - Delete
    
    func deleteLead(_ lead: FieldLead) async throws {
        try await client
            .from("field_leads")
            .delete()
            .eq("id", value: lead.id)
            .execute()
    }
}
