import Foundation
import Supabase

actor FarmTouchService {
    static let shared = FarmTouchService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}

    private func isMissingExecutionColumnError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("phase_id")
            || message.contains("session_id")
            || message.contains("completed_at")
            || message.contains("completed_by_user_id")
            || message.contains("execution_metrics")
    }
    
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

        if let phaseId = touch.phaseId {
            insertData["phase_id"] = AnyCodable(phaseId.uuidString)
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

        if let phaseId = touch.phaseId {
            updateData["phase_id"] = AnyCodable(phaseId.uuidString)
        } else {
            updateData["phase_id"] = AnyCodable(NSNull())
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

        if let sessionId = touch.sessionId {
            updateData["session_id"] = AnyCodable(sessionId.uuidString)
        } else {
            updateData["session_id"] = AnyCodable(NSNull())
        }

        if let completedAt = touch.completedAt {
            updateData["completed_at"] = AnyCodable(ISO8601DateFormatter().string(from: completedAt))
        } else {
            updateData["completed_at"] = AnyCodable(NSNull())
        }

        if let completedByUserId = touch.completedByUserId {
            updateData["completed_by_user_id"] = AnyCodable(completedByUserId.uuidString)
        } else {
            updateData["completed_by_user_id"] = AnyCodable(NSNull())
        }

        if let executionMetrics = touch.executionMetrics {
            updateData["execution_metrics"] = AnyCodable(executionMetrics)
        } else {
            updateData["execution_metrics"] = AnyCodable(NSNull())
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
        var updateData: [String: AnyCodable] = [
            "completed": AnyCodable(completed)
        ]
        updateData["completed_at"] = completed
            ? AnyCodable(ISO8601DateFormatter().string(from: Date()))
            : AnyCodable(NSNull())

        let response: [FarmTouch]
        do {
            response = try await client
                .from("farm_touches")
                .update(updateData)
                .eq("id", value: touchId)
                .select()
                .execute()
                .value
        } catch {
            guard isMissingExecutionColumnError(error) else {
                throw error
            }

            response = try await client
                .from("farm_touches")
                .update([
                    "completed": AnyCodable(completed)
                ])
                .eq("id", value: touchId)
                .select()
                .execute()
                .value
        }
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update touch"])
        }
        
        return updated
    }

    func markExecuted(
        touchId: UUID,
        phaseId: UUID?,
        sessionId: UUID,
        completedByUserId: UUID,
        completedAt: Date,
        metrics: [String: AnyCodable]
    ) async throws -> FarmTouch {
        let executedAt = ISO8601DateFormatter().string(from: completedAt)
        var updateData: [String: AnyCodable] = [
            "completed": AnyCodable(true),
            "session_id": AnyCodable(sessionId.uuidString),
            "completed_by_user_id": AnyCodable(completedByUserId.uuidString),
            "completed_at": AnyCodable(executedAt),
            "execution_metrics": AnyCodable(metrics)
        ]
        if let phaseId {
            updateData["phase_id"] = AnyCodable(phaseId.uuidString)
        }

        let response: [FarmTouch]
        do {
            response = try await client
                .from("farm_touches")
                .update(updateData)
                .eq("id", value: touchId)
                .select()
                .execute()
                .value
        } catch {
            guard isMissingExecutionColumnError(error) else {
                throw error
            }

            response = try await client
                .from("farm_touches")
                .update([
                    "completed": AnyCodable(true)
                ])
                .eq("id", value: touchId)
                .select()
                .execute()
                .value
        }

        guard let updated = response.first else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to mark touch executed"])
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


