import Foundation
import GRDB

private struct CachedFarmRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_farms"

    let id: String
    let userId: String
    let workspaceId: String?
    let isActive: Int
    let createdAt: String?
    let updatedAt: String?
    let payloadJSON: String
    let cachedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case workspaceId = "workspace_id"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }
}

private struct CachedFarmTouchRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_farm_touches"

    let id: String
    let farmId: String
    let campaignId: String?
    let cycleNumber: Int?
    let date: String?
    let orderIndex: Int?
    let completed: Int
    let dirty: Int
    let payloadJSON: String
    let cachedAt: String?
    let syncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case campaignId = "campaign_id"
        case cycleNumber = "cycle_number"
        case date
        case orderIndex = "order_index"
        case completed
        case dirty
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
        case syncedAt = "synced_at"
    }
}

private struct CachedFarmLeadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_farm_leads"

    let id: String
    let farmId: String
    let touchId: String?
    let createdAt: String?
    let payloadJSON: String
    let cachedAt: String?
    let dirty: Int
    let syncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case touchId = "touch_id"
        case createdAt = "created_at"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
        case dirty
        case syncedAt = "synced_at"
    }
}

private struct CachedFarmAddressRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_farm_addresses"

    let id: String
    let farmId: String
    let campaignId: String?
    let campaignAddressId: String?
    let streetName: String?
    let houseNumber: String?
    let createdAt: String?
    let payloadJSON: String
    let cachedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case campaignId = "campaign_id"
        case campaignAddressId = "campaign_address_id"
        case streetName = "street_name"
        case houseNumber = "house_number"
        case createdAt = "created_at"
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
    }
}

private struct CachedFarmAddressStatusRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_farm_touch_address_statuses"

    let id: String
    let farmId: String
    let farmTouchId: String?
    let cycleNumber: Int?
    let addressId: String
    let status: String
    let notes: String?
    let occurredAt: String
    let dirty: Int
    let payloadJSON: String?
    let cachedAt: String?
    let syncedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case farmId = "farm_id"
        case farmTouchId = "farm_touch_id"
        case cycleNumber = "cycle_number"
        case addressId = "address_id"
        case status
        case notes
        case occurredAt = "occurred_at"
        case dirty
        case payloadJSON = "payload_json"
        case cachedAt = "cached_at"
        case syncedAt = "synced_at"
    }
}

final class FarmOfflineRepository {
    static let shared = FarmOfflineRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    func upsertFarms(_ farms: [Farm], userId: UUID, workspaceId: UUID?) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for farm in farms {
                guard let payloadJSON = OfflineJSONCodec.encode(farm) else { continue }
                let record = CachedFarmRecord(
                    id: farm.id.uuidString,
                    userId: farm.userId.uuidString,
                    workspaceId: farm.workspaceId?.uuidString ?? workspaceId?.uuidString,
                    isActive: farm.isActive ? 1 : 0,
                    createdAt: OfflineDateCodec.string(from: farm.createdAt),
                    updatedAt: farm.updatedAt.map(OfflineDateCodec.string(from:)),
                    payloadJSON: payloadJSON,
                    cachedAt: cachedAt
                )
                try record.save(db)
            }
        }
    }

    func upsertFarm(_ farm: Farm) async {
        await upsertFarms([farm], userId: farm.userId, workspaceId: farm.workspaceId)
    }

    func getCachedFarms(userId: UUID, workspaceId: UUID?) async -> [Farm] {
        (try? await dbQueue.read { db in
            var request = CachedFarmRecord.filter(Column("user_id") == userId.uuidString)
            if let workspaceId {
                request = request.filter(Column("workspace_id") == workspaceId.uuidString || Column("workspace_id") == nil)
            }

            return try request
                .order(Column("created_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(Farm.self, from: $0.payloadJSON) }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        }) ?? []
    }

    func getCachedFarm(id: UUID) async -> Farm? {
        try? await dbQueue.read { db in
            guard let record = try CachedFarmRecord.fetchOne(db, key: id.uuidString) else { return nil }
            return OfflineJSONCodec.decode(Farm.self, from: record.payloadJSON)
        }
    }

    func upsertTouches(_ touches: [FarmTouch], dirty: Bool = false, syncedAt: Date? = Date()) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for touch in touches {
                guard let payloadJSON = OfflineJSONCodec.encode(touch) else { continue }
                let record = CachedFarmTouchRecord(
                    id: touch.id.uuidString,
                    farmId: touch.farmId.uuidString,
                    campaignId: touch.campaignId?.uuidString,
                    cycleNumber: touch.cycleNumber,
                    date: OfflineDateCodec.string(from: touch.date),
                    orderIndex: touch.orderIndex,
                    completed: touch.completed ? 1 : 0,
                    dirty: dirty ? 1 : 0,
                    payloadJSON: payloadJSON,
                    cachedAt: cachedAt,
                    syncedAt: syncedAt.map(OfflineDateCodec.string(from:))
                )
                try record.save(db)
            }
        }
    }

    func getCachedTouches(farmId: UUID) async -> [FarmTouch] {
        (try? await dbQueue.read { db in
            try CachedFarmTouchRecord
                .filter(Column("farm_id") == farmId.uuidString)
                .order(Column("date").asc, Column("order_index").asc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(FarmTouch.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func getCachedTouch(id: UUID) async -> FarmTouch? {
        try? await dbQueue.read { db in
            guard let record = try CachedFarmTouchRecord.fetchOne(db, key: id.uuidString) else { return nil }
            return OfflineJSONCodec.decode(FarmTouch.self, from: record.payloadJSON)
        }
    }

    func markTouchSynced(id: UUID, touch: FarmTouch? = nil, at date: Date = Date()) async {
        if let touch {
            await upsertTouches([touch], dirty: false, syncedAt: date)
        } else {
            let syncedAt = OfflineDateCodec.string(from: date)
            try? await dbQueue.write { db in
                try db.execute(
                    sql: """
                    UPDATE cached_farm_touches
                    SET dirty = 0,
                        synced_at = ?
                    WHERE id = ?
                    """,
                    arguments: [syncedAt, id.uuidString]
                )
            }
        }
    }

    func upsertLeads(_ leads: [FarmLead], dirty: Bool = false, syncedAt: Date? = Date()) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        let syncedAtString = syncedAt.map(OfflineDateCodec.string(from:))
        try? await dbQueue.write { db in
            for lead in leads {
                guard let payloadJSON = OfflineJSONCodec.encode(lead) else { continue }
                let record = CachedFarmLeadRecord(
                    id: lead.id.uuidString,
                    farmId: lead.farmId.uuidString,
                    touchId: lead.touchId?.uuidString,
                    createdAt: OfflineDateCodec.string(from: lead.createdAt),
                    payloadJSON: payloadJSON,
                    cachedAt: cachedAt,
                    dirty: dirty ? 1 : 0,
                    syncedAt: dirty ? nil : syncedAtString
                )
                try record.save(db)
            }
        }
    }

    func getCachedLeads(farmId: UUID) async -> [FarmLead] {
        (try? await dbQueue.read { db in
            try CachedFarmLeadRecord
                .filter(Column("farm_id") == farmId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(FarmLead.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func getCachedLeads(touchId: UUID) async -> [FarmLead] {
        (try? await dbQueue.read { db in
            try CachedFarmLeadRecord
                .filter(Column("touch_id") == touchId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(FarmLead.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func getCachedLead(id: UUID) async -> FarmLead? {
        try? await dbQueue.read { db in
            guard let record = try CachedFarmLeadRecord.fetchOne(db, key: id.uuidString) else { return nil }
            return OfflineJSONCodec.decode(FarmLead.self, from: record.payloadJSON)
        }
    }

    func deleteCachedLead(id: UUID) async {
        try? await dbQueue.write { db in
            _ = try CachedFarmLeadRecord.deleteOne(db, key: id.uuidString)
        }
    }

    func markLeadSynced(id: UUID, lead: FarmLead? = nil, at date: Date = Date()) async {
        if let lead {
            await upsertLeads([lead], dirty: false, syncedAt: date)
        } else {
            let syncedAt = OfflineDateCodec.string(from: date)
            try? await dbQueue.write { db in
                try db.execute(
                    sql: """
                    UPDATE cached_farm_leads
                    SET dirty = 0,
                        synced_at = ?
                    WHERE id = ?
                    """,
                    arguments: [syncedAt, id.uuidString]
                )
            }
        }
    }

    func upsertAddresses(_ addresses: [FarmAddressViewRow]) async {
        let cachedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for address in addresses {
                guard let payloadJSON = OfflineJSONCodec.encode(address) else { continue }
                let record = CachedFarmAddressRecord(
                    id: address.id.uuidString,
                    farmId: address.farmId.uuidString,
                    campaignId: address.campaignId?.uuidString,
                    campaignAddressId: address.campaignAddressId?.uuidString,
                    streetName: address.streetName,
                    houseNumber: address.houseNumber,
                    createdAt: OfflineDateCodec.string(from: address.createdAt),
                    payloadJSON: payloadJSON,
                    cachedAt: cachedAt
                )
                try record.save(db)
            }
        }
    }

    func getCachedAddresses(farmId: UUID) async -> [FarmAddressViewRow] {
        (try? await dbQueue.read { db in
            try CachedFarmAddressRecord
                .filter(Column("farm_id") == farmId.uuidString)
                .order(Column("street_name").asc, Column("house_number").asc, Column("created_at").asc)
                .fetchAll(db)
                .compactMap { OfflineJSONCodec.decode(FarmAddressViewRow.self, from: $0.payloadJSON) }
        }) ?? []
    }

    func upsertCycleStatuses(
        farmId: UUID,
        cycleNumber: Int,
        statuses: [UUID: AddressStatus],
        dirty: Bool = false
    ) async {
        let now = Date()
        let cachedAt = OfflineDateCodec.string(from: now)
        try? await dbQueue.write { db in
            for (addressId, status) in statuses {
                let recordId = Self.statusRecordId(farmId: farmId, cycleNumber: cycleNumber, addressId: addressId)
                let record = CachedFarmAddressStatusRecord(
                    id: recordId,
                    farmId: farmId.uuidString,
                    farmTouchId: nil,
                    cycleNumber: cycleNumber,
                    addressId: addressId.uuidString,
                    status: status.rawValue,
                    notes: nil,
                    occurredAt: cachedAt,
                    dirty: dirty ? 1 : 0,
                    payloadJSON: nil,
                    cachedAt: cachedAt,
                    syncedAt: dirty ? nil : cachedAt
                )
                try record.save(db)
            }
        }
    }

    func getCachedCycleStatuses(farmId: UUID, cycleNumber: Int) async -> [UUID: AddressStatus] {
        (try? await dbQueue.read { db in
            let records = try CachedFarmAddressStatusRecord
                .filter(Column("farm_id") == farmId.uuidString)
                .filter(Column("cycle_number") == cycleNumber)
                .order(Column("occurred_at").desc, Column("cached_at").desc)
                .fetchAll(db)

            var statuses: [UUID: AddressStatus] = [:]
            for record in records {
                guard let addressId = UUID(uuidString: record.addressId),
                      statuses[addressId] == nil else { continue }
                statuses[addressId] = AddressStatus(rawValue: record.status) ?? AddressStatus.none
            }
            return statuses
        }) ?? [:]
    }

    func recordAddressOutcome(
        context: FarmExecutionContext,
        addressId: UUID,
        status: AddressStatus,
        notes: String?,
        occurredAt: Date,
        dirty: Bool
    ) async {
        let occurredAtString = OfflineDateCodec.string(from: occurredAt)
        let recordId = Self.statusRecordId(
            farmId: context.farmId,
            farmTouchId: context.touchId,
            cycleNumber: context.cycleNumber,
            addressId: addressId
        )
        let payload = FarmAddressOutcomeOutboxPayload(
            farmExecutionContext: OfflineFarmExecutionPayload(context: context),
            addressId: addressId.uuidString,
            status: status.rawValue,
            notes: notes,
            occurredAt: occurredAtString
        )
        try? await dbQueue.write { db in
            let record = CachedFarmAddressStatusRecord(
                id: recordId,
                farmId: context.farmId.uuidString,
                farmTouchId: context.touchId.uuidString,
                cycleNumber: context.cycleNumber,
                addressId: addressId.uuidString,
                status: status.rawValue,
                notes: notes,
                occurredAt: occurredAtString,
                dirty: dirty ? 1 : 0,
                payloadJSON: OfflineJSONCodec.encode(payload),
                cachedAt: OfflineDateCodec.string(from: Date()),
                syncedAt: dirty ? nil : occurredAtString
            )
            try record.save(db)
        }

        await updateCachedAddressStatus(farmId: context.farmId, addressId: addressId, status: status, occurredAt: occurredAt)
    }

    func markAddressOutcomeSynced(
        context: FarmExecutionContext,
        addressId: UUID,
        at date: Date = Date()
    ) async {
        let syncedAt = OfflineDateCodec.string(from: date)
        let recordId = Self.statusRecordId(
            farmId: context.farmId,
            farmTouchId: context.touchId,
            cycleNumber: context.cycleNumber,
            addressId: addressId
        )
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE cached_farm_touch_address_statuses
                SET dirty = 0,
                    synced_at = ?
                WHERE id = ?
                """,
                arguments: [syncedAt, recordId]
            )
        }
    }

    private func updateCachedAddressStatus(
        farmId: UUID,
        addressId: UUID,
        status: AddressStatus,
        occurredAt: Date
    ) async {
        try? await dbQueue.write { db in
            guard let record = try CachedFarmAddressRecord.fetchOne(db, key: addressId.uuidString),
                  let existing = OfflineJSONCodec.decode(FarmAddressViewRow.self, from: record.payloadJSON),
                  existing.farmId == farmId else {
                return
            }

            let updated = FarmAddressViewRow(
                farmAddressId: existing.farmAddressId,
                campaignAddressId: existing.campaignAddressId,
                farmId: existing.farmId,
                campaignId: existing.campaignId,
                gersId: existing.gersId,
                formatted: existing.formatted,
                postalCode: existing.postalCode,
                source: existing.source,
                houseNumber: existing.houseNumber,
                streetName: existing.streetName,
                locality: existing.locality,
                region: existing.region,
                visitedCount: max(existing.visitedCount, 1),
                lastVisitedAt: occurredAt,
                lastOutcomeStatus: status.rawValue,
                geomJson: existing.geomJson,
                createdAt: existing.createdAt
            )
            guard let payloadJSON = OfflineJSONCodec.encode(updated) else { return }
            let updatedRecord = CachedFarmAddressRecord(
                id: record.id,
                farmId: record.farmId,
                campaignId: record.campaignId,
                campaignAddressId: record.campaignAddressId,
                streetName: record.streetName,
                houseNumber: record.houseNumber,
                createdAt: record.createdAt,
                payloadJSON: payloadJSON,
                cachedAt: OfflineDateCodec.string(from: Date())
            )
            try updatedRecord.save(db)
        }
    }

    private static func statusRecordId(
        farmId: UUID,
        farmTouchId: UUID? = nil,
        cycleNumber: Int?,
        addressId: UUID
    ) -> String {
        [
            farmId.uuidString.lowercased(),
            farmTouchId?.uuidString.lowercased() ?? "cycle-\(cycleNumber ?? 0)",
            addressId.uuidString.lowercased()
        ].joined(separator: ":")
    }
}
