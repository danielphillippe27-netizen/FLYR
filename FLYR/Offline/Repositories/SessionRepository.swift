import Foundation
import CoreLocation
import GRDB

struct LocalSessionPoint: Sendable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let accuracy: Double?
    let speed: Double?
    let heading: Double?
    let altitude: Double?
    let timestamp: Date
    let accepted: Bool
}

struct LocalSessionEvent: Sendable {
    let id: UUID
    let sessionId: UUID
    let campaignId: UUID
    let entityType: String?
    let entityId: String?
    let eventType: String?
    let payloadJSON: String?
    let occurredAt: Date
    let syncedAt: Date?
}

struct LocalSessionSnapshot: Sendable {
    let id: UUID
    let remoteId: UUID?
    let campaignId: UUID
    let mode: SessionMode
    let startedAt: Date
    let endedAt: Date?
    let status: String
    let distanceMeters: Double
    let pathGeoJSON: String?
    let pathGeoJSONNormalized: String?
    let payload: OfflineSessionPayload?
    let createdOffline: Bool
    let updatedAt: Date?
    let syncedAt: Date?
    let points: [LocalSessionPoint]
    let events: [LocalSessionEvent]
}

private struct LocalSessionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_sessions"

    let id: String
    let remoteId: String?
    let campaignId: String
    let mode: String?
    let startedAt: String?
    let endedAt: String?
    let status: String?
    let distanceMeters: Double
    let pathGeoJSON: String?
    let pathGeoJSONNormalized: String?
    let payloadJSON: String?
    let createdOffline: Int
    let updatedAt: String?
    let syncedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case remoteId = "remote_id"
        case campaignId = "campaign_id"
        case mode
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case distanceMeters = "distance_meters"
        case pathGeoJSON = "path_geojson"
        case pathGeoJSONNormalized = "path_geojson_normalized"
        case payloadJSON = "payload_json"
        case createdOffline = "created_offline"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case remoteId = "remote_id"
        case campaignId = "campaign_id"
        case mode
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case distanceMeters = "distance_meters"
        case pathGeoJSON = "path_geojson"
        case pathGeoJSONNormalized = "path_geojson_normalized"
        case payloadJSON = "payload_json"
        case createdOffline = "created_offline"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
    }
}

private struct LocalSessionPointRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_session_points"

    let id: String
    let sessionId: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double?
    let speed: Double?
    let heading: Double?
    let altitude: Double?
    let timestamp: String
    let accepted: Int
    let createdAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case sessionId = "session_id"
        case latitude
        case longitude
        case accuracy
        case speed
        case heading
        case altitude
        case timestamp
        case accepted
        case createdAt = "created_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case latitude
        case longitude
        case accuracy
        case speed
        case heading
        case altitude
        case timestamp
        case accepted
        case createdAt = "created_at"
    }
}

private struct LocalSessionEventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_session_events"

    let id: String
    let sessionId: String
    let campaignId: String
    let entityType: String?
    let entityId: String?
    let eventType: String?
    let payloadJSON: String?
    let occurredAt: String?
    let syncedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case sessionId = "session_id"
        case campaignId = "campaign_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case eventType = "event_type"
        case payloadJSON = "payload_json"
        case occurredAt = "occurred_at"
        case syncedAt = "synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case campaignId = "campaign_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case eventType = "event_type"
        case payloadJSON = "payload_json"
        case occurredAt = "occurred_at"
        case syncedAt = "synced_at"
    }
}

final class SessionRepository {
    static let shared = SessionRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    func createLocalSession(
        id: UUID,
        remoteId: UUID?,
        campaignId: UUID,
        mode: SessionMode,
        startedAt: Date,
        status: String = "active",
        createdOffline: Bool,
        payload: OfflineSessionPayload
    ) async {
        let record = LocalSessionRecord(
            id: id.uuidString,
            remoteId: remoteId?.uuidString,
            campaignId: campaignId.uuidString,
            mode: mode.rawValue,
            startedAt: OfflineDateCodec.string(from: startedAt),
            endedAt: nil,
            status: status,
            distanceMeters: 0,
            pathGeoJSON: nil,
            pathGeoJSONNormalized: nil,
            payloadJSON: OfflineJSONCodec.encode(payload),
            createdOffline: createdOffline ? 1 : 0,
            updatedAt: OfflineDateCodec.string(from: startedAt),
            syncedAt: nil
        )

        try? await dbQueue.write { db in
            try record.save(db)
        }
    }

    func markSessionRemoteCreated(sessionId: UUID, remoteId: UUID? = nil, at date: Date = Date()) async {
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_sessions
                SET remote_id = ?,
                    created_offline = 0,
                    synced_at = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    (remoteId ?? sessionId).uuidString,
                    OfflineDateCodec.string(from: date),
                    OfflineDateCodec.string(from: date),
                    sessionId.uuidString
                ]
            )
        }
    }

    func appendAcceptedPoint(sessionId: UUID, location: CLLocation, accepted: Bool = true) async {
        let record = LocalSessionPointRecord(
            id: UUID().uuidString,
            sessionId: sessionId.uuidString,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil,
            heading: location.course >= 0 ? location.course : nil,
            altitude: location.altitude,
            timestamp: OfflineDateCodec.string(from: location.timestamp),
            accepted: accepted ? 1 : 0,
            createdAt: OfflineDateCodec.string(from: Date())
        )

        try? await dbQueue.write { db in
            try record.insert(db)
        }
    }

    func updateSessionProgress(
        id: UUID,
        distanceMeters: Double,
        pathGeoJSON: String?,
        pathGeoJSONNormalized: String?,
        status: String = "active",
        syncedAt: Date? = nil
    ) async {
        let now = Date()
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_sessions
                SET distance_meters = ?,
                    path_geojson = ?,
                    path_geojson_normalized = ?,
                    status = ?,
                    updated_at = ?,
                    synced_at = COALESCE(?, synced_at)
                WHERE id = ?
                """,
                arguments: [
                    distanceMeters,
                    pathGeoJSON,
                    pathGeoJSONNormalized,
                    status,
                    OfflineDateCodec.string(from: now),
                    syncedAt.map(OfflineDateCodec.string(from:)),
                    id.uuidString
                ]
            )
        }
    }

    func endSession(
        id: UUID,
        endedAt: Date,
        distanceMeters: Double,
        pathGeoJSON: String?,
        pathGeoJSONNormalized: String?
    ) async {
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_sessions
                SET ended_at = ?,
                    status = 'ended',
                    distance_meters = ?,
                    path_geojson = ?,
                    path_geojson_normalized = ?,
                    updated_at = ?
                WHERE id = ?
                """,
                arguments: [
                    OfflineDateCodec.string(from: endedAt),
                    distanceMeters,
                    pathGeoJSON,
                    pathGeoJSONNormalized,
                    OfflineDateCodec.string(from: endedAt),
                    id.uuidString
                ]
            )
        }
    }

    func markSessionSynced(id: UUID, at date: Date = Date()) async {
        let syncedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_sessions
                SET synced_at = ?, updated_at = ?
                WHERE id = ?
                """,
                arguments: [syncedAt, syncedAt, id.uuidString]
            )
        }
    }

    func getActiveSession() async -> LocalSessionSnapshot? {
        try? await dbQueue.read { db in
            guard let record = try LocalSessionRecord
                .filter(Column("ended_at") == nil)
                .order(Column("started_at").desc)
                .fetchOne(db) else {
                return nil
            }

            return try makeSnapshot(from: record, db: db)
        }
    }

    func getSessionPoints(sessionId: UUID) async -> [LocalSessionPoint] {
        (try? await dbQueue.read { db in
            let pointRecords = try LocalSessionPointRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .order(Column("timestamp").asc)
                .fetchAll(db)
            return pointRecords.compactMap(makePoint)
        }) ?? []
    }

    func fetchSessionsForCampaign(campaignId: UUID, limit: Int = 100) async -> [SessionRecord] {
        (try? await dbQueue.read { db in
            let records = try LocalSessionRecord
                .filter(Column("campaign_id") == campaignId.uuidString)
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)

            return records.compactMap { record in
                makeSessionRecord(from: record, db: db)
            }
        }) ?? []
    }

    func fetchSessionRecord(sessionId: UUID) async -> SessionRecord? {
        try? await dbQueue.read { db in
            guard let record = try LocalSessionRecord
                .filter(Column("id") == sessionId.uuidString)
                .fetchOne(db) else {
                return nil
            }

            return makeSessionRecord(from: record, db: db)
        }
    }

    func fetchRecentSessions(limit: Int = 100) async -> [SessionRecord] {
        (try? await dbQueue.read { db in
            let records = try LocalSessionRecord
                .order(Column("started_at").desc)
                .limit(limit)
                .fetchAll(db)

            return records.compactMap { record in
                makeSessionRecord(from: record, db: db)
            }
        }) ?? []
    }

    func addLocalSessionEvent(
        id: UUID = UUID(),
        sessionId: UUID,
        campaignId: UUID,
        entityType: String?,
        entityId: String?,
        eventType: String?,
        payloadJSON: String?,
        occurredAt: Date = Date()
    ) async -> UUID {
        let record = LocalSessionEventRecord(
            id: id.uuidString,
            sessionId: sessionId.uuidString,
            campaignId: campaignId.uuidString,
            entityType: entityType,
            entityId: entityId,
            eventType: eventType,
            payloadJSON: payloadJSON,
            occurredAt: OfflineDateCodec.string(from: occurredAt),
            syncedAt: nil
        )

        try? await dbQueue.write { db in
            try record.insert(db)
        }
        return id
    }

    func markSessionEventSynced(eventId: UUID, at date: Date = Date()) async {
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_session_events
                SET synced_at = ?
                WHERE id = ?
                """,
                arguments: [OfflineDateCodec.string(from: date), eventId.uuidString]
            )
        }
    }

    private func makeSnapshot(from record: LocalSessionRecord, db: Database) throws -> LocalSessionSnapshot? {
        guard let sessionId = UUID(uuidString: record.id),
              let campaignId = UUID(uuidString: record.campaignId),
              let startedAt = OfflineDateCodec.date(from: record.startedAt) else {
            return nil
        }

        let pointRecords = try LocalSessionPointRecord
            .filter(Column("session_id") == record.id)
            .order(Column("timestamp").asc)
            .fetchAll(db)
        let eventRecords = try LocalSessionEventRecord
            .filter(Column("session_id") == record.id)
            .order(Column("occurred_at").asc)
            .fetchAll(db)

        return LocalSessionSnapshot(
            id: sessionId,
            remoteId: record.remoteId.flatMap(UUID.init(uuidString:)),
            campaignId: campaignId,
            mode: SessionMode(rawValue: record.mode ?? "") ?? .doorKnocking,
            startedAt: startedAt,
            endedAt: OfflineDateCodec.date(from: record.endedAt),
            status: record.status ?? "active",
            distanceMeters: record.distanceMeters,
            pathGeoJSON: record.pathGeoJSON,
            pathGeoJSONNormalized: record.pathGeoJSONNormalized,
            payload: OfflineJSONCodec.decode(OfflineSessionPayload.self, from: record.payloadJSON),
            createdOffline: record.createdOffline == 1,
            updatedAt: OfflineDateCodec.date(from: record.updatedAt),
            syncedAt: OfflineDateCodec.date(from: record.syncedAt),
            points: pointRecords.compactMap(makePoint),
            events: eventRecords.compactMap(makeEvent)
        )
    }

    private func makePoint(from record: LocalSessionPointRecord) -> LocalSessionPoint? {
        guard let timestamp = OfflineDateCodec.date(from: record.timestamp),
              let pointId = UUID(uuidString: record.id) else {
            return nil
        }

        return LocalSessionPoint(
            id: pointId,
            coordinate: CLLocationCoordinate2D(latitude: record.latitude, longitude: record.longitude),
            accuracy: record.accuracy,
            speed: record.speed,
            heading: record.heading,
            altitude: record.altitude,
            timestamp: timestamp,
            accepted: record.accepted == 1
        )
    }

    private func makeEvent(from record: LocalSessionEventRecord) -> LocalSessionEvent? {
        guard let eventId = UUID(uuidString: record.id),
              let sessionId = UUID(uuidString: record.sessionId),
              let campaignId = UUID(uuidString: record.campaignId),
              let occurredAt = OfflineDateCodec.date(from: record.occurredAt) else {
            return nil
        }

        return LocalSessionEvent(
            id: eventId,
            sessionId: sessionId,
            campaignId: campaignId,
            entityType: record.entityType,
            entityId: record.entityId,
            eventType: record.eventType,
            payloadJSON: record.payloadJSON,
            occurredAt: occurredAt,
            syncedAt: OfflineDateCodec.date(from: record.syncedAt)
        )
    }

    private func makeSessionRecord(from record: LocalSessionRecord, db: Database) -> SessionRecord? {
        guard let sessionId = UUID(uuidString: record.id),
              let campaignId = UUID(uuidString: record.campaignId),
              let startedAt = OfflineDateCodec.date(from: record.startedAt) else {
            return nil
        }

        let payload = OfflineJSONCodec.decode(OfflineSessionPayload.self, from: record.payloadJSON)
        let endedAt = OfflineDateCodec.date(from: record.endedAt)
        let updatedAt = OfflineDateCodec.date(from: record.updatedAt)
        let activeSeconds = Int((endedAt ?? updatedAt ?? Date()).timeIntervalSince(startedAt).rounded())
        let completedCount = localCompletedCount(sessionId: sessionId.uuidString, db: db)
        let goalType = payload?.goalType ?? GoalType.knocks.rawValue
        let goalAmount = payload?.goalAmount
        let mode = record.mode ?? payload?.sessionMode
        let notes = payload?.notes
        let targetBuildings = payload?.targetBuildings
        let userId = payload.flatMap { UUID(uuidString: $0.userId) } ?? UUID()

        return SessionRecord(
            id: sessionId,
            user_id: userId,
            start_time: startedAt,
            end_time: endedAt,
            doors_hit: nil,
            distance_meters: record.distanceMeters,
            conversations: nil,
            session_mode: mode,
            goal_type: goalType,
            goal_amount: goalAmount,
            path_geojson: record.pathGeoJSON,
            path_geojson_normalized: record.pathGeoJSONNormalized,
            active_seconds: max(activeSeconds, 0),
            created_at: startedAt,
            updated_at: updatedAt,
            campaign_id: campaignId,
            farm_id: payload?.farmExecutionContext?.makeContext()?.farmId,
            farm_touch_id: payload?.farmExecutionContext?.makeContext()?.touchId,
            route_assignment_id: payload?.routeAssignmentId.flatMap(UUID.init(uuidString:)),
            target_building_ids: targetBuildings,
            completed_count: completedCount,
            flyers_delivered: completedCount,
            is_paused: record.status == "paused",
            auto_complete_enabled: payload?.autoCompleteEnabled,
            notes: notes,
            doors_per_hour: nil,
            conversations_per_hour: nil,
            completions_per_km: nil,
            appointments_count: nil,
            appointments_per_conversation: nil,
            leads_created: nil,
            conversations_per_door: nil,
            leads_per_conversation: nil
        )
    }

    private func localCompletedCount(sessionId: String, db: Database) -> Int {
        let eventRecords = (try? LocalSessionEventRecord
            .filter(Column("session_id") == sessionId)
            .order(Column("occurred_at").asc)
            .fetchAll(db)) ?? []

        var count = 0
        for record in eventRecords {
            switch record.eventType {
            case SessionEventType.completionUndone.rawValue:
                count = max(0, count - 1)
            case SessionEventType.flyerLeft.rawValue,
                 SessionEventType.conversation.rawValue,
                 SessionEventType.completedManual.rawValue,
                 SessionEventType.completedAuto.rawValue:
                count += 1
            default:
                continue
            }
        }
        return count
    }
}
