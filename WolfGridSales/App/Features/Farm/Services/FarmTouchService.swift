import Foundation
import Supabase

actor FarmTouchService {
    static let shared = FarmTouchService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    private let farmService = FarmService.shared
    private let offlineRepository = FarmOfflineRepository.shared
    private let outboxRepository = OutboxRepository.shared
    private var touchModeColumnAvailable: Bool?
    
    private init() {}

    private func isMissingExecutionColumnError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("cycle_number")
            || message.contains("session_id")
            || message.contains("completed_at")
            || message.contains("completed_by_user_id")
            || message.contains("execution_metrics")
    }

    private func isMissingModeColumnError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("mode")
            && (message.contains("column")
                || message.contains("schema cache")
                || message.contains("could not find"))
    }

    private func resolvedCycleNumber(for touch: FarmTouch) async throws -> Int? {
        if let cycleNumber = touch.cycleNumber {
            return cycleNumber
        }

        guard let farm = try await farmService.fetchFarm(id: touch.farmId) else {
            return nil
        }

        let existingTouches = try await fetchTouches(farmId: touch.farmId)
        let siblingTouches = existingTouches.filter { $0.id != touch.id }
        return FarmCycleResolver.nextCycleNumber(
            existingTouches: siblingTouches,
            touchesPerInterval: max(1, farm.touchesPerInterval ?? farm.frequency)
        )
    }
    
    // MARK: - Fetch Touches
    
    func fetchTouches(farmId: UUID) async throws -> [FarmTouch] {
        if !NetworkMonitor.shared.isOnline {
            return await offlineRepository.getCachedTouches(farmId: farmId)
        }

        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .select()
            .eq("farm_id", value: farmId)
            .order("date", ascending: true)
            .order("order_index", ascending: true)
            .execute()
            .value
        
        await offlineRepository.upsertTouches(response, dirty: false, syncedAt: Date())
        return response
    }
    
    func fetchTouch(id: UUID) async throws -> FarmTouch? {
        if !NetworkMonitor.shared.isOnline {
            return await offlineRepository.getCachedTouch(id: id)
        }

        let response: [FarmTouch] = try await client
            .from("farm_touches")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        
        if let touch = response.first {
            await offlineRepository.upsertTouches([touch], dirty: false, syncedAt: Date())
            return touch
        }
        return nil
    }

    func ensureTouchForCycle(
        farmId: UUID,
        cycleNumber: Int,
        campaignId: UUID,
        touchType: FarmTouchType,
        title: String,
        date: Date
    ) async throws -> FarmTouch {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        do {
            let response = try await client
                .rpc(
                    "ensure_farm_touch_for_cycle",
                    params: [
                        "p_farm_id": AnyCodable(farmId),
                        "p_cycle_number": AnyCodable(cycleNumber),
                        "p_campaign_id": AnyCodable(campaignId),
                        "p_touch_type": AnyCodable(touchType.rawValue),
                        "p_touch_title": AnyCodable(title),
                        "p_touch_date": AnyCodable(dateFormatter.string(from: date))
                    ]
                )
                .execute()

            return try JSONDecoder.supabaseDates.decode(FarmTouch.self, from: response.data)
        } catch {
            let existingTouches = try await fetchTouches(farmId: farmId)
            if let exactMatch = existingTouches.first(where: {
                $0.cycleNumber == cycleNumber && $0.campaignId == campaignId
            }) {
                return exactMatch
            }
            throw error
        }
    }
    
    // MARK: - Create Touch
    
    func createTouch(_ touch: FarmTouch) async throws -> FarmTouch {
        let touchToCreate = try await touchWithResolvedCycleNumber(touch)
        if !NetworkMonitor.shared.isOnline {
            await cacheAndQueueCreateTouch(touchToCreate)
            return touchToCreate
        }

        let inserted = try await performRemoteCreateTouch(touchToCreate)
        await offlineRepository.upsertTouches([inserted], dirty: false, syncedAt: Date())
        return inserted
    }

    func performRemoteCreateTouch(_ touch: FarmTouch) async throws -> FarmTouch {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        func makeInsertData(includeMode: Bool) -> [String: AnyCodable] {
            var data: [String: AnyCodable] = [
                "id": AnyCodable(touch.id.uuidString),
                "farm_id": AnyCodable(touch.farmId.uuidString),
                "date": AnyCodable(dateFormatter.string(from: touch.date)),
                "type": AnyCodable(touch.type.rawValue),
                "title": AnyCodable(touch.title),
                "completed": AnyCodable(touch.completed)
            ]

            if includeMode {
                data["mode"] = AnyCodable(touch.effectiveModeRawValue)
            }

            if let notes = touch.notes {
                data["notes"] = AnyCodable(notes)
            }

            if let cycleNumber = touch.cycleNumber {
                data["cycle_number"] = AnyCodable(cycleNumber)
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

        func insert(includeMode: Bool) async throws -> FarmTouch {
            let response: [FarmTouch] = try await client
                .from("farm_touches")
                .insert(makeInsertData(includeMode: includeMode))
                .select()
                .execute()
                .value

            guard let inserted = response.first else {
                throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create touch"])
            }

            return inserted
        }

        let includeMode = touchModeColumnAvailable ?? true
        do {
            let inserted = try await insert(includeMode: includeMode)
            touchModeColumnAvailable = includeMode
            return inserted
        } catch {
            guard includeMode, isMissingModeColumnError(error) else {
                throw error
            }
            touchModeColumnAvailable = false
            return try await insert(includeMode: false)
        }

    }
    
    // MARK: - Batch Create Touches
    
    func createTouches(_ touches: [FarmTouch]) async throws -> [FarmTouch] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        func makeInsertData(includeMode: Bool) -> [[String: AnyCodable]] {
            touches.map { touch in
                var data: [String: AnyCodable] = [
                    "farm_id": AnyCodable(touch.farmId.uuidString),
                    "date": AnyCodable(dateFormatter.string(from: touch.date)),
                    "type": AnyCodable(touch.type.rawValue),
                    "title": AnyCodable(touch.title),
                    "completed": AnyCodable(touch.completed)
                ]

                if includeMode {
                    data["mode"] = AnyCodable(touch.effectiveModeRawValue)
                }

                if let notes = touch.notes {
                    data["notes"] = AnyCodable(notes)
                }

                if let cycleNumber = touch.cycleNumber {
                    data["cycle_number"] = AnyCodable(cycleNumber)
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
        }

        func insert(includeMode: Bool) async throws -> [FarmTouch] {
            try await client
                .from("farm_touches")
                .insert(makeInsertData(includeMode: includeMode))
                .select()
                .execute()
                .value
        }

        let includeMode = touchModeColumnAvailable ?? true
        do {
            let response = try await insert(includeMode: includeMode)
            touchModeColumnAvailable = includeMode
            return response
        } catch {
            guard includeMode, isMissingModeColumnError(error) else {
                throw error
            }
            touchModeColumnAvailable = false
            return try await insert(includeMode: false)
        }
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

        if let cycleNumber = touch.cycleNumber {
            updateData["cycle_number"] = AnyCodable(cycleNumber)
        } else {
            updateData["cycle_number"] = AnyCodable(NSNull())
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
        func update(includeMode: Bool) async throws -> FarmTouch {
            var payload = updateData
            if includeMode {
                payload["mode"] = AnyCodable(touch.effectiveModeRawValue)
            }

            let response: [FarmTouch] = try await client
                .from("farm_touches")
                .update(payload)
                .eq("id", value: touch.id)
                .select()
                .execute()
                .value

            guard let updated = response.first else {
                throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update touch"])
            }

            return updated
        }

        let includeMode = touchModeColumnAvailable ?? true
        do {
            let updated = try await update(includeMode: includeMode)
            touchModeColumnAvailable = includeMode
            return updated
        } catch {
            guard includeMode, isMissingModeColumnError(error) else {
                throw error
            }
            touchModeColumnAvailable = false
            return try await update(includeMode: false)
        }
    }
    
    // MARK: - Mark Complete
    
    func markComplete(touchId: UUID, completed: Bool) async throws -> FarmTouch {
        if !NetworkMonitor.shared.isOnline {
            let updated = try await locallyMarkComplete(touchId: touchId, completed: completed, completedAt: completed ? Date() : nil)
            await outboxRepository.enqueue(
                entityType: "farm_touch",
                entityId: touchId.uuidString,
                operation: .markFarmTouchComplete,
                payload: FarmTouchCompleteOutboxPayload(
                    touchId: touchId.uuidString,
                    completed: completed,
                    completedAt: updated.completedAt.map(OfflineDateCodec.string(from:))
                ),
                dependencyKey: "farm_touch:\(touchId.uuidString.lowercased())"
            )
            return updated
        }

        let updated = try await performRemoteMarkComplete(touchId: touchId, completed: completed, completedAt: completed ? Date() : nil)
        await offlineRepository.upsertTouches([updated], dirty: false, syncedAt: Date())
        return updated
    }

    func performRemoteMarkComplete(touchId: UUID, completed: Bool, completedAt: Date?) async throws -> FarmTouch {
        var updateData: [String: AnyCodable] = [
            "completed": AnyCodable(completed)
        ]
        if let completedAt {
            updateData["completed_at"] = AnyCodable(ISO8601DateFormatter().string(from: completedAt))
        } else {
            updateData["completed_at"] = AnyCodable(NSNull())
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
        cycleNumber: Int?,
        sessionId: UUID,
        completedByUserId: UUID,
        completedAt: Date,
        metrics: [String: AnyCodable]
    ) async throws -> FarmTouch {
        if !NetworkMonitor.shared.isOnline {
            let updated = try await locallyMarkExecuted(
                touchId: touchId,
                cycleNumber: cycleNumber,
                sessionId: sessionId,
                completedByUserId: completedByUserId,
                completedAt: completedAt,
                metrics: metrics
            )
            await outboxRepository.enqueue(
                entityType: "farm_touch",
                entityId: touchId.uuidString,
                operation: .markFarmTouchExecuted,
                payload: FarmTouchExecutedOutboxPayload(
                    touchId: touchId.uuidString,
                    cycleNumber: cycleNumber,
                    sessionId: sessionId.uuidString,
                    completedByUserId: completedByUserId.uuidString,
                    completedAt: OfflineDateCodec.string(from: completedAt),
                    metrics: metrics
                ),
                dependencyKey: "farm_touch:\(touchId.uuidString.lowercased())"
            )
            return updated
        }

        let updated = try await performRemoteMarkExecuted(
            touchId: touchId,
            cycleNumber: cycleNumber,
            sessionId: sessionId,
            completedByUserId: completedByUserId,
            completedAt: completedAt,
            metrics: metrics
        )
        await offlineRepository.upsertTouches([updated], dirty: false, syncedAt: Date())
        return updated
    }

    func performRemoteMarkExecuted(
        touchId: UUID,
        cycleNumber: Int?,
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
        if let cycleNumber {
            updateData["cycle_number"] = AnyCodable(cycleNumber)
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

    private func touchWithResolvedCycleNumber(_ touch: FarmTouch) async throws -> FarmTouch {
        guard touch.cycleNumber == nil,
              let cycleNumber = try await resolvedCycleNumber(for: touch) else {
            return touch
        }

        return FarmTouch(
            id: touch.id,
            farmId: touch.farmId,
            cycleNumber: cycleNumber,
            date: touch.date,
            type: touch.type,
            mode: touch.mode,
            title: touch.title,
            notes: touch.notes,
            orderIndex: touch.orderIndex,
            completed: touch.completed,
            campaignId: touch.campaignId,
            batchId: touch.batchId,
            sessionId: touch.sessionId,
            completedAt: touch.completedAt,
            completedByUserId: touch.completedByUserId,
            executionMetrics: touch.executionMetrics,
            createdAt: touch.createdAt
        )
    }

    private func cacheAndQueueCreateTouch(_ touch: FarmTouch) async {
        await offlineRepository.upsertTouches([touch], dirty: true, syncedAt: nil)
        await outboxRepository.enqueue(
            entityType: "farm_touch",
            entityId: touch.id.uuidString,
            operation: .createFarmTouch,
            payload: FarmTouchOutboxPayload(touch: touch),
            dependencyKey: "farm_touch:\(touch.id.uuidString.lowercased())"
        )
    }

    private func locallyMarkComplete(
        touchId: UUID,
        completed: Bool,
        completedAt: Date?
    ) async throws -> FarmTouch {
        guard let current = await offlineRepository.getCachedTouch(id: touchId) else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Touch is not available offline"])
        }

        let updated = FarmTouch(
            id: current.id,
            farmId: current.farmId,
            cycleNumber: current.cycleNumber,
            date: current.date,
            type: current.type,
            mode: current.mode,
            title: current.title,
            notes: current.notes,
            orderIndex: current.orderIndex,
            completed: completed,
            campaignId: current.campaignId,
            batchId: current.batchId,
            sessionId: current.sessionId,
            completedAt: completedAt,
            completedByUserId: current.completedByUserId,
            executionMetrics: current.executionMetrics,
            createdAt: current.createdAt
        )
        await offlineRepository.upsertTouches([updated], dirty: true, syncedAt: nil)
        return updated
    }

    private func locallyMarkExecuted(
        touchId: UUID,
        cycleNumber: Int?,
        sessionId: UUID,
        completedByUserId: UUID,
        completedAt: Date,
        metrics: [String: AnyCodable]
    ) async throws -> FarmTouch {
        guard let current = await offlineRepository.getCachedTouch(id: touchId) else {
            throw NSError(domain: "FarmTouchService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Touch is not available offline"])
        }

        let updated = FarmTouch(
            id: current.id,
            farmId: current.farmId,
            cycleNumber: cycleNumber ?? current.cycleNumber,
            date: current.date,
            type: current.type,
            mode: current.mode,
            title: current.title,
            notes: current.notes,
            orderIndex: current.orderIndex,
            completed: true,
            campaignId: current.campaignId,
            batchId: current.batchId,
            sessionId: sessionId,
            completedAt: completedAt,
            completedByUserId: completedByUserId,
            executionMetrics: metrics,
            createdAt: current.createdAt
        )
        await offlineRepository.upsertTouches([updated], dirty: true, syncedAt: nil)
        return updated
    }
}
