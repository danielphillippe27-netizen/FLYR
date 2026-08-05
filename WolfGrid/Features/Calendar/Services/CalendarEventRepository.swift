import Foundation
import GRDB

private struct CachedCalendarEventRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_calendar_events"

    let id: String
    let userId: String?
    let workspaceId: String?
    let title: String
    let startAt: String
    let endAt: String
    let isAllDay: Int
    let eventType: String
    let contactId: String?
    let contactName: String?
    let contactAddress: String?
    let campaignId: String?
    let campaignName: String?
    let recurrenceRule: String?
    let recurrenceUntil: String?
    let sourceKind: String?
    let sourceId: String?
    let notes: String?
    let location: String?
    let colorKey: String
    let payloadJSON: String?
    let createdAt: String
    let updatedAt: String
    let deletedAt: String?
    let dirty: Int
    let syncedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case eventType = "event_type"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case contactAddress = "contact_address"
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case recurrenceRule = "recurrence_rule"
        case recurrenceUntil = "recurrence_until"
        case sourceKind = "source_kind"
        case sourceId = "source_id"
        case notes
        case location
        case colorKey = "color_key"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case dirty
        case syncedAt = "synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case isAllDay = "is_all_day"
        case eventType = "event_type"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case contactAddress = "contact_address"
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case recurrenceRule = "recurrence_rule"
        case recurrenceUntil = "recurrence_until"
        case sourceKind = "source_kind"
        case sourceId = "source_id"
        case notes
        case location
        case colorKey = "color_key"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case dirty
        case syncedAt = "synced_at"
    }
}

final class CalendarEventRepository {
    static let shared = CalendarEventRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    func fetchEvents(userId: UUID, workspaceId: UUID?, start: Date, end: Date, includeDeleted: Bool = false) async -> [FlyrCalendarEvent] {
        (try? await dbQueue.read { db in
            var request = CachedCalendarEventRecord
                .filter(Column("start_at") < OfflineDateCodec.string(from: end))

            // workspaceId is metadata only for personal calendar events.
            request = request.filter(Column("user_id") == userId.uuidString)
            if !includeDeleted {
                request = request.filter(Column("deleted_at") == nil)
            }

            return try request
                .order(Column("start_at").asc)
                .fetchAll(db)
                .compactMap(Self.makeEvent(from:))
        }) ?? []
    }

    func fetchEvent(id: UUID) async -> FlyrCalendarEvent? {
        try? await dbQueue.read { db in
            try CachedCalendarEventRecord
                .fetchOne(db, key: id.uuidString)
                .flatMap(Self.makeEvent(from:))
        }
    }

    func upsertEvents(_ events: [FlyrCalendarEvent], dirty: Bool = false, syncedAt: Date? = nil) async {
        guard !events.isEmpty else { return }
        let syncedAtString = syncedAt.map(OfflineDateCodec.string(from:))
        try? await dbQueue.write { db in
            for event in events {
                try Self.makeRecord(from: event, dirty: dirty, syncedAt: dirty ? nil : syncedAtString).save(db)
            }
        }
    }

    func upsertEventLocally(_ event: FlyrCalendarEvent, userId: UUID?, workspaceId: UUID?) async -> FlyrCalendarEvent {
        let normalized = FlyrCalendarEvent(
            id: event.id,
            userId: event.userId ?? userId,
            workspaceId: event.workspaceId ?? workspaceId,
            title: event.title,
            startAt: event.startAt,
            endAt: event.endAt,
            isAllDay: event.isAllDay,
            eventType: event.eventType,
            contactId: event.contactId,
            contactName: event.contactName,
            contactAddress: event.contactAddress,
            campaignId: event.campaignId,
            campaignName: event.campaignName,
            recurrenceRule: event.recurrenceRule,
            recurrenceUntil: event.recurrenceUntil,
            sourceKind: event.sourceKind,
            sourceId: event.sourceId,
            notes: event.notes,
            location: event.location,
            colorKey: event.colorKey,
            createdAt: event.createdAt,
            updatedAt: Date(),
            deletedAt: event.deletedAt
        )
        await upsertEvents([normalized], dirty: true, syncedAt: nil)
        return normalized
    }

    func softDeleteEventLocally(id: UUID) async -> FlyrCalendarEvent? {
        try? await dbQueue.write { db in
            guard var event = try CachedCalendarEventRecord.fetchOne(db, key: id.uuidString).flatMap(Self.makeEvent(from:)) else {
                return nil
            }
            event.deletedAt = Date()
            event.updatedAt = Date()
            try Self.makeRecord(from: event, dirty: true, syncedAt: nil).save(db)
            return event
        }
    }

    func markEventsSynced(ids: [UUID], at date: Date = Date()) async {
        guard !ids.isEmpty else { return }
        let syncedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE cached_calendar_events
                SET dirty = 0, synced_at = ?, updated_at = COALESCE(updated_at, ?)
                WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments([syncedAt, syncedAt] + ids.map(\.uuidString))
            )
        }
    }

    private static func makeRecord(from event: FlyrCalendarEvent, dirty: Bool, syncedAt: String?) -> CachedCalendarEventRecord {
        CachedCalendarEventRecord(
            id: event.id.uuidString,
            userId: event.userId?.uuidString,
            workspaceId: event.workspaceId?.uuidString,
            title: event.title,
            startAt: OfflineDateCodec.string(from: event.startAt),
            endAt: OfflineDateCodec.string(from: event.endAt),
            isAllDay: event.isAllDay ? 1 : 0,
            eventType: event.eventType,
            contactId: event.contactId?.uuidString,
            contactName: event.contactName,
            contactAddress: event.contactAddress,
            campaignId: event.campaignId?.uuidString,
            campaignName: event.campaignName,
            recurrenceRule: event.recurrenceRule,
            recurrenceUntil: event.recurrenceUntil.map(OfflineDateCodec.string(from:)),
            sourceKind: event.sourceKind,
            sourceId: event.sourceId?.uuidString,
            notes: event.notes,
            location: event.location,
            colorKey: event.colorKey,
            payloadJSON: OfflineJSONCodec.encode(event),
            createdAt: OfflineDateCodec.string(from: event.createdAt),
            updatedAt: OfflineDateCodec.string(from: event.updatedAt),
            deletedAt: event.deletedAt.map(OfflineDateCodec.string(from:)),
            dirty: dirty ? 1 : 0,
            syncedAt: syncedAt
        )
    }

    private static func makeEvent(from record: CachedCalendarEventRecord) -> FlyrCalendarEvent? {
        if let decoded = OfflineJSONCodec.decode(FlyrCalendarEvent.self, from: record.payloadJSON) {
            return decoded
        }
        guard let id = UUID(uuidString: record.id),
              let start = OfflineDateCodec.date(from: record.startAt),
              let end = OfflineDateCodec.date(from: record.endAt),
              let created = OfflineDateCodec.date(from: record.createdAt),
              let updated = OfflineDateCodec.date(from: record.updatedAt) else {
            return nil
        }

        return FlyrCalendarEvent(
            id: id,
            userId: record.userId.flatMap(UUID.init(uuidString:)),
            workspaceId: record.workspaceId.flatMap(UUID.init(uuidString:)),
            title: record.title,
            startAt: start,
            endAt: end,
            isAllDay: record.isAllDay == 1,
            eventType: record.eventType,
            contactId: record.contactId.flatMap(UUID.init(uuidString:)),
            contactName: record.contactName,
            contactAddress: record.contactAddress,
            campaignId: record.campaignId.flatMap(UUID.init(uuidString:)),
            campaignName: record.campaignName,
            recurrenceRule: record.recurrenceRule ?? CalendarRecurrenceRule.none.rawValue,
            recurrenceUntil: OfflineDateCodec.date(from: record.recurrenceUntil),
            sourceKind: record.sourceKind,
            sourceId: record.sourceId.flatMap(UUID.init(uuidString:)),
            notes: record.notes,
            location: record.location,
            colorKey: record.colorKey,
            createdAt: created,
            updatedAt: updated,
            deletedAt: OfflineDateCodec.date(from: record.deletedAt)
        )
    }
}
