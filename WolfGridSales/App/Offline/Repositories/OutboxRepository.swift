import Foundation
import GRDB

enum OutboxOperation: String, Codable, Sendable {
    case upsertAddressStatus = "upsert_address_status"
    case upsertAddressCaptureMetadata = "upsert_address_capture_metadata"
    case logBuildingTouch = "log_building_touch"
    case markAddressVisited = "mark_address_visited"
    case createSession = "create_session"
    case updateSessionProgress = "update_session_progress"
    case endSession = "end_session"
    case createSessionEvent = "create_session_event"
    case upsertContact = "upsert_contact"
    case createContactActivity = "create_contact_activity"
    case deleteContact = "delete_contact"
    case deleteBuilding = "delete_building"
    case deleteAddress = "delete_address"
    case deleteManualAddress = "delete_manual_address"
    case unlinkAddressFromBuilding = "unlink_address_from_building"
    case createManualAddress = "create_manual_address"
    case moveAddress = "move_address"
    case moveBuilding = "move_building"
    case linkAddressToBuilding = "link_address_to_building"
    case fallbackBuildingCreated = "fallback_building_created"
    case createFarmTouch = "create_farm_touch"
    case markFarmTouchExecuted = "mark_farm_touch_executed"
    case markFarmTouchComplete = "mark_farm_touch_complete"
    case recordFarmAddressOutcome = "record_farm_address_outcome"
    case createFarmLead = "create_farm_lead"
    case updateFarmLead = "update_farm_lead"
    case deleteFarmLead = "delete_farm_lead"
    case upsertCalendarEvent = "upsert_calendar_event"
    case deleteCalendarEvent = "delete_calendar_event"
}

struct OfflineFarmExecutionPayload: Codable, Sendable {
    let farmId: String
    let farmName: String
    let touchId: String
    let touchTitle: String
    let touchDate: String
    let touchType: FarmTouchType
    let campaignId: String
    let cycleNumber: Int?
    let cycleName: String?

    init(context: FarmExecutionContext) {
        farmId = context.farmId.uuidString
        farmName = context.farmName
        touchId = context.touchId.uuidString
        touchTitle = context.touchTitle
        touchDate = OfflineDateCodec.string(from: context.touchDate)
        touchType = context.touchType
        campaignId = context.campaignId.uuidString
        cycleNumber = context.cycleNumber
        cycleName = context.cycleName
    }

    func makeContext() -> FarmExecutionContext? {
        guard let farmId = UUID(uuidString: farmId),
              let touchId = UUID(uuidString: touchId),
              let campaignId = UUID(uuidString: campaignId),
              let touchDate = OfflineDateCodec.date(from: touchDate) else {
            return nil
        }

        return FarmExecutionContext(
            farmId: farmId,
            farmName: farmName,
            touchId: touchId,
            touchTitle: touchTitle,
            touchDate: touchDate,
            touchType: touchType,
            campaignId: campaignId,
            cycleNumber: cycleNumber,
            cycleName: cycleName
        )
    }
}

struct OfflineSessionPayload: Codable, Sendable {
    let id: String
    let userId: String
    let campaignId: String
    let targetBuildings: [String]
    let autoCompleteEnabled: Bool
    let thresholdMeters: Double
    let dwellSeconds: Int
    let notes: String?
    let workspaceId: String?
    let goalType: String
    let goalAmount: Int?
    let sessionMode: String
    let routeAssignmentId: String?
    let farmExecutionContext: OfflineFarmExecutionPayload?
    let startedAt: String
}

struct FarmTouchOutboxPayload: Codable, Sendable {
    let touch: FarmTouch
}

struct FarmTouchExecutedOutboxPayload: Codable, Sendable {
    let touchId: String
    let cycleNumber: Int?
    let sessionId: String
    let completedByUserId: String
    let completedAt: String
    let metrics: [String: AnyCodable]
}

struct FarmTouchCompleteOutboxPayload: Codable, Sendable {
    let touchId: String
    let completed: Bool
    let completedAt: String?
}

struct FarmAddressOutcomeOutboxPayload: Codable, Sendable {
    let farmExecutionContext: OfflineFarmExecutionPayload
    let addressId: String
    let status: String
    let notes: String?
    let occurredAt: String
}

struct FarmLeadOutboxPayload: Codable, Sendable {
    let lead: FarmLead
}

struct DeleteFarmLeadOutboxPayload: Codable, Sendable {
    let leadId: String
}

struct AddressStatusOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressIds: [String]
    let buildingId: String?
    let status: String
    let notes: String?
    let sessionId: String?
    let sessionTargetId: String?
    let sessionEventType: String?
    let latitude: Double?
    let longitude: Double?
    let occurredAt: String
    let farmExecutionContext: OfflineFarmExecutionPayload?
    let baseRevisions: [String: Int]?
    let overrideReason: String?
}

struct BuildingTouchOutboxPayload: Codable, Sendable {
    let addressId: String
    let campaignId: String
    let buildingId: String?
    let sessionId: String?
    let userId: String?
    let touchedAt: String
}

struct MarkAddressVisitedOutboxPayload: Codable, Sendable {
    let addressId: String
    let visited: Bool
}

struct SessionProgressOutboxPayload: Codable, Sendable {
    let id: String
    let campaignId: String?
    let completedCount: Int?
    let distanceM: Double?
    let activeSeconds: Int?
    let pathGeoJSON: String?
    let pathGeoJSONNormalized: String?
    let flyersDelivered: Int?
    let conversations: Int?
    let leadsCreated: Int?
    let appointmentsCount: Int?
    let doorsHit: Int?
    let autoCompleteEnabled: Bool?
    let isPaused: Bool?
    let endTime: String?
}

struct SessionEventOutboxPayload: Codable, Sendable {
    let localEventId: String
    let sessionId: String
    let campaignId: String
    let buildingId: String?
    let eventType: String
    let latitude: Double?
    let longitude: Double?
    let metadata: [String: String]
}

struct ContactOutboxPayload: Codable, Sendable {
    let contactJSON: String
    let userId: String?
    let workspaceId: String?
    let addressId: String?
    let syncToCRM: Bool
}

struct ContactActivityOutboxPayload: Codable, Sendable {
    let localActivityId: String
    let contactId: String
    let type: String
    let note: String?
    let timestamp: String
}

struct AddressCaptureMetadataOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressId: String
    let contactName: String?
    let leadStatus: String?
    let productInterest: String?
    let followUpDate: String?
    let rawTranscript: String?
    let aiSummary: String?
    let clearAll: Bool
}

struct DeleteContactOutboxPayload: Codable, Sendable {
    let contactId: String
}

struct DeleteBuildingOutboxPayload: Codable, Sendable {
    let campaignId: String
    let buildingId: String
}

struct DeleteAddressOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressId: String
    let baseRevision: Int?
    let occurredAt: String?
}

typealias DeleteManualAddressOutboxPayload = DeleteAddressOutboxPayload

struct UnlinkAddressFromBuildingOutboxPayload: Codable, Sendable {
    let campaignId: String
    let buildingId: String
    let addressId: String
    let deleteManualAddress: Bool
}

struct MoveAddressOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressId: String
    let latitude: Double
    let longitude: Double
    let baseRevision: Int?
    let occurredAt: String?
}

struct MoveBuildingOutboxPayload: Codable, Sendable {
    let campaignId: String
    let buildingId: String
    let geometryJSON: String
}

struct ManualAddressCreateOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressId: String
    let formatted: String
    let houseNumber: String?
    let streetName: String?
    let locality: String?
    let region: String?
    let postalCode: String?
    let country: String?
    let buildingId: String?
    let addressProvenance: String?
    let userConfirmed: Bool
    let parcelId: String?
    let campaignParcelId: String?
    let hasParcelLink: Bool?
    let latitude: Double
    let longitude: Double
}

struct LinkAddressToBuildingOutboxPayload: Codable, Sendable {
    let campaignId: String
    let buildingId: String
    let addressId: String
    let latitude: Double?
    let longitude: Double?
}

struct FallbackBuildingCreatedOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressId: String
    let fallbackBuildingId: String
    let geometryJSON: String
    let geometrySource: String
    let createdAt: String
}

struct OutboxEntry: Codable, FetchableRecord, PersistableRecord, Sendable {
    let id: String
    let clientMutationId: String?
    let entityType: String
    let entityId: String
    let operation: String
    let operationVersion: Int
    let payloadJSON: String
    let status: String?
    let dependencyKey: String?
    let createdAt: String
    let attemptedAt: String?
    let syncedAt: String?
    let retryAfter: String?
    let retryCount: Int
    let errorMessage: String?
    let deadLetteredAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case clientMutationId = "client_mutation_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case operation
        case operationVersion = "operation_version"
        case payloadJSON = "payload_json"
        case status
        case dependencyKey = "dependency_key"
        case createdAt = "created_at"
        case attemptedAt = "attempted_at"
        case syncedAt = "synced_at"
        case retryAfter = "retry_after"
        case retryCount = "retry_count"
        case errorMessage = "error_message"
        case deadLetteredAt = "dead_lettered_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clientMutationId = "client_mutation_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case operation
        case operationVersion = "operation_version"
        case payloadJSON = "payload_json"
        case status
        case dependencyKey = "dependency_key"
        case createdAt = "created_at"
        case attemptedAt = "attempted_at"
        case syncedAt = "synced_at"
        case retryAfter = "retry_after"
        case retryCount = "retry_count"
        case errorMessage = "error_message"
        case deadLetteredAt = "dead_lettered_at"
    }

    static let databaseTableName = "sync_outbox"

    func decodedPayload<T: Decodable>(_ type: T.Type) -> T? {
        OfflineJSONCodec.decode(T.self, from: payloadJSON)
    }
}

struct CampaignMutationConflict: Identifiable, Equatable, Sendable {
    let id: String
    let campaignId: String
    let operation: OutboxOperation
    let canonicalRevision: Int?
    let canonicalActorUserId: UUID?
    let canonicalStateJSON: String?
    let draftPayloadJSON: String

    enum Attribution: Equatable, Sendable {
        case currentUser
        case teammate
        case unknown
    }

    func attribution(for currentUserId: UUID?) -> Attribution {
        guard let canonicalActorUserId, let currentUserId else { return .unknown }
        return canonicalActorUserId == currentUserId ? .currentUser : .teammate
    }

    var title: String {
        switch operation {
        case .moveAddress:
            return "Pin location changed elsewhere"
        case .deleteAddress, .deleteManualAddress:
            return "Pin changed before deletion"
        case .upsertAddressStatus:
            return "Home status changed elsewhere"
        default:
            return "Campaign change needs review"
        }
    }
}

struct CampaignMutationReapplyPlan: Equatable, Sendable {
    let clientMutationId: String
    let payloadJSON: String
    let baseRevision: Int
}

enum CampaignMutationConflictResolver {
    static func conflict(from entry: OutboxEntry) -> CampaignMutationConflict? {
        guard entry.status == "conflict",
              let operation = OutboxOperation(rawValue: entry.operation),
              let campaignId = campaignId(from: entry) else {
            return nil
        }
        let canonicalJSON = canonicalStateJSON(from: entry.errorMessage)
        return CampaignMutationConflict(
            id: entry.id,
            campaignId: campaignId,
            operation: operation,
            canonicalRevision: canonicalRevision(from: canonicalJSON),
            canonicalActorUserId: canonicalActorUserId(from: canonicalJSON),
            canonicalStateJSON: canonicalJSON,
            draftPayloadJSON: entry.payloadJSON
        )
    }

    static func canonicalStateJSON(from errorMessage: String?) -> String? {
        guard let errorMessage,
              let separator = errorMessage.firstIndex(of: "|") else {
            return nil
        }
        let json = String(errorMessage[errorMessage.index(after: separator)...])
        guard let data = json.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return json
    }

    static func canonicalRevision(from canonicalStateJSON: String?) -> Int? {
        guard let canonicalStateJSON,
              let data = canonicalStateJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let revision = object["revision"] as? Int { return revision }
        return (object["revision"] as? NSNumber)?.intValue
    }

    static func canonicalActorUserId(from canonicalStateJSON: String?) -> UUID? {
        guard let canonicalStateJSON,
              let data = canonicalStateJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let rawValue = (object["last_action_by"] as? String)
            ?? (object["lastActionBy"] as? String)
            ?? (object["updated_by"] as? String)
            ?? (object["updatedBy"] as? String)
        return rawValue.flatMap(UUID.init(uuidString:))
    }

    static func rebasedPayloadJSON(for entry: OutboxEntry, canonicalRevision: Int) -> String? {
        guard canonicalRevision >= 0,
              let data = entry.payloadJSON.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch OutboxOperation(rawValue: entry.operation) {
        case .upsertAddressStatus:
            guard let addressIds = object["addressIds"] as? [String], !addressIds.isEmpty else {
                return nil
            }
            object["baseRevisions"] = Dictionary(uniqueKeysWithValues: addressIds.map { ($0.lowercased(), canonicalRevision) })
        case .moveAddress, .deleteAddress, .deleteManualAddress:
            object["baseRevision"] = canonicalRevision
        default:
            return nil
        }

        guard JSONSerialization.isValidJSONObject(object),
              let updated = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: updated, encoding: .utf8)
    }

    static func reapplyPlan(
        for entry: OutboxEntry,
        newClientMutationId: String = UUID().uuidString
    ) -> CampaignMutationReapplyPlan? {
        guard let canonicalRevision = conflict(from: entry)?.canonicalRevision,
              let payloadJSON = rebasedPayloadJSON(for: entry, canonicalRevision: canonicalRevision) else {
            return nil
        }
        return CampaignMutationReapplyPlan(
            clientMutationId: newClientMutationId,
            payloadJSON: payloadJSON,
            baseRevision: canonicalRevision
        )
    }

    private static func campaignId(from entry: OutboxEntry) -> String? {
        guard let data = entry.payloadJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let campaignId = object["campaignId"] as? String,
              !campaignId.isEmpty else {
            return nil
        }
        return campaignId
    }
}

final class OutboxRepository {
    static let shared = OutboxRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    @discardableResult
    func enqueue<P: Encodable>(
        entityType: String,
        entityId: String,
        operation: OutboxOperation,
        payload: P,
        clientMutationId: String = UUID().uuidString,
        operationVersion: Int = 1,
        dependencyKey: String? = nil
    ) async -> String? {
        guard let payloadJSON = OfflineJSONCodec.encode(payload) else { return nil }
        let resolvedDependencyKey = dependencyKey ?? "\(entityType):\(entityId)"
        let entry = OutboxEntry(
            id: UUID().uuidString,
            clientMutationId: clientMutationId,
            entityType: entityType,
            entityId: entityId,
            operation: operation.rawValue,
            operationVersion: operationVersion,
            payloadJSON: payloadJSON,
            status: "pending",
            dependencyKey: resolvedDependencyKey,
            createdAt: OfflineDateCodec.string(from: Date()),
            attemptedAt: nil,
            syncedAt: nil,
            retryAfter: nil,
            retryCount: 0,
            errorMessage: nil,
            deadLetteredAt: nil
        )

        do {
            try await dbQueue.write { db in
                try entry.insert(db)
            }
            return entry.id
        } catch {
            debugLog("Failed to enqueue outbox entry \(operation.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    func fetchPending(limit: Int = 50) async -> [OutboxEntry] {
        let now = OfflineDateCodec.string(from: Date())
        return (try? await dbQueue.read { db in
            try OutboxEntry.fetchAll(
                db,
                sql: """
                SELECT o.*
                FROM sync_outbox o
                WHERE o.synced_at IS NULL
                  AND COALESCE(o.status, 'pending') IN ('pending', 'failed')
                  AND (o.retry_after IS NULL OR o.retry_after <= ?)
                  AND NOT EXISTS (
                      SELECT 1
                      FROM sync_outbox older
                      WHERE older.synced_at IS NULL
                        AND COALESCE(older.status, 'pending') != 'dead_letter'
                        AND COALESCE(older.dependency_key, older.entity_type || ':' || older.entity_id)
                            = COALESCE(o.dependency_key, o.entity_type || ':' || o.entity_id)
                        AND older.rowid < o.rowid
                  )
                ORDER BY o.created_at ASC
                LIMIT ?
                """,
                arguments: [now, limit]
            )
        }) ?? []
    }

    func pendingCount() async -> Int {
        (try? await dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM sync_outbox
                WHERE synced_at IS NULL
                  AND COALESCE(status, 'pending') != 'dead_letter'
                """
            )
        }) ?? 0
    }

    func fetchConflicts() async -> [CampaignMutationConflict] {
        (try? await dbQueue.read { db in
            try OutboxEntry
                .filter(Column("status") == "conflict")
                .filter(Column("synced_at") == nil)
                .order(Column("created_at").asc)
                .fetchAll(db)
                .compactMap(CampaignMutationConflictResolver.conflict(from:))
        }) ?? []
    }

    func discardConflictAndUseServer(id: String, at date: Date = Date()) async {
        let resolvedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET status = 'discarded_server',
                    synced_at = ?,
                    retry_after = NULL,
                    error_message = NULL
                WHERE id = ? AND status = 'conflict' AND synced_at IS NULL
                """,
                arguments: [resolvedAt, id]
            )
        }
    }

    @discardableResult
    func reapplyConflict(id: String, newClientMutationId: String = UUID().uuidString) async -> Bool {
        do {
            return try await dbQueue.write { db in
                guard let entry = try OutboxEntry.fetchOne(db, key: id),
                      entry.status == "conflict",
                      entry.syncedAt == nil,
                      let plan = CampaignMutationConflictResolver.reapplyPlan(
                        for: entry,
                        newClientMutationId: newClientMutationId
                      ) else {
                    return false
                }

                try db.execute(
                    sql: """
                    UPDATE sync_outbox
                    SET client_mutation_id = ?,
                        payload_json = ?,
                        status = 'pending',
                        attempted_at = NULL,
                        retry_after = NULL,
                        retry_count = 0,
                        error_message = NULL,
                        dead_lettered_at = NULL
                    WHERE id = ? AND status = 'conflict' AND synced_at IS NULL
                    """,
                    arguments: [plan.clientMutationId, plan.payloadJSON, id]
                )
                return db.changesCount > 0
            }
        } catch {
            return false
        }
    }

    func resetStaleProcessing(olderThan interval: TimeInterval = 300) async {
        let cutoff = OfflineDateCodec.string(from: Date().addingTimeInterval(-interval))
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET status = 'failed',
                    retry_after = NULL,
                    error_message = COALESCE(error_message, 'Reset stale processing entry')
                WHERE status = 'processing'
                  AND attempted_at IS NOT NULL
                  AND attempted_at <= ?
                  AND synced_at IS NULL
                """,
                arguments: [cutoff]
            )
        }
    }

    func markAttempted(id: String, at date: Date = Date()) async {
        let attemptedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET attempted_at = ?,
                    status = 'processing',
                    retry_after = NULL,
                    error_message = NULL
                WHERE id = ?
                """,
                arguments: [attemptedAt, id]
            )
        }
    }

    func markSynced(id: String, at date: Date = Date()) async {
        let syncedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET synced_at = ?,
                    status = 'synced',
                    retry_after = NULL,
                    error_message = NULL
                WHERE id = ?
                """,
                arguments: [syncedAt, id]
            )
        }
    }

    func markFailed(
        id: String,
        errorMessage: String,
        retryAfter: Date?,
        deadLetter: Bool = false,
        at date: Date = Date()
    ) async {
        let attemptedAt = OfflineDateCodec.string(from: date)
        let retryAfterString = retryAfter.map(OfflineDateCodec.string(from:))
        let deadLetteredAt = deadLetter ? attemptedAt : nil
        let status = deadLetter ? "dead_letter" : "failed"
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET attempted_at = ?,
                    retry_count = retry_count + 1,
                    status = ?,
                    retry_after = ?,
                    error_message = ?,
                    dead_lettered_at = COALESCE(?, dead_lettered_at)
                WHERE id = ?
                """,
                arguments: [attemptedAt, status, retryAfterString, errorMessage, deadLetteredAt, id]
            )
        }
    }

    func markPaused(id: String, status: String, errorMessage: String) async {
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET status = ?,
                    retry_after = NULL,
                    error_message = ?
                WHERE id = ? AND synced_at IS NULL
                """,
                arguments: [status, errorMessage, id]
            )
        }
    }

    func resumeUpgradeBlockedEntries(currentBuild: Int) async {
        let currentMarker = "CLIENT_UPGRADE_REQUIRED:\(currentBuild)"
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sync_outbox
                SET status = 'pending', retry_after = NULL, error_message = NULL
                WHERE status = 'blocked_upgrade'
                  AND COALESCE(error_message, '') != ?
                  AND synced_at IS NULL
                """,
                arguments: [currentMarker]
            )
        }
    }

    func updatePendingManualAddressCreatePayload(
        campaignId: String,
        addressId: UUID,
        formatted: String,
        houseNumber: String?,
        streetName: String?,
        locality: String?,
        region: String?,
        postalCode: String?,
        country: String?
    ) async {
        let trimmedFormatted = formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFormatted.isEmpty else { return }

        let targetEntityId = "\(campaignId.lowercased()):\(addressId.uuidString.lowercased())"
        try? await dbQueue.write { db in
            let entries = try OutboxEntry.fetchAll(
                db,
                sql: """
                SELECT *
                FROM sync_outbox
                WHERE operation = ?
                  AND entity_id = ?
                  AND synced_at IS NULL
                  AND COALESCE(status, 'pending') IN ('pending', 'failed')
                """,
                arguments: [OutboxOperation.createManualAddress.rawValue, targetEntityId]
            )

            for entry in entries {
                guard let payload = entry.decodedPayload(ManualAddressCreateOutboxPayload.self),
                      payload.campaignId.lowercased() == campaignId.lowercased(),
                      payload.addressId.lowercased() == addressId.uuidString.lowercased() else {
                    continue
                }

                let updatedPayload = ManualAddressCreateOutboxPayload(
                    campaignId: payload.campaignId,
                    addressId: payload.addressId,
                    formatted: trimmedFormatted,
                    houseNumber: houseNumber ?? payload.houseNumber,
                    streetName: streetName ?? payload.streetName,
                    locality: locality ?? payload.locality,
                    region: region ?? payload.region,
                    postalCode: postalCode ?? payload.postalCode,
                    country: country ?? payload.country,
                    buildingId: payload.buildingId,
                    addressProvenance: payload.addressProvenance,
                    userConfirmed: payload.userConfirmed,
                    parcelId: payload.parcelId,
                    campaignParcelId: payload.campaignParcelId,
                    hasParcelLink: payload.hasParcelLink,
                    latitude: payload.latitude,
                    longitude: payload.longitude
                )
                guard let payloadJSON = OfflineJSONCodec.encode(updatedPayload) else { continue }
                try db.execute(
                    sql: """
                    UPDATE sync_outbox
                    SET payload_json = ?
                    WHERE id = ?
                      AND synced_at IS NULL
                      AND COALESCE(status, 'pending') IN ('pending', 'failed')
                    """,
                    arguments: [payloadJSON, entry.id]
                )
            }
        }
    }

    func discardPendingSessionEntries(sessionId: UUID) async {
        let dependencyKey = "session:\(sessionId.uuidString.lowercased())"
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                DELETE FROM sync_outbox
                WHERE synced_at IS NULL
                  AND COALESCE(dependency_key, entity_type || ':' || entity_id) = ?
                """,
                arguments: [dependencyKey]
            )
        }
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[OutboxRepository] \(message())")
        #endif
    }
}
