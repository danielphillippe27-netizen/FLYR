import Foundation
import GRDB

struct CachedContactContext: Sendable {
    let contact: Contact
    let userId: UUID?
    let workspaceId: UUID?
}

struct CampaignOfflineContactCounts: Sendable {
    let contacts: Int
    let activities: Int
}

private struct CachedContactRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_contacts"

    let id: String
    let userId: String?
    let workspaceId: String?
    let fullName: String
    let phone: String?
    let email: String?
    let address: String
    let campaignId: String?
    let farmId: String?
    let gersId: String?
    let addressId: String?
    let tags: String?
    let status: String
    let lastContacted: String?
    let notes: String?
    let reminderDate: String?
    let payloadJSON: String?
    let updatedAt: String?
    let dirty: Int
    let syncedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case fullName = "full_name"
        case phone
        case email
        case address
        case campaignId = "campaign_id"
        case farmId = "farm_id"
        case gersId = "gers_id"
        case addressId = "address_id"
        case tags
        case status
        case lastContacted = "last_contacted"
        case notes
        case reminderDate = "reminder_date"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
        case dirty
        case syncedAt = "synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case fullName = "full_name"
        case phone
        case email
        case address
        case campaignId = "campaign_id"
        case farmId = "farm_id"
        case gersId = "gers_id"
        case addressId = "address_id"
        case tags
        case status
        case lastContacted = "last_contacted"
        case notes
        case reminderDate = "reminder_date"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
        case dirty
        case syncedAt = "synced_at"
    }
}

private struct CachedContactActivityRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_contact_activities"

    let id: String
    let contactId: String
    let type: String
    let note: String?
    let timestamp: String
    let createdAt: String?
    let payloadJSON: String?
    let dirty: Int
    let syncedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case contactId = "contact_id"
        case type
        case note
        case timestamp
        case createdAt = "created_at"
        case payloadJSON = "payload_json"
        case dirty
        case syncedAt = "synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "contact_id"
        case type
        case note
        case timestamp
        case createdAt = "created_at"
        case payloadJSON = "payload_json"
        case dirty
        case syncedAt = "synced_at"
    }
}

final class ContactRepository {
    static let shared = ContactRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    func upsertContacts(
        _ contacts: [Contact],
        userId: UUID?,
        workspaceId: UUID?,
        dirty: Bool = false,
        syncedAt: Date? = nil
    ) async {
        guard !contacts.isEmpty else { return }
        let syncedAtString = syncedAt.map(OfflineDateCodec.string(from:))
        try? await dbQueue.write { db in
            for contact in contacts {
                let existing = try CachedContactRecord.fetchOne(db, key: contact.id.uuidString)
                let record = Self.makeRecord(
                    from: contact,
                    userId: userId ?? existing.flatMap { UUID(uuidString: $0.userId ?? "") },
                    workspaceId: workspaceId ?? existing.flatMap { UUID(uuidString: $0.workspaceId ?? "") },
                    dirty: dirty,
                    syncedAt: dirty ? nil : syncedAtString
                )
                try record.save(db)
            }
        }
    }

    func upsertContactLocally(
        _ contact: Contact,
        userId: UUID?,
        workspaceId: UUID?,
        addressId: UUID? = nil
    ) async -> CachedContactContext {
        let normalized = Contact(
            id: contact.id,
            fullName: contact.fullName,
            phone: contact.phone,
            email: contact.email,
            address: contact.address,
            campaignId: contact.campaignId,
            farmId: contact.farmId,
            gersId: contact.gersId,
            addressId: addressId ?? contact.addressId,
            tags: contact.tags,
            status: contact.status,
            lastContacted: contact.lastContacted,
            notes: contact.notes,
            reminderDate: contact.reminderDate,
            createdAt: contact.createdAt,
            updatedAt: Date()
        )

        return (try? await dbQueue.write { db in
            let existing = try CachedContactRecord.fetchOne(db, key: contact.id.uuidString)
            let resolvedUserId = userId ?? existing.flatMap { UUID(uuidString: $0.userId ?? "") }
            let resolvedWorkspaceId = workspaceId ?? existing.flatMap { UUID(uuidString: $0.workspaceId ?? "") }
            let record = Self.makeRecord(
                from: normalized,
                userId: resolvedUserId,
                workspaceId: resolvedWorkspaceId,
                dirty: true,
                syncedAt: nil
            )
            try record.save(db)
            return CachedContactContext(contact: normalized, userId: resolvedUserId, workspaceId: resolvedWorkspaceId)
        }) ?? CachedContactContext(contact: normalized, userId: userId, workspaceId: workspaceId)
    }

    func getContactContext(id: UUID) async -> CachedContactContext? {
        try? await dbQueue.read { db in
            guard let record = try CachedContactRecord.fetchOne(db, key: id.uuidString),
                  let contact = Self.makeContact(from: record) else {
                return nil
            }
            return CachedContactContext(
                contact: contact,
                userId: UUID(uuidString: record.userId ?? ""),
                workspaceId: UUID(uuidString: record.workspaceId ?? "")
            )
        }
    }

    func fetchContacts(userId: UUID, workspaceId: UUID? = nil, filter: ContactFilter? = nil) async -> [Contact] {
        let contacts: [Contact] = (try? await dbQueue.read { db in
            var request = CachedContactRecord.all()
            if let campaignId = filter?.campaignId {
                request = request.filter(Column("campaign_id") == campaignId.uuidString)
            } else if let workspaceId {
                request = request.filter(Column("workspace_id") == workspaceId.uuidString)
            } else {
                request = request.filter(Column("user_id") == userId.uuidString)
            }

            if let filter {
                if let status = filter.status {
                    request = request.filter(Column("status") == status.rawValue)
                }
                if let farmId = filter.farmId {
                    request = request.filter(Column("farm_id") == farmId.uuidString)
                }
            }

            return try request
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .compactMap(Self.makeContact(from:))
        }) ?? []

        guard let searchText = filter?.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty else {
            return contacts
        }

        let needle = searchText.lowercased()
        return contacts.filter { contact in
            let fields = [
                contact.fullName,
                contact.address,
                contact.phone ?? "",
                contact.email ?? "",
                contact.notes ?? ""
            ]
            return fields.contains { $0.lowercased().contains(needle) }
        }
    }

    func fetchContactsForAddress(addressId: UUID) async -> [Contact] {
        (try? await dbQueue.read { db in
            try CachedContactRecord
                .filter(Column("address_id") == addressId.uuidString)
                .order(Column("updated_at").desc)
                .fetchAll(db)
                .compactMap(Self.makeContact(from:))
        }) ?? []
    }

    func addActivityLocally(
        contactId: UUID,
        type: ActivityType,
        note: String?,
        timestamp: Date = Date(),
        id: UUID = UUID()
    ) async -> ContactActivity {
        let activity = ContactActivity(
            id: id,
            contactId: contactId,
            type: type,
            note: note,
            timestamp: timestamp,
            createdAt: timestamp
        )
        let record = CachedContactActivityRecord(
            id: activity.id.uuidString,
            contactId: activity.contactId.uuidString,
            type: activity.type.rawValue,
            note: activity.note,
            timestamp: OfflineDateCodec.string(from: activity.timestamp),
            createdAt: OfflineDateCodec.string(from: activity.createdAt),
            payloadJSON: OfflineJSONCodec.encode(activity),
            dirty: 1,
            syncedAt: nil
        )
        try? await dbQueue.write { db in
            try record.save(db)
        }
        return activity
    }

    func upsertActivities(_ activities: [ContactActivity], dirty: Bool = false, syncedAt: Date? = nil) async {
        guard !activities.isEmpty else { return }
        let syncedAtString = syncedAt.map(OfflineDateCodec.string(from:))
        try? await dbQueue.write { db in
            for activity in activities {
                let record = CachedContactActivityRecord(
                    id: activity.id.uuidString,
                    contactId: activity.contactId.uuidString,
                    type: activity.type.rawValue,
                    note: activity.note,
                    timestamp: OfflineDateCodec.string(from: activity.timestamp),
                    createdAt: OfflineDateCodec.string(from: activity.createdAt),
                    payloadJSON: OfflineJSONCodec.encode(activity),
                    dirty: dirty ? 1 : 0,
                    syncedAt: dirty ? nil : syncedAtString
                )
                try record.save(db)
            }
        }
    }

    func fetchActivities(contactId: UUID) async -> [ContactActivity] {
        (try? await dbQueue.read { db in
            try CachedContactActivityRecord
                .filter(Column("contact_id") == contactId.uuidString)
                .order(Column("timestamp").desc)
                .fetchAll(db)
                .compactMap(Self.makeActivity(from:))
        }) ?? []
    }

    func getOfflineCounts(campaignId: UUID) async -> CampaignOfflineContactCounts {
        (try? await dbQueue.read { db in
            let contactRecords = try CachedContactRecord
                .filter(Column("campaign_id") == campaignId.uuidString)
                .fetchAll(db)
            let contactIDs = contactRecords.map(\.id)
            let activities: Int
            if contactIDs.isEmpty {
                activities = 0
            } else {
                activities = try CachedContactActivityRecord
                    .filter(contactIDs.contains(Column("contact_id")))
                    .fetchCount(db)
            }

            return CampaignOfflineContactCounts(
                contacts: contactRecords.count,
                activities: activities
            )
        }) ?? CampaignOfflineContactCounts(contacts: 0, activities: 0)
    }

    func markContactsSynced(ids: [UUID], at date: Date = Date()) async {
        guard !ids.isEmpty else { return }
        let syncedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE cached_contacts
                SET dirty = 0, synced_at = ?, updated_at = COALESCE(updated_at, ?)
                WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments([syncedAt, syncedAt] + ids.map(\.uuidString))
            )
        }
    }

    func markActivitiesSynced(ids: [UUID], at date: Date = Date()) async {
        guard !ids.isEmpty else { return }
        let syncedAt = OfflineDateCodec.string(from: date)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE cached_contact_activities
                SET dirty = 0, synced_at = ?
                WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments([syncedAt] + ids.map(\.uuidString))
            )
        }
    }

    func deleteContacts(ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        try? await dbQueue.write { db in
            let contactIds = ids.map(\.uuidString)
            try db.execute(
                sql: """
                DELETE FROM cached_contact_activities
                WHERE contact_id IN (\(contactIds.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments(contactIds)
            )
            try db.execute(
                sql: """
                DELETE FROM cached_contacts
                WHERE id IN (\(contactIds.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments(contactIds)
            )
        }
    }

    func deleteContactsForAddress(addressId: UUID) async -> [Contact] {
        let contacts = await fetchContactsForAddress(addressId: addressId)
        await deleteContacts(ids: contacts.map(\.id))
        return contacts
    }

    private static func makeRecord(
        from contact: Contact,
        userId: UUID?,
        workspaceId: UUID?,
        dirty: Bool,
        syncedAt: String?
    ) -> CachedContactRecord {
        CachedContactRecord(
            id: contact.id.uuidString,
            userId: userId?.uuidString,
            workspaceId: workspaceId?.uuidString,
            fullName: contact.fullName,
            phone: contact.phone,
            email: contact.email,
            address: contact.address,
            campaignId: contact.campaignId?.uuidString,
            farmId: contact.farmId?.uuidString,
            gersId: contact.gersId,
            addressId: contact.addressId?.uuidString,
            tags: contact.tags,
            status: contact.status.rawValue,
            lastContacted: contact.lastContacted.map(OfflineDateCodec.string(from:)),
            notes: contact.notes,
            reminderDate: contact.reminderDate.map(OfflineDateCodec.string(from:)),
            payloadJSON: OfflineJSONCodec.encode(contact),
            updatedAt: OfflineDateCodec.string(from: contact.updatedAt),
            dirty: dirty ? 1 : 0,
            syncedAt: syncedAt
        )
    }

    private static func makeContact(from record: CachedContactRecord) -> Contact? {
        if let decoded = OfflineJSONCodec.decode(Contact.self, from: record.payloadJSON) {
            return decoded
        }

        return Contact(
            id: UUID(uuidString: record.id) ?? UUID(),
            fullName: record.fullName,
            phone: record.phone,
            email: record.email,
            address: record.address,
            campaignId: UUID(uuidString: record.campaignId ?? ""),
            farmId: UUID(uuidString: record.farmId ?? ""),
            gersId: record.gersId,
            addressId: UUID(uuidString: record.addressId ?? ""),
            tags: record.tags,
            status: ContactStatus(rawValue: record.status) ?? .new,
            lastContacted: OfflineDateCodec.date(from: record.lastContacted),
            notes: record.notes,
            reminderDate: OfflineDateCodec.date(from: record.reminderDate),
            createdAt: OfflineDateCodec.date(from: record.updatedAt) ?? Date(),
            updatedAt: OfflineDateCodec.date(from: record.updatedAt) ?? Date()
        )
    }

    private static func makeActivity(from record: CachedContactActivityRecord) -> ContactActivity? {
        if let decoded = OfflineJSONCodec.decode(ContactActivity.self, from: record.payloadJSON) {
            return decoded
        }

        guard let contactId = UUID(uuidString: record.contactId) else { return nil }
        return ContactActivity(
            id: UUID(uuidString: record.id) ?? UUID(),
            contactId: contactId,
            type: ActivityType(rawValue: record.type) ?? .note,
            note: record.note,
            timestamp: OfflineDateCodec.date(from: record.timestamp) ?? Date(),
            createdAt: OfflineDateCodec.date(from: record.createdAt) ?? Date()
        )
    }
}
