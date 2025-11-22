import Foundation
import Supabase

actor FarmLeadService {
    static let shared = FarmLeadService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch Leads
    
    func fetchLeads(farmId: UUID) async throws -> [FarmLead] {
        let response: [FarmLead] = try await client
            .from("farm_leads")
            .select()
            .eq("farm_id", value: farmId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    func fetchLeadsByTouch(touchId: UUID) async throws -> [FarmLead] {
        let response: [FarmLead] = try await client
            .from("farm_leads")
            .select()
            .eq("touch_id", value: touchId)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return response
    }
    
    func fetchLead(id: UUID) async throws -> FarmLead? {
        let response: [FarmLead] = try await client
            .from("farm_leads")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Add Lead
    
    func addLead(_ lead: FarmLead) async throws -> FarmLead {
        var insertData: [String: AnyCodable] = [
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
        
        // Sync to CRM integrations (non-blocking)
        Task.detached(priority: .utility) {
            // Get farm owner ID for sync
            if let farm = try? await FarmService.shared.fetchFarm(id: inserted.farmId) {
                let leadModel = LeadModel(from: inserted)
                await LeadSyncManager.shared.syncLeadToCRM(lead: leadModel, userId: farm.userId)
            }
        }
        
        return inserted
    }
    
    // MARK: - Link Lead to Touch
    
    func linkLeadToTouch(leadId: UUID, touchId: UUID) async throws -> FarmLead {
        let updateData: [String: AnyCodable] = [
            "touch_id": AnyCodable(touchId.uuidString)
        ]
        
        let response: [FarmLead] = try await client
            .from("farm_leads")
            .update(updateData)
            .eq("id", value: leadId)
            .select()
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmLeadService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to link lead"])
        }
        
        return updated
    }
    
    // MARK: - Update Lead
    
    func updateLead(_ lead: FarmLead) async throws -> FarmLead {
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
        try await client
            .from("farm_leads")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}


