import Foundation
import Supabase

actor FarmTouchService {
    static let shared = FarmTouchService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch Touches
    
    func fetchTouches(farmId: UUID) async throws -> [FarmTouch] {
        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .select()
            .eq("farm_id", value: farmId)
            .order("date", ascending: true)
            .order("order_index", ascending: true)
            .execute()
            .value
        
        return response
    }
    
    func fetchTouch(id: UUID) async throws -> FarmTouch? {
        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Create Touch
    
    func createTouch(_ touch: FarmTouch) async throws -> FarmTouch {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var insertData: [String: AnyCodable] = [
            "farm_id": AnyCodable(touch.farmId.uuidString),
            "date": AnyCodable(dateFormatter.string(from: touch.date)),
            "type": AnyCodable(touch.type.rawValue),
            "title": AnyCodable(touch.title),
            "completed": AnyCodable(touch.completed)
        ]
        
        if let notes = touch.notes {
            insertData["notes"] = AnyCodable(notes)
        }
        
        if let orderIndex = touch.orderIndex {
            insertData["order_index"] = AnyCodable(orderIndex)
        }
        
        if let campaignId = touch.campaignId {
            insertData["campaign_id"] = AnyCodable(campaignId.uuidString)
        }
        
        if let batchId = touch.batchId {
            insertData["batch_id"] = AnyCodable(batchId.uuidString)
        }
        
        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .insert(insertData)
            .select()
            .execute()
            .value
        
        guard let inserted = response.first else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create touch"])
        }
        
        return inserted
    }
    
    // MARK: - Batch Create Touches
    
    func createTouches(_ touches: [FarmTouch]) async throws -> [FarmTouch] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let insertData: [[String: AnyCodable]] = touches.map { touch in
            var data: [String: AnyCodable] = [
                "farm_id": AnyCodable(touch.farmId.uuidString),
                "date": AnyCodable(dateFormatter.string(from: touch.date)),
                "type": AnyCodable(touch.type.rawValue),
                "title": AnyCodable(touch.title),
                "completed": AnyCodable(touch.completed)
            ]
            
            if let notes = touch.notes {
                data["notes"] = AnyCodable(notes)
            }
            
            if let orderIndex = touch.orderIndex {
                data["order_index"] = AnyCodable(orderIndex)
            }
            
            if let campaignId = touch.campaignId {
                data["campaign_id"] = AnyCodable(campaignId.uuidString)
            }
            
            if let batchId = touch.batchId {
                data["batch_id"] = AnyCodable(batchId.uuidString)
            }
            
            return data
        }
        
        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .insert(insertData)
            .select()
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Update Touch
    
    func updateTouch(_ touch: FarmTouch) async throws -> FarmTouch {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var updateData: [String: AnyCodable] = [
            "date": AnyCodable(dateFormatter.string(from: touch.date)),
            "type": AnyCodable(touch.type.rawValue),
            "title": AnyCodable(touch.title),
            "completed": AnyCodable(touch.completed)
        ]
        
        if let notes = touch.notes {
            updateData["notes"] = AnyCodable(notes)
        } else {
            updateData["notes"] = AnyCodable(NSNull())
        }
        
        if let orderIndex = touch.orderIndex {
            updateData["order_index"] = AnyCodable(orderIndex)
        }
        
        if let campaignId = touch.campaignId {
            updateData["campaign_id"] = AnyCodable(campaignId.uuidString)
        } else {
            updateData["campaign_id"] = AnyCodable(NSNull())
        }
        
        if let batchId = touch.batchId {
            updateData["batch_id"] = AnyCodable(batchId.uuidString)
        } else {
            updateData["batch_id"] = AnyCodable(NSNull())
        }
        
        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .update(updateData)
            .eq("id", value: touch.id)
            .select()
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update touch"])
        }
        
        return updated
    }
    
    // MARK: - Mark Complete
    
    func markComplete(touchId: UUID, completed: Bool) async throws -> FarmTouch {
        let updateData: [String: AnyCodable] = [
            "completed": AnyCodable(completed)
        ]
        
        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .update(updateData)
            .eq("id", value: touchId)
            .select()
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update touch"])
        }
        
        return updated
    }
    
    // MARK: - Delete Touch
    
    func deleteTouch(id: UUID) async throws {
        try await client
            .from("farm_touches")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}



