import Foundation
import CoreLocation
import Supabase

/// API for logging building visits/touches and updating campaign address visited status
final class VisitsAPI {
    static let shared = VisitsAPI()
    private init() {}
    
    private let client = SupabaseManager.shared.client
    private let pendingLock = NSLock()
    private var pendingTouches: [(addressId: UUID, campaignId: UUID, buildingId: String?, sessionId: UUID?)] = []
    private var pendingVisitedMarks: [UUID] = []
    private let statusFetchLock = NSLock()
    private var inFlightStatusFetches: [UUID: Task<[UUID: AddressStatusRow], Error>] = [:]
    private var lastStatusFetchAt: [UUID: Date] = [:]
    private var cachedStatuses: [UUID: [UUID: AddressStatusRow]] = [:]
    /// Short TTL so rapid map updates (buildings → addresses → route scope) reuse one response instead of re-hitting Supabase.
    private let statusFetchCooldownSeconds: TimeInterval = 12

    /// Clears in-memory status cache so the next `fetchStatuses` hits the network (used after writes).
    func invalidateStatusCache(campaignId: UUID) {
        synchronizedStatusState {
            cachedStatuses[campaignId] = nil
            lastStatusFetchAt[campaignId] = nil
        }
    }
    
    /// Log a building touch/visit event
    /// - Parameters:
    ///   - addressId: UUID of the campaign address (from campaign_addresses.id)
    ///   - campaignId: UUID of the campaign
    ///   - buildingId: Mapbox building ID (optional, may be nil for some buildings)
    ///   - sessionId: Current session ID (optional, nil if not tracking active session)
    func logBuildingTouch(
        addressId: UUID,
        campaignId: UUID,
        buildingId: String?,
        sessionId: UUID?
    ) {
        // Fire and forget - non-blocking async call
        Task {
            do {
                debugLog("🏗️ [VisitsAPI] Logging building touch")

                guard let user = try? await client.auth.session.user else {
                    debugLog("⚠️ [VisitsAPI] No authenticated user for building touch logging")
                    return
                }

                var touchData: [String: AnyCodable] = [
                    "user_id": AnyCodable(user.id.uuidString),
                    "address_id": AnyCodable(addressId.uuidString),
                    "campaign_id": AnyCodable(campaignId.uuidString),
                    "touched_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
                ]

                touchData["building_id"] = AnyCodable(buildingIdCodableValue(buildingId))

                if let sessionId = sessionId {
                    touchData["session_id"] = AnyCodable(sessionId.uuidString)
                } else {
                    touchData["session_id"] = AnyCodable(NSNull())
                }

                _ = try await client
                    .from("building_touches")
                    .insert(touchData)
                    .execute()

                debugLog("✅ [VisitsAPI] Building touch logged to database")
            } catch {
                // Log error but don't block user interaction
                enqueuePendingTouch(addressId: addressId, campaignId: campaignId, buildingId: buildingId, sessionId: sessionId)
                debugLog("⚠️ [VisitsAPI] Error logging building touch: \(error.localizedDescription)")
            }
        }
    }
    
    /// Mark a campaign address as visited
    /// - Parameter addressId: UUID of the campaign address (from campaign_addresses.id)
    func markAddressVisited(addressId: UUID) {
        // Fire and forget - non-blocking async update
        Task {
            do {
                debugLog("📍 [VisitsAPI] Marking address visited")
                
                // Update campaign_addresses.visited = true
                let updateData: [String: AnyCodable] = [
                    "visited": AnyCodable(true)
                ]
                
                _ = try await client
                    .from("campaign_addresses")
                    .update(updateData)
                    .eq("id", value: addressId.uuidString)
                    .execute()
                
                debugLog("✅ [VisitsAPI] Address marked as visited")
            } catch {
                // Log error but don't block user interaction
                enqueuePendingVisitedMark(addressId)
                debugLog("⚠️ [VisitsAPI] Error marking address as visited: \(error.localizedDescription)")
            }
        }
    }
    
    /// Fetch all address statuses for a campaign
    /// - Parameters:
    ///   - campaignId: UUID of the campaign
    ///   - forceRefresh: When true, skips the short cooldown cache and always fetches from the server.
    /// - Returns: Dictionary mapping address_id to AddressStatusRow
    func fetchStatuses(campaignId: UUID, forceRefresh: Bool = false) async throws -> [UUID: AddressStatusRow] {
        if let inFlight = synchronizedStatusState({ inFlightStatusFetches[campaignId] }) {
            return try await inFlight.value
        }

        if !forceRefresh,
           let cached = synchronizedStatusState({ () -> [UUID: AddressStatusRow]? in
            guard let lastFetch = lastStatusFetchAt[campaignId],
                  Date().timeIntervalSince(lastFetch) <= statusFetchCooldownSeconds else {
                return nil
            }
            return cachedStatuses[campaignId]
        }) {
            debugLog("📊 [VisitsAPI] Using cached statuses for campaign (cooldown)")
            return cached
        }

        let task = Task<[UUID: AddressStatusRow], Error> {
            debugLog("📊 [VisitsAPI] Fetching statuses for campaign")
            
            let response = try await client
                .from("address_statuses")
                .select()
                .eq("campaign_id", value: campaignId.uuidString)
                .execute()
            
            #if DEBUG
            let raw = String(data: response.data, encoding: .utf8) ?? ""
            let preview = String(raw.prefix(2048))
            print("[VisitsAPI DEBUG] address_statuses raw JSON (first 2KB): \(preview)\(raw.count > 2048 ? "…" : "")")
            #endif
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let rows: [AddressStatusRow] = try decoder.decode([AddressStatusRow].self, from: response.data)
            
            var statuses: [UUID: AddressStatusRow] = [:]
            for statusRow in rows {
                statuses[statusRow.addressId] = statusRow
            }
            
            synchronizedStatusState {
                cachedStatuses[campaignId] = statuses
                lastStatusFetchAt[campaignId] = Date()
            }
            debugLog("✅ [VisitsAPI] Fetched \(statuses.count) statuses for campaign")
            return statuses
        }

        synchronizedStatusState {
            inFlightStatusFetches[campaignId] = task
        }
        defer {
            synchronizedStatusState {
                inFlightStatusFetches[campaignId] = nil
            }
        }
        return try await task.value
    }
    
    /// Update or create address status
    /// - Parameters:
    ///   - addressId: UUID of the campaign address
    ///   - campaignId: UUID of the campaign
    ///   - status: New status value
    ///   - notes: Optional notes
    func updateStatus(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil
    ) async throws {
        debugLog("📝 [VisitsAPI] Updating status to \(status.rawValue)")

        let occurredAt = ISO8601DateFormatter().string(from: Date())
        var canonicalParams: [String: AnyCodable] = [
            "p_campaign_id": AnyCodable(campaignId),
            "p_campaign_address_id": AnyCodable(addressId),
            "p_address_id": AnyCodable(addressId),
            "p_status": AnyCodable(status.persistedRPCValue),
            "p_notes": AnyCodable(notes ?? ""),
            "p_occurred_at": AnyCodable(occurredAt)
        ]
        if let sessionId {
            canonicalParams["p_session_id"] = AnyCodable(sessionId)
        }
        if let sessionTargetId, !sessionTargetId.isEmpty {
            canonicalParams["p_session_target_id"] = AnyCodable(sessionTargetId)
        }
        if let sessionEventType {
            canonicalParams["p_session_event_type"] = AnyCodable(sessionEventType.rawValue)
        }
        if let location {
            canonicalParams["p_lat"] = AnyCodable(location.coordinate.latitude)
            canonicalParams["p_lon"] = AnyCodable(location.coordinate.longitude)
        }

        do {
            _ = try await client
                .rpc("record_campaign_address_outcome", params: canonicalParams)
                .execute()
        } catch {
            let fallbackReasonMissingRPC = isMissingFunction(error, functionName: "record_campaign_address_outcome")
            let fallbackReasonCampaignIDNotNull = isCampaignIDNotNullViolation(error)
            guard fallbackReasonMissingRPC || fallbackReasonCampaignIDNotNull else {
                throw error
            }

            if fallbackReasonCampaignIDNotNull {
                debugLog("⚠️ [VisitsAPI] record_campaign_address_outcome failed campaign_id not-null despite app sending campaign_id=\(campaignId.uuidString); falling back to upsert_address_status")
            } else {
                debugLog("ℹ️ [VisitsAPI] record_campaign_address_outcome missing, falling back to upsert_address_status")
            }

            let fallbackParams: [String: AnyCodable] = [
                "p_address_id": AnyCodable(addressId),
                "p_campaign_id": AnyCodable(campaignId),
                "p_status": AnyCodable(status.persistedRPCValue),
                "p_notes": AnyCodable(notes ?? ""),
                "p_last_visited_at": AnyCodable(occurredAt)
            ]

            _ = try await client
                .rpc("upsert_address_status", params: fallbackParams)
                .execute()

            try await syncVisitedFlag(addressId: addressId, status: status)
        }

        invalidateStatusCache(campaignId: campaignId)
        debugLog("✅ [VisitsAPI] Status updated to \(status.rawValue)")
    }

    /// Clears voice/AI-derived columns on `campaign_addresses` when resetting a home to a clean slate.
    func clearCampaignAddressCaptureMetadata(addressId: UUID, campaignId: UUID) async throws {
        let updateData: [String: AnyCodable] = [
            "contact_name": AnyCodable(NSNull()),
            "lead_status": AnyCodable(NSNull()),
            "product_interest": AnyCodable(NSNull()),
            "follow_up_date": AnyCodable(NSNull()),
            "raw_transcript": AnyCodable(NSNull()),
            "ai_summary": AnyCodable(NSNull())
        ]
        _ = try await client
            .from("campaign_addresses")
            .update(updateData)
            .eq("id", value: addressId.uuidString)
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
        debugLog("✅ [VisitsAPI] Cleared campaign_addresses capture metadata for address \(addressId.uuidString)")
    }

    /// Update or create status for one or more campaign addresses that represent a single target/building.
    /// When multiple addresses are present, the backend owns the persisted transaction and session credit.
    func updateTargetStatus(
        addressIds: [UUID],
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil
    ) async throws {
        let uniqueAddressIds = deduplicated(addressIds)
        guard !uniqueAddressIds.isEmpty else { return }

        if uniqueAddressIds.count == 1, let addressId = uniqueAddressIds.first {
            try await updateStatus(
                addressId: addressId,
                campaignId: campaignId,
                status: status,
                notes: notes,
                sessionId: sessionId,
                sessionTargetId: sessionTargetId,
                sessionEventType: sessionEventType,
                location: location
            )
            return
        }

        debugLog("📝 [VisitsAPI] Updating target status to \(status.rawValue) for \(uniqueAddressIds.count) addresses")

        let occurredAt = ISO8601DateFormatter().string(from: Date())
        var canonicalParams: [String: AnyCodable] = [
            "p_campaign_id": AnyCodable(campaignId),
            "p_campaign_address_ids": AnyCodable(uniqueAddressIds.map(\.uuidString)),
            "p_status": AnyCodable(status.persistedRPCValue),
            "p_notes": AnyCodable(notes ?? ""),
            "p_occurred_at": AnyCodable(occurredAt)
        ]
        if let sessionId {
            canonicalParams["p_session_id"] = AnyCodable(sessionId)
        }
        if let sessionTargetId, !sessionTargetId.isEmpty {
            canonicalParams["p_session_target_id"] = AnyCodable(sessionTargetId)
        }
        if let sessionEventType {
            canonicalParams["p_session_event_type"] = AnyCodable(sessionEventType.rawValue)
        }
        if let location {
            canonicalParams["p_lat"] = AnyCodable(location.coordinate.latitude)
            canonicalParams["p_lon"] = AnyCodable(location.coordinate.longitude)
        }

        do {
            _ = try await client
                .rpc("record_campaign_target_outcome", params: canonicalParams)
                .execute()
        } catch {
            let fallbackReasonMissingRPC = isMissingFunction(error, functionName: "record_campaign_target_outcome")
            let fallbackReasonCampaignIDNotNull = isCampaignIDNotNullViolation(error)
            guard fallbackReasonMissingRPC || fallbackReasonCampaignIDNotNull else {
                throw error
            }

            if fallbackReasonCampaignIDNotNull {
                debugLog("⚠️ [VisitsAPI] record_campaign_target_outcome failed campaign_id not-null despite app sending campaign_id=\(campaignId.uuidString); falling back to per-address status updates")
            } else {
                debugLog("ℹ️ [VisitsAPI] record_campaign_target_outcome missing, falling back to per-address status updates")
            }

            for (index, addressId) in uniqueAddressIds.enumerated() {
                try await updateStatus(
                    addressId: addressId,
                    campaignId: campaignId,
                    status: status,
                    notes: notes,
                    sessionId: index == 0 ? sessionId : nil,
                    sessionTargetId: index == 0 ? sessionTargetId : nil,
                    sessionEventType: index == 0 ? sessionEventType : nil,
                    location: index == 0 ? location : nil
                )
            }
        }

        invalidateStatusCache(campaignId: campaignId)
        debugLog("✅ [VisitsAPI] Target status updated to \(status.rawValue)")
    }

    public func flushPending() async {
        let pendingTouchesSnapshot = dequeueAllPendingTouches()
        var failedTouches: [(addressId: UUID, campaignId: UUID, buildingId: String?, sessionId: UUID?)] = []
        for pending in pendingTouchesSnapshot {
            do {
                try await insertTouch(
                    addressId: pending.addressId,
                    campaignId: pending.campaignId,
                    buildingId: pending.buildingId,
                    sessionId: pending.sessionId
                )
            } catch {
                failedTouches.append(pending)
            }
        }
        if !failedTouches.isEmpty {
            requeuePendingTouches(failedTouches)
        }

        let pendingVisitedSnapshot = dequeueAllPendingVisitedMarks()
        var failedVisited: [UUID] = []
        for addressId in pendingVisitedSnapshot {
            do {
                try await updateVisited(addressId: addressId)
            } catch {
                failedVisited.append(addressId)
            }
        }
        if !failedVisited.isEmpty {
            requeuePendingVisitedMarks(failedVisited)
        }
    }

    private func insertTouch(
        addressId: UUID,
        campaignId: UUID,
        buildingId: String?,
        sessionId: UUID?
    ) async throws {
        guard let user = try? await client.auth.session.user else {
            throw NSError(domain: "VisitsAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user for building touch logging"])
        }

        var touchData: [String: AnyCodable] = [
            "user_id": AnyCodable(user.id.uuidString),
            "address_id": AnyCodable(addressId.uuidString),
            "campaign_id": AnyCodable(campaignId.uuidString),
            "touched_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]

        touchData["building_id"] = AnyCodable(buildingIdCodableValue(buildingId))

        if let sessionId = sessionId {
            touchData["session_id"] = AnyCodable(sessionId.uuidString)
        } else {
            touchData["session_id"] = AnyCodable(NSNull())
        }

        _ = try await client
            .from("building_touches")
            .insert(touchData)
            .execute()
    }

    private func updateVisited(addressId: UUID) async throws {
        let updateData: [String: AnyCodable] = [
            "visited": AnyCodable(true)
        ]

        _ = try await client
            .from("campaign_addresses")
            .update(updateData)
            .eq("id", value: addressId.uuidString)
            .execute()
    }

    private func syncVisitedFlag(addressId: UUID, status: AddressStatus) async throws {
        let visited: Bool
        switch status {
        case .none, .untouched:
            visited = false
        default:
            visited = true
        }

        let updateData: [String: AnyCodable] = [
            "visited": AnyCodable(visited)
        ]

        _ = try await client
            .from("campaign_addresses")
            .update(updateData)
            .eq("id", value: addressId.uuidString)
            .execute()
    }

    private func enqueuePendingTouch(addressId: UUID, campaignId: UUID, buildingId: String?, sessionId: UUID?) {
        pendingLock.lock()
        pendingTouches.append((addressId: addressId, campaignId: campaignId, buildingId: buildingId, sessionId: sessionId))
        pendingLock.unlock()
    }

    private func enqueuePendingVisitedMark(_ addressId: UUID) {
        pendingLock.lock()
        pendingVisitedMarks.append(addressId)
        pendingLock.unlock()
    }

    private func dequeueAllPendingTouches() -> [(addressId: UUID, campaignId: UUID, buildingId: String?, sessionId: UUID?)] {
        pendingLock.lock()
        let snapshot = pendingTouches
        pendingTouches.removeAll(keepingCapacity: true)
        pendingLock.unlock()
        return snapshot
    }

    private func dequeueAllPendingVisitedMarks() -> [UUID] {
        pendingLock.lock()
        let snapshot = pendingVisitedMarks
        pendingVisitedMarks.removeAll(keepingCapacity: true)
        pendingLock.unlock()
        return snapshot
    }

    private func requeuePendingTouches(_ touches: [(addressId: UUID, campaignId: UUID, buildingId: String?, sessionId: UUID?)]) {
        pendingLock.lock()
        pendingTouches.append(contentsOf: touches)
        pendingLock.unlock()
    }

    private func requeuePendingVisitedMarks(_ visited: [UUID]) {
        pendingLock.lock()
        pendingVisitedMarks.append(contentsOf: visited)
        pendingLock.unlock()
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
    }

    private func deduplicated(_ addressIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return addressIds.filter { seen.insert($0).inserted }
    }

    /// Prefer `UUID` for `building_touches.building_id` when the column is uuid; fall back to string for legacy text columns.
    private func buildingIdCodableValue(_ buildingId: String?) -> Any {
        guard let raw = buildingId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return NSNull()
        }
        if let uuid = UUID(uuidString: raw) {
            return uuid
        }
        return raw
    }

    private func isMissingFunction(_ error: Error, functionName: String) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains(functionName.lowercased()) && message.contains("does not exist")
    }

    private func isCampaignIDNotNullViolation(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("campaign_id")
            && (message.contains("23502") || message.contains("not-null") || message.contains("not null"))
    }

    @discardableResult
    private func synchronizedStatusState<T>(_ operation: () -> T) -> T {
        statusFetchLock.lock()
        defer { statusFetchLock.unlock() }
        return operation()
    }
}
