import Foundation
import CoreLocation
import Supabase

/// API for logging building visits/touches and updating campaign address visited status
final class VisitsAPI {
    static let shared = VisitsAPI()
    private init() {}

    private struct StatusFetchScope: Hashable {
        let campaignId: UUID
        let farmCycleNumber: Int?
    }
    
    private let client = SupabaseManager.shared.client
    private let pendingLock = NSLock()
    private var pendingTouches: [(addressId: UUID, campaignId: UUID, buildingId: String?, sessionId: UUID?)] = []
    private var pendingVisitedMarks: [UUID] = []
    private let statusFetchLock = NSLock()
    private var inFlightStatusFetches: [StatusFetchScope: Task<[UUID: AddressStatusRow], Error>] = [:]
    private var lastStatusFetchAt: [StatusFetchScope: Date] = [:]
    private var cachedStatuses: [StatusFetchScope: [UUID: AddressStatusRow]] = [:]
    private let campaignRepository = CampaignRepository.shared
    private let outboxRepository = OutboxRepository.shared
    /// Short TTL so rapid map updates (buildings → addresses → route scope) reuse one response instead of re-hitting Supabase.
    private let statusFetchCooldownSeconds: TimeInterval = 12

    /// Clears in-memory status cache so the next `fetchStatuses` hits the network (used after writes).
    func invalidateStatusCache(campaignId: UUID) {
        synchronizedStatusState {
            let matchingScopes = Set(cachedStatuses.keys.filter { $0.campaignId == campaignId })
                .union(lastStatusFetchAt.keys.filter { $0.campaignId == campaignId })
                .union(inFlightStatusFetches.keys.filter { $0.campaignId == campaignId })

            for scope in matchingScopes {
                cachedStatuses[scope] = nil
                lastStatusFetchAt[scope] = nil
                inFlightStatusFetches[scope] = nil
            }
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
    ///   - farmCycleNumber: Optional farm cycle scope. When present, only statuses recorded by sessions in that cycle are returned.
    ///   - forceRefresh: When true, skips the short cooldown cache and always fetches from the server.
    /// - Returns: Dictionary mapping address_id to AddressStatusRow
    func fetchStatuses(
        campaignId: UUID,
        farmCycleNumber: Int? = nil,
        forceRefresh: Bool = false
    ) async throws -> [UUID: AddressStatusRow] {
        let scope = StatusFetchScope(campaignId: campaignId, farmCycleNumber: farmCycleNumber)
        let shouldBypassCooldownCache = forceRefresh || farmCycleNumber != nil

        if let inFlight = synchronizedStatusState({ inFlightStatusFetches[scope] }) {
            return try await inFlight.value
        }

        if !shouldBypassCooldownCache {
            let localStatuses = await campaignRepository.getStatuses(campaignId: campaignId)
            if !localStatuses.isEmpty {
                synchronizedStatusState {
                    cachedStatuses[scope] = localStatuses
                    lastStatusFetchAt[scope] = Date()
                }
                return localStatuses
            }
        }

        if !shouldBypassCooldownCache,
           let cached = synchronizedStatusState({ () -> [UUID: AddressStatusRow]? in
            guard let lastFetch = lastStatusFetchAt[scope],
                  Date().timeIntervalSince(lastFetch) <= statusFetchCooldownSeconds else {
                return nil
            }
            return cachedStatuses[scope]
        }) {
            debugLog("📊 [VisitsAPI] Using cached statuses for campaign (cooldown)")
            return cached
        }

        let task = Task<[UUID: AddressStatusRow], Error> {
            let cycleLogSuffix = farmCycleNumber.map { " cycle=\($0)" } ?? ""
            debugLog("📊 [VisitsAPI] Fetching statuses for campaign\(cycleLogSuffix)")

            let rows = try await remoteFetchStatuses(campaignId: campaignId, farmCycleNumber: farmCycleNumber)
            
            var statuses: [UUID: AddressStatusRow] = [:]
            for statusRow in rows {
                statuses[statusRow.addressId] = statusRow
            }

            await campaignRepository.upsertStatuses(rows: rows)
            
            synchronizedStatusState {
                cachedStatuses[scope] = statuses
                lastStatusFetchAt[scope] = Date()
            }
            debugLog("✅ [VisitsAPI] Fetched \(statuses.count) statuses for campaign\(cycleLogSuffix)")
            return statuses
        }

        synchronizedStatusState {
            inFlightStatusFetches[scope] = task
        }
        defer {
            synchronizedStatusState {
                inFlightStatusFetches[scope] = nil
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
    @discardableResult
    func updateStatus(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil
    ) async throws -> AddressStatusRow? {
        let rows = try await updateTargetStatus(
            addressIds: [addressId],
            campaignId: campaignId,
            status: status,
            notes: notes,
            sessionId: sessionId,
            sessionTargetId: sessionTargetId,
            sessionEventType: sessionEventType,
            location: location
        )
        return rows.first
    }

    /// Clears voice/AI-derived columns on `campaign_addresses` when resetting a home to a clean slate.
    func clearCampaignAddressCaptureMetadata(addressId: UUID, campaignId: UUID) async throws {
        await campaignRepository.clearAddressCaptureMetadata(
            campaignId: campaignId,
            addressId: addressId,
            dirty: true
        )
        await outboxRepository.enqueue(
            entityType: "address_capture_metadata",
            entityId: addressId.uuidString,
            operation: .upsertAddressCaptureMetadata,
            payload: AddressCaptureMetadataOutboxPayload(
                campaignId: campaignId.uuidString,
                addressId: addressId.uuidString,
                contactName: nil,
                leadStatus: nil,
                productInterest: nil,
                followUpDate: nil,
                rawTranscript: nil,
                aiSummary: nil,
                clearAll: true
            )
        )
        if NetworkMonitor.shared.isOnline {
            await MainActor.run {
                OfflineSyncCoordinator.shared.scheduleProcessOutbox()
            }
        }
        debugLog("✅ [VisitsAPI] Queued campaign_addresses capture metadata reset for address \(addressId.uuidString)")
    }

    func performRemoteUpsertCampaignAddressCaptureMetadata(
        addressId: UUID,
        campaignId: UUID,
        contactName: String?,
        leadStatus: String?,
        productInterest: String?,
        followUpDate: Date?,
        rawTranscript: String?,
        aiSummary: String?,
        clearAll: Bool
    ) async throws {
        var updateData: [String: AnyCodable] = [:]
        if clearAll {
            updateData = [
                "contact_name": AnyCodable(NSNull()),
                "lead_status": AnyCodable(NSNull()),
                "product_interest": AnyCodable(NSNull()),
                "follow_up_date": AnyCodable(NSNull()),
                "raw_transcript": AnyCodable(NSNull()),
                "ai_summary": AnyCodable(NSNull())
            ]
        } else {
            if let contactName {
                updateData["contact_name"] = AnyCodable(contactName)
            }
            if let leadStatus {
                updateData["lead_status"] = AnyCodable(leadStatus)
            }
            if let productInterest {
                updateData["product_interest"] = AnyCodable(productInterest)
            }
            if let followUpDate {
                updateData["follow_up_date"] = AnyCodable(followUpDate)
            }
            if let rawTranscript {
                updateData["raw_transcript"] = AnyCodable(rawTranscript)
            }
            if let aiSummary {
                updateData["ai_summary"] = AnyCodable(aiSummary)
            }
        }

        guard !updateData.isEmpty else { return }

        _ = try await client
            .from("campaign_addresses")
            .update(updateData)
            .eq("id", value: addressId.uuidString)
            .eq("campaign_id", value: campaignId.uuidString)
            .execute()
    }

    /// Update or create status for one or more campaign addresses that represent a single target/building.
    /// When multiple addresses are present, the backend owns the persisted transaction and session credit.
    @discardableResult
    func updateTargetStatus(
        addressIds: [UUID],
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil
    ) async throws -> [AddressStatusRow] {
        let uniqueAddressIds = deduplicated(addressIds)
        guard !uniqueAddressIds.isEmpty else { return [] }

        do {
            let now = Date()
            let localRows = await campaignRepository.updateStatusLocally(
                addressIds: uniqueAddressIds,
                campaignId: campaignId,
                buildingId: sessionTargetId,
                status: status,
                notes: notes,
                occurredAt: now,
                sessionId: sessionId
            )
            invalidateStatusCache(campaignId: campaignId)
            cacheStatuses(localRows, scope: StatusFetchScope(campaignId: campaignId, farmCycleNumber: nil))

            let payload = AddressStatusOutboxPayload(
                campaignId: campaignId.uuidString,
                addressIds: uniqueAddressIds.map(\.uuidString),
                buildingId: sessionTargetId,
                status: status.rawValue,
                notes: notes,
                sessionId: sessionId?.uuidString,
                sessionTargetId: sessionTargetId,
                sessionEventType: sessionEventType?.rawValue,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                occurredAt: OfflineDateCodec.string(from: now)
            )
            await outboxRepository.enqueue(
                entityType: "address_status",
                entityId: uniqueAddressIds.map(\.uuidString).joined(separator: ","),
                operation: .upsertAddressStatus,
                payload: payload
            )

            if NetworkMonitor.shared.isOnline {
                await MainActor.run {
                    OfflineSyncCoordinator.shared.scheduleProcessOutbox()
                }
            }

            debugLog("✅ [VisitsAPI] Queued target status update to \(status.rawValue)")
            return localRows
        } catch {
            debugLog("⚠️ [VisitsAPI] Local-first status update failed, falling back to direct remote sync: \(error.localizedDescription)")
            return try await performRemoteTargetStatusUpdate(
                addressIds: uniqueAddressIds,
                campaignId: campaignId,
                status: status,
                notes: notes,
                sessionId: sessionId,
                sessionTargetId: sessionTargetId,
                sessionEventType: sessionEventType,
                location: location
            )
        }
    }

    func performRemoteStatusUpdate(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil,
        occurredAt: Date? = nil
    ) async throws -> AddressStatusRow? {
        let rows = try await performRemoteTargetStatusUpdate(
            addressIds: [addressId],
            campaignId: campaignId,
            status: status,
            notes: notes,
            sessionId: sessionId,
            sessionTargetId: sessionTargetId,
            sessionEventType: sessionEventType,
            location: location,
            occurredAt: occurredAt
        )
        return rows.first
    }

    func performRemoteTargetStatusUpdate(
        addressIds: [UUID],
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil,
        occurredAt: Date? = nil
    ) async throws -> [AddressStatusRow] {
        let uniqueAddressIds = deduplicated(addressIds)
        guard !uniqueAddressIds.isEmpty else { return [] }

        if uniqueAddressIds.count == 1, let addressId = uniqueAddressIds.first {
            let row = try await performRemoteSingleStatusUpdate(
                addressId: addressId,
                campaignId: campaignId,
                status: status,
                notes: notes,
                sessionId: sessionId,
                sessionTargetId: sessionTargetId,
                sessionEventType: sessionEventType,
                location: location,
                occurredAt: occurredAt
            )
            return row.map { [$0] } ?? []
        }

        debugLog("📝 [VisitsAPI] Remotely updating target status to \(status.rawValue) for \(uniqueAddressIds.count) addresses")

        let occurredAtString = ISO8601DateFormatter().string(from: occurredAt ?? Date())
        var canonicalParams: [String: AnyCodable] = [
            "p_campaign_id": AnyCodable(campaignId),
            "p_campaign_address_ids": AnyCodable(uniqueAddressIds.map(\.uuidString)),
            "p_status": AnyCodable(status.persistedRPCValue),
            "p_notes": AnyCodable(notes ?? ""),
            "p_occurred_at": AnyCodable(occurredAtString)
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

        var updatedRows: [AddressStatusRow] = []
        do {
            let response = try await client
                .rpc("record_campaign_target_outcome", params: canonicalParams)
                .execute()
            updatedRows = decodeTargetAddressStatusRows(fromRPCResponse: response.data)
        } catch {
            let fallbackReasonMissingRPC = isMissingFunction(error, functionName: "record_campaign_target_outcome")
            let fallbackReasonCampaignIDNotNull = isCampaignIDNotNullViolation(error)
            guard fallbackReasonMissingRPC || fallbackReasonCampaignIDNotNull else {
                throw error
            }

            for (index, addressId) in uniqueAddressIds.enumerated() {
                if let row = try await performRemoteSingleStatusUpdate(
                    addressId: addressId,
                    campaignId: campaignId,
                    status: status,
                    notes: notes,
                    sessionId: index == 0 ? sessionId : nil,
                    sessionTargetId: index == 0 ? sessionTargetId : nil,
                    sessionEventType: index == 0 ? sessionEventType : nil,
                    location: index == 0 ? location : nil,
                    occurredAt: occurredAt
                ) {
                    updatedRows.append(row)
                }
            }
        }

        invalidateStatusCache(campaignId: campaignId)
        await campaignRepository.upsertStatuses(rows: updatedRows)
        cacheStatuses(updatedRows, scope: StatusFetchScope(campaignId: campaignId, farmCycleNumber: nil))
        return updatedRows
    }

    private func recordFarmOutcomeIfNeeded(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String?,
        sessionId: UUID?,
        occurredAt: String
    ) async {
        guard sessionId != nil else { return }

        let context = await MainActor.run { SessionManager.shared.currentFarmExecutionContext }
        guard let context,
              context.campaignId == campaignId else {
            return
        }

        do {
            _ = try await client
                .rpc(
                    "record_farm_address_outcome",
                    params: [
                        "p_farm_id": AnyCodable(context.farmId),
                        "p_farm_touch_id": AnyCodable(context.touchId),
                        "p_campaign_address_id": AnyCodable(addressId),
                        "p_status": AnyCodable(status.persistedRPCValue),
                        "p_notes": AnyCodable(notes ?? ""),
                        "p_occurred_at": AnyCodable(occurredAt)
                    ]
                )
                .execute()
        } catch {
            debugLog("⚠️ [VisitsAPI] Failed to record farm address outcome: \(error.localizedDescription)")
        }
    }

    func recordFarmAddressOutcome(
        context: FarmExecutionContext,
        addressId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        occurredAt: String? = nil
    ) async {
        let timestamp = occurredAt ?? ISO8601DateFormatter().string(from: Date())

        do {
            _ = try await client
                .rpc(
                    "record_farm_address_outcome",
                    params: [
                        "p_farm_id": AnyCodable(context.farmId),
                        "p_farm_touch_id": AnyCodable(context.touchId),
                        "p_campaign_address_id": AnyCodable(addressId),
                        "p_status": AnyCodable(status.persistedRPCValue),
                        "p_notes": AnyCodable(notes ?? ""),
                        "p_occurred_at": AnyCodable(timestamp)
                    ]
                )
                .execute()
            invalidateStatusCache(campaignId: context.campaignId)
        } catch {
            debugLog("⚠️ [VisitsAPI] Failed to record explicit farm address outcome: \(error.localizedDescription)")
        }
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

    private func decodeAddressStatusRow(fromRPCResponse data: Data) -> AddressStatusRow? {
        try? JSONDecoder.supabaseDates.decode(AddressStatusRow.self, from: data)
    }

    private func decodeTargetAddressStatusRows(fromRPCResponse data: Data) -> [AddressStatusRow] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawRows = root["address_outcomes"]
        else {
            return []
        }

        guard let rowsData = try? JSONSerialization.data(withJSONObject: rawRows) else {
            return []
        }

        return (try? JSONDecoder.supabaseDates.decode([AddressStatusRow].self, from: rowsData)) ?? []
    }

    @discardableResult
    private func synchronizedStatusState<T>(_ operation: () -> T) -> T {
        statusFetchLock.lock()
        defer { statusFetchLock.unlock() }
        return operation()
    }

    private func cacheStatuses(_ rows: [AddressStatusRow], scope: StatusFetchScope) {
        synchronizedStatusState {
            var existing = cachedStatuses[scope] ?? [:]
            for row in rows {
                existing[row.addressId] = row
            }
            cachedStatuses[scope] = existing
            lastStatusFetchAt[scope] = Date()
        }
    }

    private func remoteFetchStatuses(
        campaignId: UUID,
        farmCycleNumber: Int?
    ) async throws -> [AddressStatusRow] {
        if let farmCycleNumber {
            let response = try await client
                .rpc(
                    "rpc_get_campaign_address_status_rows_for_farm_cycle",
                    params: [
                        "p_campaign_id": AnyCodable(campaignId.uuidString),
                        "p_cycle_number": AnyCodable(farmCycleNumber)
                    ]
                )
                .execute()
            return try JSONDecoder.supabaseDates.decode([AddressStatusRow].self, from: response.data)
        }

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

        return try JSONDecoder.supabaseDates.decode([AddressStatusRow].self, from: response.data)
    }

    private func performRemoteSingleStatusUpdate(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        sessionId: UUID? = nil,
        sessionTargetId: String? = nil,
        sessionEventType: SessionEventType? = nil,
        location: CLLocation? = nil,
        occurredAt: Date? = nil
    ) async throws -> AddressStatusRow? {
        debugLog("📝 [VisitsAPI] Remotely updating status to \(status.rawValue)")

        let occurredAtString = ISO8601DateFormatter().string(from: occurredAt ?? Date())
        var canonicalParams: [String: AnyCodable] = [
            "p_campaign_id": AnyCodable(campaignId),
            "p_campaign_address_id": AnyCodable(addressId),
            "p_address_id": AnyCodable(addressId),
            "p_status": AnyCodable(status.persistedRPCValue),
            "p_notes": AnyCodable(notes ?? ""),
            "p_occurred_at": AnyCodable(occurredAtString)
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

        var updatedRow: AddressStatusRow?
        do {
            let response = try await client
                .rpc("record_campaign_address_outcome", params: canonicalParams)
                .execute()
            updatedRow = decodeAddressStatusRow(fromRPCResponse: response.data)
        } catch {
            let fallbackReasonMissingRPC = isMissingFunction(error, functionName: "record_campaign_address_outcome")
            let fallbackReasonCampaignIDNotNull = isCampaignIDNotNullViolation(error)
            guard fallbackReasonMissingRPC || fallbackReasonCampaignIDNotNull else {
                throw error
            }

            let fallbackParams: [String: AnyCodable] = [
                "p_address_id": AnyCodable(addressId),
                "p_campaign_id": AnyCodable(campaignId),
                "p_status": AnyCodable(status.persistedRPCValue),
                "p_notes": AnyCodable(notes ?? ""),
                "p_last_visited_at": AnyCodable(occurredAtString)
            ]

            _ = try await client
                .rpc("upsert_address_status", params: fallbackParams)
                .execute()

            try await syncVisitedFlag(addressId: addressId, status: status)
        }

        invalidateStatusCache(campaignId: campaignId)
        await recordFarmOutcomeIfNeeded(
            addressId: addressId,
            campaignId: campaignId,
            status: status,
            notes: notes,
            sessionId: sessionId,
            occurredAt: occurredAtString
        )
        if let updatedRow {
            await campaignRepository.upsertStatuses(rows: [updatedRow])
        }
        return updatedRow
    }
}
