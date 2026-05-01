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
    case moveAddress = "move_address"
    case moveBuilding = "move_building"
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

struct MoveAddressOutboxPayload: Codable, Sendable {
    let campaignId: String
    let addressId: String
    let latitude: Double
    let longitude: Double
}

struct MoveBuildingOutboxPayload: Codable, Sendable {
    let campaignId: String
    let buildingId: String
    let geometryJSON: String
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

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[OutboxRepository] \(message())")
        #endif
    }
}
