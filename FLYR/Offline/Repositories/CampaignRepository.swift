import Foundation
import GRDB
import CoreLocation

struct CampaignDownloadState: Codable, Equatable, Sendable {
    let campaignId: String
    let status: String
    let progress: Double
    let startedAt: Date?
    let completedAt: Date?
    let errorMessage: String?
    let lastSyncedAt: Date?

    var isAvailableOffline: Bool {
        status == "ready"
    }
}

struct OfflineCampaignMapBundle: Sendable {
    let buildings: BuildingFeatureCollection
    let addresses: AddressFeatureCollection
    let roads: RoadFeatureCollection
    let silverBuildingLinks: [String: [String]]
}

struct CampaignOfflineAssetCounts: Sendable {
    let buildings: Int
    let addresses: Int
    let buildingLinks: Int
    let statuses: Int
    let roads: Int
    let metadata: Int
}

struct AddressCaptureMetadata: Sendable {
    let campaignId: UUID
    let addressId: UUID
    let contactName: String?
    let leadStatus: String?
    let productInterest: String?
    let followUpDate: Date?
    let rawTranscript: String?
    let aiSummary: String?
    let updatedAt: Date?
    let dirty: Bool
}

struct OfflineDeletedBuildingSnapshot: Sendable {
    let buildingIdentifiers: [String]
    let deletedAddressIds: [String]
}

private struct CachedCampaignRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_campaigns"

    let id: String
    let name: String?
    let mode: String?
    let boundaryGeoJSON: String?
    let payloadJSON: String?
    let downloadedAt: String?
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case name
        case mode
        case boundaryGeoJSON = "boundary_geojson"
        case payloadJSON = "payload_json"
        case downloadedAt = "downloaded_at"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case boundaryGeoJSON = "boundary_geojson"
        case payloadJSON = "payload_json"
        case downloadedAt = "downloaded_at"
        case updatedAt = "updated_at"
    }
}

private struct CachedBuildingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_buildings"

    let id: String
    let campaignId: String
    let sourceId: String?
    let externalId: String?
    let geometryGeoJSON: String
    let propertiesJSON: String?
    let payloadJSON: String?
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case sourceId = "source_id"
        case externalId = "external_id"
        case geometryGeoJSON = "geometry_geojson"
        case propertiesJSON = "properties_json"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case sourceId = "source_id"
        case externalId = "external_id"
        case geometryGeoJSON = "geometry_geojson"
        case propertiesJSON = "properties_json"
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }
}

private struct CachedAddressRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_addresses"

    let id: String
    let campaignId: String
    let buildingId: String?
    let address: String?
    let unit: String?
    let city: String?
    let province: String?
    let postalCode: String?
    let latitude: Double?
    let longitude: Double?
    let payloadJSON: String?
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case buildingId = "building_id"
        case address
        case unit
        case city
        case province
        case postalCode = "postal_code"
        case latitude
        case longitude
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case buildingId = "building_id"
        case address
        case unit
        case city
        case province
        case postalCode = "postal_code"
        case latitude
        case longitude
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
    }
}

private struct CachedBuildingAddressLinkRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_building_address_links"

    let id: String
    let campaignId: String
    let buildingId: String
    let addressId: String
    let confidence: Double?
    let source: String?
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case buildingId = "building_id"
        case addressId = "address_id"
        case confidence
        case source
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case buildingId = "building_id"
        case addressId = "address_id"
        case confidence
        case source
        case updatedAt = "updated_at"
    }
}

private struct CachedAddressStatusRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_address_statuses"

    let id: String
    let campaignId: String
    let addressId: String?
    let buildingId: String?
    let status: String?
    let outcome: String?
    let notes: String?
    let payloadJSON: String?
    let updatedAt: String?
    let dirty: Int

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case buildingId = "building_id"
        case status
        case outcome
        case notes
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
        case dirty
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case buildingId = "building_id"
        case status
        case outcome
        case notes
        case payloadJSON = "payload_json"
        case updatedAt = "updated_at"
        case dirty
    }
}

private struct CachedRoadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_roads"

    let id: String
    let campaignId: String
    let geometryGeoJSON: String
    let propertiesJSON: String?
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case geometryGeoJSON = "geometry_geojson"
        case propertiesJSON = "properties_json"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case geometryGeoJSON = "geometry_geojson"
        case propertiesJSON = "properties_json"
        case updatedAt = "updated_at"
    }
}

private struct CampaignDownloadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "campaign_downloads"

    let campaignId: String
    let status: String?
    let progress: Double
    let startedAt: String?
    let completedAt: String?
    let errorMessage: String?
    let lastSyncedAt: String?

    enum Columns: String, ColumnExpression {
        case campaignId = "campaign_id"
        case status
        case progress
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case errorMessage = "error_message"
        case lastSyncedAt = "last_synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case status
        case progress
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case errorMessage = "error_message"
        case lastSyncedAt = "last_synced_at"
    }
}

private struct CachedAddressCaptureMetadataRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_address_capture_metadata"

    let id: String
    let campaignId: String
    let addressId: String
    let contactName: String?
    let leadStatus: String?
    let productInterest: String?
    let followUpDate: String?
    let rawTranscript: String?
    let aiSummary: String?
    let updatedAt: String?
    let dirty: Int

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case contactName = "contact_name"
        case leadStatus = "lead_status"
        case productInterest = "product_interest"
        case followUpDate = "follow_up_date"
        case rawTranscript = "raw_transcript"
        case aiSummary = "ai_summary"
        case updatedAt = "updated_at"
        case dirty
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case contactName = "contact_name"
        case leadStatus = "lead_status"
        case productInterest = "product_interest"
        case followUpDate = "follow_up_date"
        case rawTranscript = "raw_transcript"
        case aiSummary = "ai_summary"
        case updatedAt = "updated_at"
        case dirty
    }
}

extension AddressStatusRow {
    init(
        id: UUID,
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        lastVisitedAt: Date?,
        notes: String?,
        visitCount: Int,
        lastActionBy: UUID?,
        lastSessionId: UUID?,
        lastHomeEventId: UUID?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.addressId = addressId
        self.campaignId = campaignId
        self.status = status
        self.lastVisitedAt = lastVisitedAt
        self.notes = notes
        self.visitCount = visitCount
        self.lastActionBy = lastActionBy
        self.lastSessionId = lastSessionId
        self.lastHomeEventId = lastHomeEventId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension AddressStatusRow: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(addressId, forKey: .addressId)
        try container.encode(campaignId, forKey: .campaignId)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(lastVisitedAt, forKey: .lastVisitedAt)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(visitCount, forKey: .visitCount)
        try container.encodeIfPresent(lastActionBy, forKey: .lastActionBy)
        try container.encodeIfPresent(lastSessionId, forKey: .lastSessionId)
        try container.encodeIfPresent(lastHomeEventId, forKey: .lastHomeEventId)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

final class CampaignRepository {
    static let shared = CampaignRepository()

    private let dbQueue = OfflineDatabase.shared.dbQueue

    private init() {}

    func upsertCampaign(
        id: String,
        name: String?,
        mode: String?,
        boundaryGeoJSON: String?,
        payloadJSON: String?,
        downloadedAt: Date?,
        updatedAt: Date = Date()
    ) async {
        let record = CachedCampaignRecord(
            id: id,
            name: name,
            mode: mode,
            boundaryGeoJSON: boundaryGeoJSON,
            payloadJSON: payloadJSON,
            downloadedAt: downloadedAt.map(OfflineDateCodec.string(from:)),
            updatedAt: OfflineDateCodec.string(from: updatedAt)
        )
        try? await dbQueue.write { db in
            try record.save(db)
        }
    }

    func getCampaignBoundaryCoordinates(campaignId: String) async -> [CLLocationCoordinate2D]? {
        try? await dbQueue.read { db in
            guard let record = try CachedCampaignRecord
                .filter(Column("id") == campaignId)
                .fetchOne(db),
                  let boundaryGeoJSON = record.boundaryGeoJSON,
                  let data = boundaryGeoJSON.data(using: .utf8),
                  let polygon = try? JSONDecoder().decode(GeoJSONPolygon.self, from: data) else {
                return nil
            }

            let ring = polygon.coordinates.first ?? []
            let coordinates = ring.compactMap { point -> CLLocationCoordinate2D? in
                guard point.count >= 2 else { return nil }
                let coordinate = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
                return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
            }

            return coordinates.isEmpty ? nil : coordinates
        }
    }

    func upsertBuildings(campaignId: String, features: [BuildingFeature]) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            try CachedBuildingRecord.filter(Column("campaign_id") == campaignId).deleteAll(db)
            for feature in features {
                let sourceId = feature.properties.canonicalBuildingIdentifier ?? feature.id ?? UUID().uuidString
                let record = CachedBuildingRecord(
                    id: cacheScopedId(campaignId: campaignId, entityId: sourceId),
                    campaignId: campaignId,
                    sourceId: sourceId,
                    externalId: feature.properties.gersId ?? feature.properties.buildingId,
                    geometryGeoJSON: OfflineJSONCodec.encode(feature.geometry) ?? "{}",
                    propertiesJSON: OfflineJSONCodec.encode(feature.properties),
                    payloadJSON: OfflineJSONCodec.encode(feature),
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func upsertAddresses(campaignId: String, features: [AddressFeature]) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            try CachedAddressRecord.filter(Column("campaign_id") == campaignId).deleteAll(db)
            for feature in features {
                let sourceId = feature.properties.id ?? feature.id ?? UUID().uuidString
                let coordinate = feature.geometry.asPoint
                let formatted = feature.properties.formatted?.trimmingCharacters(in: .whitespacesAndNewlines)
                let record = CachedAddressRecord(
                    id: cacheScopedId(campaignId: campaignId, entityId: sourceId),
                    campaignId: campaignId,
                    buildingId: feature.properties.buildingGersId,
                    address: formatted?.isEmpty == false ? formatted : [feature.properties.houseNumber, feature.properties.streetName].compactMap { $0 }.joined(separator: " "),
                    unit: nil,
                    city: feature.properties.locality,
                    province: nil,
                    postalCode: feature.properties.postalCode,
                    latitude: coordinate?[safe: 1],
                    longitude: coordinate?[safe: 0],
                    payloadJSON: OfflineJSONCodec.encode(feature),
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func upsertBuildingAddressLinks(campaignId: String, links: [BuildingAddressLink]) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            try CachedBuildingAddressLinkRecord.filter(Column("campaign_id") == campaignId).deleteAll(db)
            for link in links {
                let record = CachedBuildingAddressLinkRecord(
                    id: cacheScopedId(campaignId: campaignId, entityId: "\(link.buildingId.lowercased()):\(link.addressId.lowercased())"),
                    campaignId: campaignId,
                    buildingId: link.buildingId,
                    addressId: link.addressId,
                    confidence: link.confidence,
                    source: link.matchType,
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func moveAddressLocally(
        campaignId: String,
        addressId: String,
        coordinate: CLLocationCoordinate2D
    ) async {
        let normalizedAddressId = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAddressId.isEmpty,
              CLLocationCoordinate2DIsValid(coordinate) else {
            return
        }

        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            let records = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            for record in records {
                let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
                let featureIds = [
                    feature?.properties.id,
                    feature?.id,
                    record.id.replacingOccurrences(of: "\(campaignId.lowercased()):", with: "")
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

                guard featureIds.contains(normalizedAddressId) else { continue }

                let movedFeature: AddressFeature?
                if let feature,
                   let geometry = Self.pointGeometry(for: coordinate) {
                    movedFeature = AddressFeature(
                        type: feature.type,
                        id: feature.id,
                        geometry: geometry,
                        properties: feature.properties
                    )
                } else {
                    movedFeature = nil
                }

                let updated = CachedAddressRecord(
                    id: record.id,
                    campaignId: record.campaignId,
                    buildingId: record.buildingId,
                    address: record.address,
                    unit: record.unit,
                    city: record.city,
                    province: record.province,
                    postalCode: record.postalCode,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    payloadJSON: movedFeature.flatMap { OfflineJSONCodec.encode($0) } ?? record.payloadJSON,
                    updatedAt: updatedAt
                )
                try updated.save(db)
            }
        }
    }

    func moveBuildingLocally(
        campaignId: String,
        buildingId: String,
        geometry: MapFeatureGeoJSONGeometry
    ) async {
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedBuildingId.isEmpty else { return }

        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            let records = try CachedBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            for record in records {
                let feature = OfflineJSONCodec.decode(BuildingFeature.self, from: record.payloadJSON)
                let featureIds = Set(
                    ([record.sourceId, record.externalId, feature?.id, feature?.properties.gersId, feature?.properties.buildingId, feature?.properties.id]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
                )

                guard featureIds.contains(normalizedBuildingId) else { continue }

                let movedFeature: BuildingFeature?
                if let feature {
                    movedFeature = BuildingFeature(
                        type: feature.type,
                        id: feature.id,
                        geometry: geometry,
                        properties: feature.properties
                    )
                } else {
                    movedFeature = nil
                }

                let updated = CachedBuildingRecord(
                    id: record.id,
                    campaignId: record.campaignId,
                    sourceId: record.sourceId,
                    externalId: record.externalId,
                    geometryGeoJSON: OfflineJSONCodec.encode(geometry) ?? record.geometryGeoJSON,
                    propertiesJSON: record.propertiesJSON,
                    payloadJSON: movedFeature.flatMap { OfflineJSONCodec.encode($0) } ?? record.payloadJSON,
                    updatedAt: updatedAt
                )
                try updated.save(db)
            }
        }
    }

    func upsertStatuses(rows: [AddressStatusRow]) async {
        let now = Date()
        try? await dbQueue.write { db in
            for row in rows {
                let record = CachedAddressStatusRecord(
                    id: cacheScopedId(campaignId: row.campaignId.uuidString, entityId: row.addressId.uuidString),
                    campaignId: row.campaignId.uuidString,
                    addressId: row.addressId.uuidString,
                    buildingId: nil,
                    status: row.status.rawValue,
                    outcome: row.status.persistedRPCValue,
                    notes: row.notes,
                    payloadJSON: OfflineJSONCodec.encode(row),
                    updatedAt: OfflineDateCodec.string(from: row.updatedAt),
                    dirty: 0
                )
                try record.save(db)
            }

            let affectedCampaignIds = Set(rows.map(\.campaignId.uuidString))
            for campaignId in affectedCampaignIds {
                try db.execute(
                    sql: """
                    UPDATE campaign_downloads
                    SET last_synced_at = ?
                    WHERE campaign_id = ?
                    """,
                    arguments: [OfflineDateCodec.string(from: now), campaignId]
                )
            }
        }
    }

    func upsertAddressCaptureMetadata(
        campaignId: UUID,
        addressId: UUID,
        contactName: String? = nil,
        leadStatus: String? = nil,
        productInterest: String? = nil,
        followUpDate: Date? = nil,
        rawTranscript: String? = nil,
        aiSummary: String? = nil,
        dirty: Bool,
        replaceAll: Bool = false
    ) async {
        let campaignIdString = campaignId.uuidString
        let addressIdString = addressId.uuidString
        let cacheId = cacheScopedId(campaignId: campaignIdString, entityId: addressIdString)
        let updatedAt = OfflineDateCodec.string(from: Date())

        try? await dbQueue.write { db in
            let existing = try CachedAddressCaptureMetadataRecord.fetchOne(db, key: cacheId)
            let record = CachedAddressCaptureMetadataRecord(
                id: cacheId,
                campaignId: campaignIdString,
                addressId: addressIdString,
                contactName: replaceAll ? contactName : (contactName ?? existing?.contactName),
                leadStatus: replaceAll ? leadStatus : (leadStatus ?? existing?.leadStatus),
                productInterest: replaceAll ? productInterest : (productInterest ?? existing?.productInterest),
                followUpDate: replaceAll
                    ? followUpDate.map(OfflineDateCodec.string(from:))
                    : (followUpDate.map(OfflineDateCodec.string(from:)) ?? existing?.followUpDate),
                rawTranscript: replaceAll ? rawTranscript : (rawTranscript ?? existing?.rawTranscript),
                aiSummary: replaceAll ? aiSummary : (aiSummary ?? existing?.aiSummary),
                updatedAt: updatedAt,
                dirty: dirty ? 1 : 0
            )
            try record.save(db)
        }
    }

    func upsertAddressCaptureMetadata(
        campaignId: UUID,
        responses: [CampaignAddressResponse],
        dirty: Bool = false
    ) async {
        guard !responses.isEmpty else { return }
        try? await dbQueue.write { db in
            for response in responses {
                let record = CachedAddressCaptureMetadataRecord(
                    id: cacheScopedId(campaignId: campaignId.uuidString, entityId: response.id.uuidString),
                    campaignId: campaignId.uuidString,
                    addressId: response.id.uuidString,
                    contactName: response.contactName,
                    leadStatus: response.leadStatus,
                    productInterest: response.productInterest,
                    followUpDate: response.followUpDate.map(OfflineDateCodec.string(from:)),
                    rawTranscript: response.rawTranscript,
                    aiSummary: response.aiSummary,
                    updatedAt: OfflineDateCodec.string(from: Date()),
                    dirty: dirty ? 1 : 0
                )
                try record.save(db)
            }
        }
    }

    func clearAddressCaptureMetadata(
        campaignId: UUID,
        addressId: UUID,
        dirty: Bool
    ) async {
        await upsertAddressCaptureMetadata(
            campaignId: campaignId,
            addressId: addressId,
            contactName: nil,
            leadStatus: nil,
            productInterest: nil,
            followUpDate: nil,
            rawTranscript: nil,
            aiSummary: nil,
            dirty: dirty,
            replaceAll: true
        )
    }

    func getAddressCaptureMetadata(
        campaignId: UUID,
        addressId: UUID
    ) async -> AddressCaptureMetadata? {
        try? await dbQueue.read { db in
            let cacheId = cacheScopedId(campaignId: campaignId.uuidString, entityId: addressId.uuidString)
            guard let record = try CachedAddressCaptureMetadataRecord.fetchOne(db, key: cacheId) else {
                return nil
            }
            return AddressCaptureMetadata(
                campaignId: campaignId,
                addressId: addressId,
                contactName: record.contactName,
                leadStatus: record.leadStatus,
                productInterest: record.productInterest,
                followUpDate: OfflineDateCodec.date(from: record.followUpDate),
                rawTranscript: record.rawTranscript,
                aiSummary: record.aiSummary,
                updatedAt: OfflineDateCodec.date(from: record.updatedAt),
                dirty: record.dirty != 0
            )
        }
    }

    func markAddressCaptureMetadataSynced(
        campaignId: UUID,
        addressId: UUID,
        at date: Date = Date()
    ) async {
        let cacheId = cacheScopedId(campaignId: campaignId.uuidString, entityId: addressId.uuidString)
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE cached_address_capture_metadata
                SET dirty = 0, updated_at = ?
                WHERE id = ?
                """,
                arguments: [OfflineDateCodec.string(from: date), cacheId]
            )
        }
    }

    func markStatusRowsSynced(campaignId: UUID, addressIds: [UUID], at date: Date = Date()) async {
        let updatedAt = OfflineDateCodec.string(from: date)
        let ids = addressIds.map(\.uuidString)
        guard !ids.isEmpty else { return }

        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE cached_address_statuses
                SET dirty = 0, updated_at = ?
                WHERE campaign_id = ? AND address_id IN (\(ids.map { _ in "?" }.joined(separator: ",")))
                """,
                arguments: StatementArguments([updatedAt, campaignId.uuidString] + ids)
            )
        }
    }

    func updateStatusLocally(
        addressIds: [UUID],
        campaignId: UUID,
        buildingId: String?,
        status: AddressStatus,
        notes: String?,
        occurredAt: Date,
        sessionId: UUID?
    ) async -> [AddressStatusRow] {
        let timestamp = OfflineDateCodec.string(from: occurredAt)
        let campaignIdString = campaignId.uuidString
        var rows: [AddressStatusRow] = []

        try? await dbQueue.write { db in
            for addressId in addressIds {
                let existing = try CachedAddressStatusRecord
                    .filter(Column("campaign_id") == campaignIdString && Column("address_id") == addressId.uuidString)
                    .fetchOne(db)
                let createdAt = OfflineDateCodec.date(from: existing?.updatedAt) ?? occurredAt
                let existingVisitCount = OfflineJSONCodec.decode(AddressStatusRow.self, from: existing?.payloadJSON)?.visitCount ?? 0
                let visitCount: Int
                switch status {
                case .none, .untouched:
                    visitCount = existingVisitCount
                default:
                    visitCount = max(existingVisitCount, 0) + 1
                }
                let localRow = AddressStatusRow(
                    id: addressId,
                    addressId: addressId,
                    campaignId: campaignId,
                    status: status == .untouched ? .none : status,
                    lastVisitedAt: (status == .none || status == .untouched) ? existing.flatMap { OfflineJSONCodec.decode(AddressStatusRow.self, from: $0.payloadJSON)?.lastVisitedAt } : occurredAt,
                    notes: notes,
                    visitCount: visitCount,
                    lastActionBy: nil,
                    lastSessionId: sessionId,
                    lastHomeEventId: nil,
                    createdAt: createdAt,
                    updatedAt: occurredAt
                )
                let record = CachedAddressStatusRecord(
                    id: cacheScopedId(campaignId: campaignIdString, entityId: addressId.uuidString),
                    campaignId: campaignIdString,
                    addressId: addressId.uuidString,
                    buildingId: buildingId,
                    status: localRow.status.rawValue,
                    outcome: status.persistedRPCValue,
                    notes: notes,
                    payloadJSON: OfflineJSONCodec.encode(localRow),
                    updatedAt: timestamp,
                    dirty: 1
                )
                try record.save(db)
                rows.append(localRow)
            }
        }

        return rows
    }

    func upsertRoads(campaignId: String, corridors: [StreetCorridor]) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            try CachedRoadRecord.filter(Column("campaign_id") == campaignId).deleteAll(db)
            for (index, corridor) in corridors.enumerated() {
                let geometry = RoadGeometry(type: "LineString", coordinates: corridor.polyline.map { [$0.longitude, $0.latitude] })
                let properties = RoadProperties(
                    id: corridor.id ?? "road-\(index)",
                    gersId: corridor.id,
                    roadClass: corridor.roadClass,
                    name: corridor.roadName
                )
                let record = CachedRoadRecord(
                    id: cacheScopedId(campaignId: campaignId, entityId: corridor.id ?? "road-\(index)"),
                    campaignId: campaignId,
                    geometryGeoJSON: OfflineJSONCodec.encode(geometry) ?? "{}",
                    propertiesJSON: OfflineJSONCodec.encode(properties),
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func getCampaignMapBundle(campaignId: String) async -> OfflineCampaignMapBundle? {
        try? await dbQueue.read { db in
            let buildingRecords = try CachedBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let addressRecords = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let roadRecords = try CachedRoadRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let linkRecords = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            guard !buildingRecords.isEmpty || !addressRecords.isEmpty || !roadRecords.isEmpty || !linkRecords.isEmpty else {
                return nil
            }

            let buildings = buildingRecords.compactMap { record in
                OfflineJSONCodec.decode(BuildingFeature.self, from: record.payloadJSON)
            }
            let addresses = addressRecords.compactMap { record in
                OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
            }
            let roads = roadRecords.compactMap { record -> RoadFeature? in
                guard let geometry = OfflineJSONCodec.decode(MapFeatureGeoJSONGeometry.self, from: record.geometryGeoJSON),
                      let properties = OfflineJSONCodec.decode(RoadProperties.self, from: record.propertiesJSON) else {
                    return nil
                }
                return RoadFeature(
                    type: "Feature",
                    id: properties.id ?? record.id,
                    geometry: geometry,
                    properties: properties
                )
            }

            var links: [String: [String]] = [:]
            for link in linkRecords {
                links[link.buildingId.lowercased(), default: []].append(link.addressId)
            }

            return OfflineCampaignMapBundle(
                buildings: BuildingFeatureCollection(type: "FeatureCollection", features: buildings),
                addresses: AddressFeatureCollection(type: "FeatureCollection", features: addresses),
                roads: RoadFeatureCollection(type: "FeatureCollection", features: roads),
                silverBuildingLinks: links
            )
        }
    }

    func getStatuses(campaignId: UUID) async -> [UUID: AddressStatusRow] {
        (try? await dbQueue.read { db in
            let records = try CachedAddressStatusRecord
                .filter(Column("campaign_id") == campaignId.uuidString)
                .fetchAll(db)

            var rows: [UUID: AddressStatusRow] = [:]
            for record in records {
                if let row = OfflineJSONCodec.decode(AddressStatusRow.self, from: record.payloadJSON) {
                    rows[row.addressId] = row
                } else if let addressIdString = record.addressId,
                          let addressId = UUID(uuidString: addressIdString) {
                    let status = AddressStatus(rawValue: record.status ?? "") ?? .none
                    let updatedAt = OfflineDateCodec.date(from: record.updatedAt) ?? Date()
                    rows[addressId] = AddressStatusRow(
                        id: addressId,
                        addressId: addressId,
                        campaignId: campaignId,
                        status: status,
                        lastVisitedAt: status == .none ? nil : updatedAt,
                        notes: record.notes,
                        visitCount: 0,
                        lastActionBy: nil,
                        lastSessionId: nil,
                        lastHomeEventId: nil,
                        createdAt: updatedAt,
                        updatedAt: updatedAt
                    )
                }
            }
            return rows
        }) ?? [:]
    }

    func getOfflineAssetCounts(campaignId: String) async -> CampaignOfflineAssetCounts {
        (try? await dbQueue.read { db in
            let buildings = try CachedBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchCount(db)
            let addresses = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchCount(db)
            let buildingLinks = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchCount(db)
            let statuses = try CachedAddressStatusRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchCount(db)
            let roads = try CachedRoadRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchCount(db)
            let metadata = try CachedAddressCaptureMetadataRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchCount(db)

            return CampaignOfflineAssetCounts(
                buildings: buildings,
                addresses: addresses,
                buildingLinks: buildingLinks,
                statuses: statuses,
                roads: roads,
                metadata: metadata
            )
        }) ?? CampaignOfflineAssetCounts(
            buildings: 0,
            addresses: 0,
            buildingLinks: 0,
            statuses: 0,
            roads: 0,
            metadata: 0
        )
    }

    func deleteBuildingLocally(
        campaignId: String,
        buildingId: String
    ) async -> OfflineDeletedBuildingSnapshot {
        let normalizedBuildingId = buildingId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedBuildingId.isEmpty else {
            return OfflineDeletedBuildingSnapshot(buildingIdentifiers: [], deletedAddressIds: [])
        }

        return (try? await dbQueue.write { db in
            let buildingRecords = try CachedBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            var matchedBuildingCacheIds = Set<String>()
            var buildingIdentifiers = Set([normalizedBuildingId])

            for record in buildingRecords {
                let sourceId = record.sourceId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let externalId = record.externalId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let feature = OfflineJSONCodec.decode(BuildingFeature.self, from: record.payloadJSON)
                let featureIdentifiers = Set(
                    (feature?.properties.buildingIdentifierCandidates ?? [])
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { !$0.isEmpty }
                )

                let recordIdentifiers = Set([sourceId, externalId].compactMap { $0 }).union(featureIdentifiers)
                guard recordIdentifiers.contains(normalizedBuildingId) else { continue }

                matchedBuildingCacheIds.insert(record.id)
                buildingIdentifiers.formUnion(recordIdentifiers)
            }

            let linkRecords = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            var linkCacheIdsToDelete = Set<String>()
            let linkedAddressIds = Set(linkRecords.compactMap { record -> String? in
                let normalizedLinkBuildingId = record.buildingId
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard buildingIdentifiers.contains(normalizedLinkBuildingId) else { return nil }
                linkCacheIdsToDelete.insert(record.id)
                return record.addressId.lowercased()
            })

            let addressRecords = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            var addressCacheIdsToDelete = Set<String>()
            var deletedAddressIds = linkedAddressIds

            for record in addressRecords {
                let normalizedAddressBuildingId = record.buildingId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let normalizedAddressId = record.id
                    .split(separator: ":", maxSplits: 1)
                    .last
                    .map(String.init)?
                    .lowercased()

                let shouldDelete = (normalizedAddressBuildingId.map { buildingIdentifiers.contains($0) } ?? false)
                    || (normalizedAddressId.map { linkedAddressIds.contains($0) } ?? false)

                guard shouldDelete else { continue }
                addressCacheIdsToDelete.insert(record.id)
                if let normalizedAddressId {
                    deletedAddressIds.insert(normalizedAddressId)
                }
            }

            if !matchedBuildingCacheIds.isEmpty {
                try CachedBuildingRecord
                    .filter(matchedBuildingCacheIds.contains(Column("id")))
                    .deleteAll(db)
            }

            if !buildingIdentifiers.isEmpty {
                try CachedBuildingAddressLinkRecord
                    .filter(linkCacheIdsToDelete.contains(Column("id")))
                    .deleteAll(db)
            }

            if !addressCacheIdsToDelete.isEmpty {
                try CachedAddressRecord
                    .filter(addressCacheIdsToDelete.contains(Column("id")))
                    .deleteAll(db)
            }

            if !deletedAddressIds.isEmpty {
                let statusCacheIdsToDelete = try CachedAddressStatusRecord
                    .filter(Column("campaign_id") == campaignId)
                    .fetchAll(db)
                    .compactMap { record -> String? in
                        guard let addressId = record.addressId?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased(),
                              deletedAddressIds.contains(addressId) else {
                            return nil
                        }
                        return record.id
                    }

                let metadataCacheIdsToDelete = try CachedAddressCaptureMetadataRecord
                    .filter(Column("campaign_id") == campaignId)
                    .fetchAll(db)
                    .compactMap { record -> String? in
                        let addressId = record.addressId
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .lowercased()
                        return deletedAddressIds.contains(addressId) ? record.id : nil
                    }

                if !statusCacheIdsToDelete.isEmpty {
                    try CachedAddressStatusRecord
                        .filter(statusCacheIdsToDelete.contains(Column("id")))
                        .deleteAll(db)
                }

                if !metadataCacheIdsToDelete.isEmpty {
                    try CachedAddressCaptureMetadataRecord
                        .filter(metadataCacheIdsToDelete.contains(Column("id")))
                        .deleteAll(db)
                }
            }

            return OfflineDeletedBuildingSnapshot(
                buildingIdentifiers: Array(buildingIdentifiers),
                deletedAddressIds: Array(deletedAddressIds)
            )
        }) ?? OfflineDeletedBuildingSnapshot(buildingIdentifiers: [], deletedAddressIds: [])
    }

    func updateDownloadState(
        campaignId: String,
        status: String,
        progress: Double,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        lastSyncedAt: Date? = nil
    ) async {
        let record = CampaignDownloadRecord(
            campaignId: campaignId,
            status: status,
            progress: progress,
            startedAt: startedAt.map(OfflineDateCodec.string(from:)),
            completedAt: completedAt.map(OfflineDateCodec.string(from:)),
            errorMessage: errorMessage,
            lastSyncedAt: lastSyncedAt.map(OfflineDateCodec.string(from:))
        )
        try? await dbQueue.write { db in
            try record.save(db)
        }
    }

    func markCampaignLastSynced(campaignId: String, at date: Date = Date()) async {
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO campaign_downloads (campaign_id, status, progress, last_synced_at)
                VALUES (?, COALESCE((SELECT status FROM campaign_downloads WHERE campaign_id = ?), 'ready'), COALESCE((SELECT progress FROM campaign_downloads WHERE campaign_id = ?), 1), ?)
                ON CONFLICT(campaign_id) DO UPDATE SET last_synced_at = excluded.last_synced_at
                """,
                arguments: [campaignId, campaignId, campaignId, OfflineDateCodec.string(from: date)]
            )
        }
    }

    func getDownloadState(campaignId: String) async -> CampaignDownloadState? {
        try? await dbQueue.read { db in
            guard let record = try CampaignDownloadRecord.fetchOne(db, key: campaignId) else { return nil }
            return CampaignDownloadState(
                campaignId: record.campaignId,
                status: record.status ?? "not_downloaded",
                progress: record.progress,
                startedAt: OfflineDateCodec.date(from: record.startedAt),
                completedAt: OfflineDateCodec.date(from: record.completedAt),
                errorMessage: record.errorMessage,
                lastSyncedAt: OfflineDateCodec.date(from: record.lastSyncedAt)
            )
        }
    }

    private func cacheScopedId(campaignId: String, entityId: String) -> String {
        "\(campaignId.lowercased()):\(entityId.lowercased())"
    }

    private static func pointGeometry(for coordinate: CLLocationCoordinate2D) -> MapFeatureGeoJSONGeometry? {
        let payload: [String: Any] = [
            "type": "Point",
            "coordinates": [coordinate.longitude, coordinate.latitude]
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return try? JSONDecoder().decode(MapFeatureGeoJSONGeometry.self, from: data)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
