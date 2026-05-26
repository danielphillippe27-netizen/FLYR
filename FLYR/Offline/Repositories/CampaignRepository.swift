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
}

struct CachedClientLinkBatch: Sendable {
    let summary: ClientLinkingSummary
    let assetSignature: String
}

struct CampaignOfflineAssetCounts: Sendable {
    let buildings: Int
    let addresses: Int
    let buildingLinks: Int
    let addressOrphans: Int
    let statuses: Int
    let roads: Int
    let metadata: Int
}

struct CampaignAddressOrphanSnapshot: Sendable {
    let addressId: String
    let nearestBuildingId: String?
    let nearestDistance: Double?
    let status: String?
    let suggestedStreet: String?
    let addressStreet: String?
    let coordinateJSON: String?
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

private struct CachedClientLinkBatchRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_client_link_batches"

    let campaignId: String
    let assetSignature: String
    let buildingCount: Int
    let addressCount: Int
    let parcelCount: Int
    let linkCount: Int
    let updatedAt: String?
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case assetSignature = "asset_signature"
        case buildingCount = "building_count"
        case addressCount = "address_count"
        case parcelCount = "parcel_count"
        case linkCount = "link_count"
        case updatedAt = "updated_at"
        case publishedAt = "published_at"
    }
}

private struct CachedAddressOrphanRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cached_address_orphans"

    let id: String
    let campaignId: String
    let addressId: String
    let nearestBuildingId: String?
    let nearestDistance: Double?
    let status: String?
    let suggestedStreet: String?
    let addressStreet: String?
    let coordinateJSON: String?
    let updatedAt: String?

    enum Columns: String, ColumnExpression {
        case id
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case nearestBuildingId = "nearest_building_id"
        case nearestDistance = "nearest_distance"
        case status
        case suggestedStreet = "suggested_street"
        case addressStreet = "address_street"
        case coordinateJSON = "coordinate_json"
        case updatedAt = "updated_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case nearestBuildingId = "nearest_building_id"
        case nearestDistance = "nearest_distance"
        case status
        case suggestedStreet = "suggested_street"
        case addressStreet = "address_street"
        case coordinateJSON = "coordinate_json"
        case updatedAt = "updated_at"
    }
}

private struct LocalFallbackBuildingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_fallback_buildings"

    let localGeometryId: String
    let campaignId: String
    let addressId: String
    let geometryGeoJSON: String
    let geometrySource: String
    let payloadJSON: String?
    let createdAt: String?
    let updatedAt: String?
    let syncStatus: String

    enum Columns: String, ColumnExpression {
        case localGeometryId = "local_geometry_id"
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case geometryGeoJSON = "geometry_geojson"
        case geometrySource = "geometry_source"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncStatus = "sync_status"
    }

    enum CodingKeys: String, CodingKey {
        case localGeometryId = "local_geometry_id"
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case geometryGeoJSON = "geometry_geojson"
        case geometrySource = "geometry_source"
        case payloadJSON = "payload_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncStatus = "sync_status"
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

    func upsertCampaignMetadataRows(
        _ rows: [CampaignDBRow],
        addressCounts: [UUID: Int]
    ) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            for row in rows {
                let existing = try CachedCampaignRecord.fetchOne(db, key: row.id.uuidString)
                let payloadJSON = Self.campaignPayloadJSON(from: row, totalFlyers: addressCounts[row.id])
                    ?? existing?.payloadJSON
                let record = CachedCampaignRecord(
                    id: row.id.uuidString,
                    name: row.title,
                    mode: row.status?.rawValue ?? existing?.mode,
                    boundaryGeoJSON: existing?.boundaryGeoJSON,
                    payloadJSON: payloadJSON,
                    downloadedAt: existing?.downloadedAt,
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func getCachedCampaigns() async -> [CampaignV2] {
        (try? await dbQueue.read { db in
            let campaignRecords = try CachedCampaignRecord
                .order(Column("updated_at").desc)
                .fetchAll(db)
            let addressRecords = try CachedAddressRecord.fetchAll(db)
            let addressesByCampaignId = Dictionary(grouping: addressRecords, by: \.campaignId)

            let campaigns = campaignRecords.compactMap { record -> CampaignV2? in
                guard !Self.isQuickStartCampaign(payloadJSON: record.payloadJSON) else { return nil }
                guard let campaignId = UUID(uuidString: record.id) else { return nil }
                return Self.cachedCampaign(
                    campaignId: campaignId,
                    record: record,
                    addressRecords: addressesByCampaignId[record.id] ?? []
                )
            }

            return campaigns.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }) ?? []
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

    func getCachedCampaign(campaignId: UUID) async -> CampaignV2? {
        let campaignIdString = campaignId.uuidString
        return try? await dbQueue.read { db in
            let campaignRecord = try CachedCampaignRecord
                .filter(Column("id") == campaignIdString)
                .fetchOne(db)
            let addressRecords = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignIdString)
                .fetchAll(db)

            guard campaignRecord != nil || !addressRecords.isEmpty else {
                return nil
            }

            return Self.cachedCampaign(
                campaignId: campaignId,
                record: campaignRecord,
                addressRecords: addressRecords
            )
        }
    }

    func getCachedAddressRows(campaignId: UUID) async -> [CampaignAddressRow] {
        let campaignIdString = campaignId.uuidString
        return (try? await dbQueue.read { db in
            let records = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignIdString)
                .fetchAll(db)
            return Self.addressRows(from: records, campaignId: campaignIdString)
        }) ?? []
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

    func upsertManualAddressLocally(
        campaignId: String,
        addressId: UUID,
        input: ManualAddressCreateInput
    ) async {
        guard CLLocationCoordinate2DIsValid(input.coordinate),
              let geometry = Self.pointGeometry(for: input.coordinate) else {
            return
        }

        let trimmedFormatted = input.formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatted = trimmedFormatted.isEmpty ? "Manual Address" : trimmedFormatted
        let updatedAt = OfflineDateCodec.string(from: Date())
        let feature = AddressFeature(
            type: "Feature",
            id: addressId.uuidString,
            geometry: geometry,
            properties: AddressProperties(
                id: addressId.uuidString,
                gersId: nil,
                buildingGersId: input.buildingId,
                houseNumber: input.houseNumber,
                streetName: input.streetName,
                postalCode: input.postalCode,
                locality: input.locality,
                formatted: formatted,
                source: "manual"
            )
        )

        try? await dbQueue.write { db in
            let record = CachedAddressRecord(
                id: cacheScopedId(campaignId: campaignId, entityId: addressId.uuidString),
                campaignId: campaignId,
                buildingId: input.buildingId,
                address: formatted,
                unit: nil,
                city: input.locality,
                province: input.region,
                postalCode: input.postalCode,
                latitude: input.coordinate.latitude,
                longitude: input.coordinate.longitude,
                payloadJSON: OfflineJSONCodec.encode(feature),
                updatedAt: updatedAt
            )
            try record.save(db)

            guard let buildingId = input.buildingId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !buildingId.isEmpty else {
                return
            }

            let linkRecord = CachedBuildingAddressLinkRecord(
                id: cacheScopedId(campaignId: campaignId, entityId: "\(buildingId.lowercased()):\(addressId.uuidString.lowercased())"),
                campaignId: campaignId,
                buildingId: buildingId,
                addressId: addressId.uuidString.lowercased(),
                confidence: 1,
                source: "manual",
                updatedAt: updatedAt
            )
            try linkRecord.save(db)
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

    func upsertClientGeneratedBuildingAddressLinks(
        campaignId: String,
        links: [ClientBuildingAddressLink],
        assetSignature: String,
        buildingCount: Int,
        addressCount: Int,
        parcelCount: Int
    ) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            let existingLinks = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            let protectedAddressIds = Set(
                existingLinks
                    .filter { ($0.source ?? "").lowercased().hasPrefix("manual") }
                    .map { $0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            )

            let generatedIdsToDelete = existingLinks
                .filter { ($0.source ?? "").caseInsensitiveCompare("client_auto") == .orderedSame }
                .map(\.id)
            if !generatedIdsToDelete.isEmpty {
                try CachedBuildingAddressLinkRecord
                    .filter(generatedIdsToDelete.contains(Column("id")))
                    .deleteAll(db)
            }

            var writableLinksByAddress: [String: ClientBuildingAddressLink] = [:]
            for link in links {
                let normalizedAddressId = link.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalizedAddressId.isEmpty,
                      !protectedAddressIds.contains(normalizedAddressId) else {
                    continue
                }

                if let existing = writableLinksByAddress[normalizedAddressId],
                   existing.confidence >= link.confidence {
                    continue
                }
                writableLinksByAddress[normalizedAddressId] = link
            }
            let writableLinks = Array(writableLinksByAddress.values)

            let replacedAddressIds = Set(writableLinks.map {
                $0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            })
            if !replacedAddressIds.isEmpty {
                let linkIdsToReplace = existingLinks
                    .filter {
                        replacedAddressIds.contains($0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                    }
                    .map(\.id)
                if !linkIdsToReplace.isEmpty {
                    try CachedBuildingAddressLinkRecord
                        .filter(linkIdsToReplace.contains(Column("id")))
                        .deleteAll(db)
                }
            }

            let batchRecord = CachedClientLinkBatchRecord(
                campaignId: campaignId,
                assetSignature: assetSignature,
                buildingCount: buildingCount,
                addressCount: addressCount,
                parcelCount: parcelCount,
                linkCount: writableLinks.count,
                updatedAt: updatedAt,
                publishedAt: nil
            )
            try batchRecord.save(db)

            for link in writableLinks {
                let normalizedAddressId = link.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let normalizedBuildingId = link.buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedAddressId.isEmpty, !normalizedBuildingId.isEmpty else { continue }
                let record = CachedBuildingAddressLinkRecord(
                    id: cacheScopedId(campaignId: campaignId, entityId: "\(normalizedBuildingId.lowercased()):\(normalizedAddressId)"),
                    campaignId: campaignId,
                    buildingId: normalizedBuildingId,
                    addressId: normalizedAddressId,
                    confidence: link.confidence,
                    source: "client_auto",
                    updatedAt: updatedAt
                )
                try record.save(db)

                let addressRecords = try CachedAddressRecord
                    .filter(Column("campaign_id") == campaignId)
                    .fetchAll(db)
                    .filter { Self.record($0, campaignId: campaignId, matchesAddressId: normalizedAddressId) }

                for addressRecord in addressRecords {
                    let feature = OfflineJSONCodec.decode(AddressFeature.self, from: addressRecord.payloadJSON)
                    let updatedFeature: AddressFeature?
                    if let feature {
                        updatedFeature = AddressFeature(
                            type: feature.type,
                            id: feature.id,
                            geometry: feature.geometry,
                            properties: AddressProperties(
                                id: feature.properties.id,
                                gersId: feature.properties.gersId,
                                buildingGersId: normalizedBuildingId,
                                houseNumber: feature.properties.houseNumber,
                                streetName: feature.properties.streetName,
                                postalCode: feature.properties.postalCode,
                                locality: feature.properties.locality,
                                formatted: feature.properties.formatted,
                                source: feature.properties.source
                            )
                        )
                    } else {
                        updatedFeature = nil
                    }

                    let updated = CachedAddressRecord(
                        id: addressRecord.id,
                        campaignId: addressRecord.campaignId,
                        buildingId: normalizedBuildingId,
                        address: addressRecord.address,
                        unit: addressRecord.unit,
                        city: addressRecord.city,
                        province: addressRecord.province,
                        postalCode: addressRecord.postalCode,
                        latitude: addressRecord.latitude,
                        longitude: addressRecord.longitude,
                        payloadJSON: updatedFeature.flatMap { OfflineJSONCodec.encode($0) } ?? addressRecord.payloadJSON,
                        updatedAt: updatedAt
                    )
                    try updated.save(db)
                }
            }
        }
    }

    func getClientGeneratedLinkBatch(
        campaignId: String,
        assetSignature: String
    ) async -> CachedClientLinkBatch? {
        try? await dbQueue.read { db in
            guard let batch = try CachedClientLinkBatchRecord
                .filter(Column("campaign_id") == campaignId)
                .filter(Column("asset_signature") == assetSignature)
                .fetchOne(db) else {
                return nil
            }

            let records = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .filter(Column("source") == "client_auto")
                .fetchAll(db)

            let links = records.map { record in
                ClientBuildingAddressLink(
                    id: record.id,
                    buildingId: record.buildingId,
                    addressId: record.addressId,
                    matchType: record.source ?? "client_auto",
                    confidence: record.confidence ?? 0.5,
                    distanceMeters: 0
                )
            }
            let progress = ClientLinkingProgress(
                processed: batch.addressCount,
                total: batch.addressCount,
                linked: links.count
            )
            return CachedClientLinkBatch(
                summary: ClientLinkingSummary(links: links, progress: progress),
                assetSignature: batch.assetSignature
            )
        }
    }

    func getBuildingAddressLinks(campaignId: String) async -> [BuildingAddressLink] {
        (try? await dbQueue.read { db in
            let records = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            return records.map { record in
                BuildingAddressLink(
                    id: record.id,
                    buildingId: record.buildingId,
                    addressId: record.addressId,
                    matchType: record.source ?? "cached",
                    confidence: record.confidence ?? 1,
                    isMultiUnit: false,
                    unitCount: 1
                )
            }
        }) ?? []
    }

    func upsertAddressOrphans(campaignId: String, orphans: [CampaignAddressOrphanSnapshot]) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            try CachedAddressOrphanRecord.filter(Column("campaign_id") == campaignId).deleteAll(db)
            for orphan in orphans {
                let addressId = orphan.addressId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !addressId.isEmpty else { continue }
                let nearestBuildingId = orphan.nearestBuildingId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let record = CachedAddressOrphanRecord(
                    id: cacheScopedId(campaignId: campaignId, entityId: "\(nearestBuildingId ?? "none"):\(addressId)"),
                    campaignId: campaignId,
                    addressId: addressId.lowercased(),
                    nearestBuildingId: nearestBuildingId?.isEmpty == false ? nearestBuildingId : nil,
                    nearestDistance: orphan.nearestDistance,
                    status: orphan.status,
                    suggestedStreet: orphan.suggestedStreet,
                    addressStreet: orphan.addressStreet,
                    coordinateJSON: orphan.coordinateJSON,
                    updatedAt: updatedAt
                )
                try record.save(db)
            }
        }
    }

    func getAddressOrphans(campaignId: String) async -> [CampaignAddressOrphanSnapshot] {
        (try? await dbQueue.read { db in
            let records = try CachedAddressOrphanRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            return records.map { record in
                CampaignAddressOrphanSnapshot(
                    addressId: record.addressId,
                    nearestBuildingId: record.nearestBuildingId,
                    nearestDistance: record.nearestDistance,
                    status: record.status,
                    suggestedStreet: record.suggestedStreet,
                    addressStreet: record.addressStreet,
                    coordinateJSON: record.coordinateJSON
                )
            }
        }) ?? []
    }

    func upsertBuildingAddressLinkLocally(
        campaignId: String,
        buildingId: String,
        addressId: String,
        coordinate: CLLocationCoordinate2D? = nil,
        confidence: Double = 1,
        source: String = "manual"
    ) async {
        let normalizedAddressId = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAddressId.isEmpty, !normalizedBuildingId.isEmpty else { return }

        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            let previousLinks = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .filter(Column("address_id") == normalizedAddressId)
                .fetchAll(db)
            if !previousLinks.isEmpty {
                try CachedBuildingAddressLinkRecord
                    .filter(previousLinks.map(\.id).contains(Column("id")))
                    .deleteAll(db)
            }

            let linkRecord = CachedBuildingAddressLinkRecord(
                id: cacheScopedId(campaignId: campaignId, entityId: "\(normalizedBuildingId.lowercased()):\(normalizedAddressId)"),
                campaignId: campaignId,
                buildingId: normalizedBuildingId,
                addressId: normalizedAddressId,
                confidence: confidence,
                source: source,
                updatedAt: updatedAt
            )
            try linkRecord.save(db)

            var records = try CachedAddressRecord
                .filter(Column("id") == cacheScopedId(campaignId: campaignId, entityId: normalizedAddressId))
                .fetchAll(db)

            if records.isEmpty {
                records = try CachedAddressRecord
                    .filter(Column("campaign_id") == campaignId)
                    .fetchAll(db)
                    .filter { Self.record($0, campaignId: campaignId, matchesAddressId: normalizedAddressId) }
            }

            for record in records {
                let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
                let updatedFeature: AddressFeature?
                if let feature {
                    let updatedProperties = AddressProperties(
                        id: feature.properties.id,
                        gersId: feature.properties.gersId,
                        buildingGersId: normalizedBuildingId,
                        houseNumber: feature.properties.houseNumber,
                        streetName: feature.properties.streetName,
                        postalCode: feature.properties.postalCode,
                        locality: feature.properties.locality,
                        formatted: feature.properties.formatted,
                        source: feature.properties.source
                    )
                    let geometry = coordinate.flatMap(Self.pointGeometry(for:)) ?? feature.geometry
                    updatedFeature = AddressFeature(
                        type: feature.type,
                        id: feature.id,
                        geometry: geometry,
                        properties: updatedProperties
                    )
                } else {
                    updatedFeature = nil
                }

                let updated = CachedAddressRecord(
                    id: record.id,
                    campaignId: record.campaignId,
                    buildingId: normalizedBuildingId,
                    address: record.address,
                    unit: record.unit,
                    city: record.city,
                    province: record.province,
                    postalCode: record.postalCode,
                    latitude: coordinate?.latitude ?? record.latitude,
                    longitude: coordinate?.longitude ?? record.longitude,
                    payloadJSON: updatedFeature.flatMap { OfflineJSONCodec.encode($0) } ?? record.payloadJSON,
                    updatedAt: updatedAt
                )
                try updated.save(db)
            }
        }
    }

    func fallbackBuildingId(addressId: UUID) -> String {
        Self.fallbackBuildingId(addressId: addressId)
    }

    func hasLocalFallbackBuilding(campaignId: String, addressId: UUID) async -> Bool {
        let normalizedAddressId = addressId.uuidString.lowercased()
        return (try? await dbQueue.read { db in
            try LocalFallbackBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .filter(Column("address_id") == normalizedAddressId)
                .fetchCount(db) > 0
        }) ?? false
    }

    func upsertFallbackBuildingLocally(
        campaignId: String,
        addressId: UUID
    ) async -> BuildingFeature? {
        let normalizedAddressId = addressId.uuidString.lowercased()
        let fallbackId = Self.fallbackBuildingId(addressId: addressId)
        let now = OfflineDateCodec.string(from: Date())

        return try? await dbQueue.write { db in
            if let existing = try LocalFallbackBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .filter(Column("address_id") == normalizedAddressId)
                .fetchOne(db),
               let feature = Self.decodeLocalFallbackBuildingFeature(from: existing) {
                return feature
            }

            let addressRecords = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            guard let addressRecord = addressRecords.first(where: {
                Self.record($0, campaignId: campaignId, matchesAddressId: normalizedAddressId)
            }) else {
                return nil
            }

            let addressFeature = OfflineJSONCodec.decode(AddressFeature.self, from: addressRecord.payloadJSON)
            let coordinate = addressFeature
                .flatMap { CampaignTargetResolver.coordinate(for: $0.geometry) }
                ?? addressRecord.latitude.flatMap { latitude in
                    addressRecord.longitude.map { longitude in
                        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    }
                }
            guard let coordinate, CLLocationCoordinate2DIsValid(coordinate),
                  let geometry = Self.fallbackRectangleGeometry(center: coordinate) else {
                return nil
            }

            let displayAddress = addressFeature?.properties.formatted
                ?? addressRecord.address
                ?? [addressFeature?.properties.houseNumber, addressFeature?.properties.streetName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            let trimmedDisplayAddress = displayAddress.trimmingCharacters(in: .whitespacesAndNewlines)

            let properties = BuildingProperties(
                id: fallbackId,
                buildingId: fallbackId,
                addressId: addressId.uuidString,
                gersId: fallbackId,
                height: 8,
                heightM: 8,
                minHeight: 0,
                isTownhome: false,
                unitsCount: 1,
                addressText: trimmedDisplayAddress.isEmpty ? nil : trimmedDisplayAddress,
                matchMethod: "manual_fallback",
                featureStatus: "matched",
                featureType: "manual_fallback",
                status: "not_visited",
                scansToday: 0,
                scansTotal: 0,
                lastScanSecondsAgo: nil,
                houseNumber: addressFeature?.properties.houseNumber,
                streetName: addressFeature?.properties.streetName,
                confidence: 1,
                source: "manual_fallback",
                addressCount: 1,
                areaSqm: 80,
                buildingType: "residential",
                qrScanned: false,
                isLinked: true
            )
            let feature = BuildingFeature(
                type: "Feature",
                id: fallbackId,
                geometry: geometry,
                properties: properties
            )
            let record = LocalFallbackBuildingRecord(
                localGeometryId: fallbackId,
                campaignId: campaignId,
                addressId: normalizedAddressId,
                geometryGeoJSON: OfflineJSONCodec.encode(geometry) ?? "{}",
                geometrySource: "manual_fallback",
                payloadJSON: OfflineJSONCodec.encode(feature),
                createdAt: now,
                updatedAt: now,
                syncStatus: "pending"
            )
            try record.save(db)

            let previousLinks = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .filter(Column("address_id") == normalizedAddressId)
                .fetchAll(db)
            if !previousLinks.isEmpty {
                try CachedBuildingAddressLinkRecord
                    .filter(previousLinks.map(\.id).contains(Column("id")))
                    .deleteAll(db)
            }

            let linkRecord = CachedBuildingAddressLinkRecord(
                id: cacheScopedId(campaignId: campaignId, entityId: "\(fallbackId.lowercased()):\(normalizedAddressId)"),
                campaignId: campaignId,
                buildingId: fallbackId,
                addressId: normalizedAddressId,
                confidence: 1,
                source: "manual_fallback",
                updatedAt: now
            )
            try linkRecord.save(db)

            let updatedFeature: AddressFeature?
            if let addressFeature {
                updatedFeature = AddressFeature(
                    type: addressFeature.type,
                    id: addressFeature.id,
                    geometry: addressFeature.geometry,
                    properties: AddressProperties(
                        id: addressFeature.properties.id,
                        gersId: addressFeature.properties.gersId,
                        buildingGersId: fallbackId,
                        houseNumber: addressFeature.properties.houseNumber,
                        streetName: addressFeature.properties.streetName,
                        postalCode: addressFeature.properties.postalCode,
                        locality: addressFeature.properties.locality,
                        formatted: addressFeature.properties.formatted,
                        source: addressFeature.properties.source
                    )
                )
            } else {
                updatedFeature = nil
            }

            let updatedAddressRecord = CachedAddressRecord(
                id: addressRecord.id,
                campaignId: addressRecord.campaignId,
                buildingId: fallbackId,
                address: addressRecord.address,
                unit: addressRecord.unit,
                city: addressRecord.city,
                province: addressRecord.province,
                postalCode: addressRecord.postalCode,
                latitude: addressRecord.latitude,
                longitude: addressRecord.longitude,
                payloadJSON: updatedFeature.flatMap { OfflineJSONCodec.encode($0) } ?? addressRecord.payloadJSON,
                updatedAt: now
            )
            try updatedAddressRecord.save(db)

            return feature
        }
    }

    func markFallbackBuildingSynced(campaignId: String, addressId: UUID) async {
        await updateFallbackBuildingSyncStatus(campaignId: campaignId, addressId: addressId, status: "synced")
    }

    func markFallbackBuildingFailed(campaignId: String, addressId: UUID) async {
        await updateFallbackBuildingSyncStatus(campaignId: campaignId, addressId: addressId, status: "failed")
    }

    private func updateFallbackBuildingSyncStatus(campaignId: String, addressId: UUID, status: String) async {
        let updatedAt = OfflineDateCodec.string(from: Date())
        try? await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_fallback_buildings
                SET sync_status = ?,
                    updated_at = ?
                WHERE campaign_id = ?
                  AND address_id = ?
                """,
                arguments: [status, updatedAt, campaignId, addressId.uuidString.lowercased()]
            )
        }
    }

    func mergeLocalFallbackBuildings(
        campaignId: String,
        into collection: BuildingFeatureCollection
    ) async -> BuildingFeatureCollection {
        let fallbackFeatures = await getLocalFallbackBuildingFeatures(campaignId: campaignId)
        guard !fallbackFeatures.isEmpty else { return collection }

        var seen = Set(collection.features.compactMap { ($0.id ?? $0.properties.canonicalBuildingIdentifier)?.lowercased() })
        var merged = collection.features
        for feature in fallbackFeatures {
            let identifier = (feature.id ?? feature.properties.canonicalBuildingIdentifier ?? feature.properties.id).lowercased()
            guard seen.insert(identifier).inserted else { continue }
            merged.append(feature)
        }
        return BuildingFeatureCollection(type: collection.type, features: merged)
    }

    func getLocalFallbackBuildingFeatures(campaignId: String) async -> [BuildingFeature] {
        (try? await dbQueue.read { db in
            let records = try LocalFallbackBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            return records.compactMap(Self.decodeLocalFallbackBuildingFeature(from:))
        }) ?? []
    }

    func unlinkAddressFromBuildingLocally(
        campaignId: String,
        buildingId: String,
        addressId: String,
        deleteManualAddress: Bool
    ) async -> [UUID] {
        let normalizedAddressId = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBuildingId = buildingId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAddressId.isEmpty, !normalizedBuildingId.isEmpty else { return [] }

        let updatedAt = OfflineDateCodec.string(from: Date())
        return (try? await dbQueue.write { db in
            let buildingRecords = try CachedBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            var buildingIdentifiers = Set([normalizedBuildingId])
            for record in buildingRecords {
                let feature = OfflineJSONCodec.decode(BuildingFeature.self, from: record.payloadJSON)
                let recordIdentifiers = Set(
                    ([record.sourceId, record.externalId, feature?.id, feature?.properties.gersId, feature?.properties.buildingId, feature?.properties.id]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        + (feature?.properties.buildingIdentifierCandidates.map { $0.lowercased() } ?? []))
                )
                if recordIdentifiers.contains(normalizedBuildingId) {
                    buildingIdentifiers.formUnion(recordIdentifiers)
                }
            }

            let linkRecords = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            let linkIdsToDelete = linkRecords.compactMap { record -> String? in
                let linkAddressId = record.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let linkBuildingId = record.buildingId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return linkAddressId == normalizedAddressId && buildingIdentifiers.contains(linkBuildingId)
                    ? record.id
                    : nil
            }
            if !linkIdsToDelete.isEmpty {
                try CachedBuildingAddressLinkRecord
                    .filter(linkIdsToDelete.contains(Column("id")))
                    .deleteAll(db)
            }

            if deleteManualAddress {
                try Self.deleteAddressRows(
                    db,
                    campaignId: campaignId,
                    normalizedAddressId: normalizedAddressId
                )
            } else {
                let addressRecords = try CachedAddressRecord
                    .filter(Column("campaign_id") == campaignId)
                    .fetchAll(db)

                for record in addressRecords where Self.record(record, campaignId: campaignId, matchesAddressId: normalizedAddressId) {
                    let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
                    let updatedFeature: AddressFeature?
                    if let feature {
                        let updatedProperties = AddressProperties(
                            id: feature.properties.id,
                            gersId: feature.properties.gersId,
                            buildingGersId: nil,
                            houseNumber: feature.properties.houseNumber,
                            streetName: feature.properties.streetName,
                            postalCode: feature.properties.postalCode,
                            locality: feature.properties.locality,
                            formatted: feature.properties.formatted,
                            source: feature.properties.source
                        )
                        updatedFeature = AddressFeature(
                            type: feature.type,
                            id: feature.id,
                            geometry: feature.geometry,
                            properties: updatedProperties
                        )
                    } else {
                        updatedFeature = nil
                    }

                    let updated = CachedAddressRecord(
                        id: record.id,
                        campaignId: record.campaignId,
                        buildingId: nil,
                        address: record.address,
                        unit: record.unit,
                        city: record.city,
                        province: record.province,
                        postalCode: record.postalCode,
                        latitude: record.latitude,
                        longitude: record.longitude,
                        payloadJSON: updatedFeature.flatMap { OfflineJSONCodec.encode($0) } ?? record.payloadJSON,
                        updatedAt: updatedAt
                    )
                    try updated.save(db)
                }
            }

            let remainingLinks = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            return remainingLinks.compactMap { record -> UUID? in
                let linkBuildingId = record.buildingId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard buildingIdentifiers.contains(linkBuildingId) else { return nil }
                return UUID(uuidString: record.addressId)
            }
        }) ?? []
    }

    func deleteAddressLocally(
        campaignId: String,
        addressId: String
    ) async {
        let normalizedAddressId = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAddressId.isEmpty else { return }

        try? await dbQueue.write { db in
            try Self.deleteAddressRows(
                db,
                campaignId: campaignId,
                normalizedAddressId: normalizedAddressId
            )
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

    func upsertStatuses(rows: [AddressStatusRow], preserveDirty: Bool = true) async {
        let now = Date()
        try? await dbQueue.write { db in
            for row in rows {
                let recordId = cacheScopedId(campaignId: row.campaignId.uuidString, entityId: row.addressId.uuidString)
                if preserveDirty,
                   let existing = try CachedAddressStatusRecord.fetchOne(db, key: recordId),
                   existing.dirty != 0 {
                    continue
                }

                let record = CachedAddressStatusRecord(
                    id: recordId,
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

    private static func decodeCachedBuildingFeature(from record: CachedBuildingRecord) -> BuildingFeature? {
        if let feature = OfflineJSONCodec.decode(BuildingFeature.self, from: record.payloadJSON) {
            return feature
        }
        guard let geometry = OfflineJSONCodec.decode(MapFeatureGeoJSONGeometry.self, from: record.geometryGeoJSON),
              let properties = OfflineJSONCodec.decode(BuildingProperties.self, from: record.propertiesJSON) else {
            return nil
        }
        return BuildingFeature(
            type: "Feature",
            id: record.sourceId ?? record.id,
            geometry: geometry,
            properties: properties
        )
    }

    private static func decodeLocalFallbackBuildingFeature(from record: LocalFallbackBuildingRecord) -> BuildingFeature? {
        if let feature = OfflineJSONCodec.decode(BuildingFeature.self, from: record.payloadJSON) {
            return feature
        }
        guard let geometry = OfflineJSONCodec.decode(MapFeatureGeoJSONGeometry.self, from: record.geometryGeoJSON) else {
            return nil
        }
        let properties = BuildingProperties(
            id: record.localGeometryId,
            buildingId: record.localGeometryId,
            addressId: record.addressId,
            gersId: record.localGeometryId,
            height: 8,
            heightM: 8,
            minHeight: 0,
            isTownhome: false,
            unitsCount: 1,
            addressText: nil,
            matchMethod: "manual_fallback",
            featureStatus: "matched",
            featureType: "manual_fallback",
            status: "not_visited",
            scansToday: 0,
            scansTotal: 0,
            lastScanSecondsAgo: nil,
            houseNumber: nil,
            streetName: nil,
            confidence: 1,
            source: record.geometrySource,
            addressCount: 1,
            areaSqm: 80,
            buildingType: "residential",
            qrScanned: false,
            isLinked: true
        )
        return BuildingFeature(
            type: "Feature",
            id: record.localGeometryId,
            geometry: geometry,
            properties: properties
        )
    }

    func getCampaignMapBundle(campaignId: String) async -> OfflineCampaignMapBundle? {
        try? await dbQueue.read { db in
            let buildingRecords = try CachedBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let fallbackRecords = try LocalFallbackBuildingRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let addressRecords = try CachedAddressRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let linkRecords = try CachedBuildingAddressLinkRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)
            let roadRecords = try CachedRoadRecord
                .filter(Column("campaign_id") == campaignId)
                .fetchAll(db)

            guard !buildingRecords.isEmpty || !addressRecords.isEmpty || !roadRecords.isEmpty else {
                return nil
            }

            let buildings = buildingRecords.compactMap { record in
                Self.decodeCachedBuildingFeature(from: record)
            }
            let fallbackBuildings = fallbackRecords.compactMap(Self.decodeLocalFallbackBuildingFeature(from:))
            var seenBuildingIds = Set(buildings.compactMap { ($0.id ?? $0.properties.canonicalBuildingIdentifier)?.lowercased() })
            let mergedBuildings = buildings + fallbackBuildings.filter { feature in
                let identifier = (feature.id ?? feature.properties.canonicalBuildingIdentifier ?? feature.properties.id).lowercased()
                return seenBuildingIds.insert(identifier).inserted
            }
            let addresses = addressRecords.compactMap { record in
                OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
            }
            let linkedBundle = Self.mergeCachedBuildingAddressLinks(
                linkRecords,
                buildings: mergedBuildings,
                addresses: addresses
            )
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

            return OfflineCampaignMapBundle(
                buildings: BuildingFeatureCollection(type: "FeatureCollection", features: linkedBundle.buildings),
                addresses: AddressFeatureCollection(type: "FeatureCollection", features: linkedBundle.addresses),
                roads: RoadFeatureCollection(type: "FeatureCollection", features: roads)
            )
        }
    }

    private static func mergeCachedBuildingAddressLinks(
        _ linkRecords: [CachedBuildingAddressLinkRecord],
        buildings: [BuildingFeature],
        addresses: [AddressFeature]
    ) -> (buildings: [BuildingFeature], addresses: [AddressFeature]) {
        guard !linkRecords.isEmpty else {
            return (buildings, addresses)
        }

        let linksByBuilding = Dictionary(grouping: linkRecords) {
            $0.buildingId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let linksByAddress = Dictionary(
            grouping: linkRecords,
            by: { $0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        ).compactMapValues { records in
            records.sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }.first
        }
        let addressesById = Dictionary(uniqueKeysWithValues: addresses.compactMap { feature -> (String, AddressFeature)? in
            guard let id = feature.properties.id ?? feature.id else { return nil }
            return (id.lowercased(), feature)
        })

        let updatedBuildings = buildings.map { feature -> BuildingFeature in
            let identifiers = feature.properties.buildingIdentifierCandidates.map { $0.lowercased() }
            let links = identifiers.flatMap { linksByBuilding[$0] ?? [] }
            guard !links.isEmpty else { return feature }

            let linkedAddresses = links.compactMap {
                addressesById[$0.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
            }
            let addressIds = Array(Set(feature.properties.addressIds + links.map(\.addressId))).sorted()
            let firstAddress = linkedAddresses.first
            let bestConfidence = max(
                feature.properties.confidence ?? 0,
                links.compactMap(\.confidence).max() ?? 0
            )
            let bestMatch = links
                .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
                .first?
                .source

            let updatedProperties = BuildingProperties(
                id: feature.properties.id,
                buildingId: feature.properties.buildingId ?? links.first?.buildingId,
                addressId: addressIds.count == 1 ? addressIds.first : feature.properties.addressId,
                addressIds: addressIds,
                gersId: feature.properties.gersId,
                height: feature.properties.height,
                heightM: feature.properties.heightM,
                minHeight: feature.properties.minHeight,
                isTownhome: feature.properties.isTownhome || addressIds.count > 1,
                unitsCount: max(feature.properties.unitsCount, addressIds.count),
                addressText: addressIds.count == 1 ? firstAddress?.properties.formatted ?? feature.properties.addressText : feature.properties.addressText,
                matchMethod: feature.properties.matchMethod ?? bestMatch,
                featureStatus: "matched",
                featureType: "matched_house",
                status: feature.properties.status,
                scansToday: feature.properties.scansToday,
                scansTotal: feature.properties.scansTotal,
                lastScanSecondsAgo: feature.properties.lastScanSecondsAgo,
                houseNumber: addressIds.count == 1 ? firstAddress?.properties.houseNumber ?? feature.properties.houseNumber : feature.properties.houseNumber,
                streetName: addressIds.count == 1 ? firstAddress?.properties.streetName ?? feature.properties.streetName : feature.properties.streetName,
                confidence: bestConfidence > 0 ? bestConfidence : feature.properties.confidence,
                source: feature.properties.source,
                addressCount: max(feature.properties.addressCount ?? 0, addressIds.count),
                areaSqm: feature.properties.areaSqm,
                buildingType: feature.properties.buildingType,
                qrScanned: feature.properties.qrScanned,
                isLinked: true
            )
            return BuildingFeature(
                type: feature.type,
                id: feature.id,
                geometry: feature.geometry,
                properties: updatedProperties
            )
        }

        let updatedAddresses = addresses.map { feature -> AddressFeature in
            guard let id = feature.properties.id ?? feature.id,
                  let link = linksByAddress[id.lowercased()] else {
                return feature
            }

            let updatedProperties = AddressProperties(
                id: feature.properties.id,
                gersId: feature.properties.gersId,
                buildingGersId: feature.properties.buildingGersId ?? link.buildingId,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName,
                postalCode: feature.properties.postalCode,
                locality: feature.properties.locality,
                formatted: feature.properties.formatted,
                source: feature.properties.source
            )
            return AddressFeature(
                type: feature.type,
                id: feature.id,
                geometry: feature.geometry,
                properties: updatedProperties
            )
        }

        return (updatedBuildings, updatedAddresses)
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

    func getDirtyStatuses(campaignId: UUID) async -> [UUID: AddressStatusRow] {
        (try? await dbQueue.read { db in
            let records = try CachedAddressStatusRecord
                .filter(Column("campaign_id") == campaignId.uuidString && Column("dirty") != 0)
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
            let addressOrphans = try CachedAddressOrphanRecord
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
                addressOrphans: addressOrphans,
                statuses: statuses,
                roads: roads,
                metadata: metadata
            )
        }) ?? CampaignOfflineAssetCounts(
            buildings: 0,
            addresses: 0,
            buildingLinks: 0,
            addressOrphans: 0,
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

    private static func cachedCampaign(
        campaignId: UUID,
        record: CachedCampaignRecord?,
        addressRecords: [CachedAddressRecord]
    ) -> CampaignV2 {
        let payload = jsonObject(from: record?.payloadJSON)
        let addresses = campaignAddresses(from: addressRecords, campaignId: campaignId.uuidString)
        let createdAt = dateValue(payload["created_at"])
            ?? dateValue(payload["createdAt"])
            ?? OfflineDateCodec.date(from: record?.downloadedAt)
            ?? OfflineDateCodec.date(from: record?.updatedAt)
            ?? Date()
        let totalFlyers = intValue(payload["total_flyers"])
            ?? intValue(payload["totalFlyers"])
            ?? intValue(payload["address_count"])
            ?? addresses.count

        return CampaignV2(
            id: campaignId,
            name: stringValue(payload["title"]) ?? stringValue(payload["name"]) ?? record?.name ?? "Campaign",
            type: (stringValue(payload["type"]).flatMap(CampaignType.init(dbValue:))
                ?? stringValue(payload["type"]).flatMap(CampaignType.init(rawValue:)))
                ?? .flyer,
            addressSource: stringValue(payload["address_source"]).flatMap(AddressSource.init(rawValue:))
                ?? stringValue(payload["addressSource"]).flatMap(AddressSource.init(rawValue:))
                ?? .closestHome,
            addresses: addresses,
            totalFlyers: totalFlyers,
            scans: intValue(payload["scans"]) ?? 0,
            conversions: intValue(payload["conversions"]) ?? 0,
            createdAt: createdAt,
            status: stringValue(payload["status"]).flatMap(CampaignStatus.init(rawValue:))
                ?? record?.mode.flatMap(CampaignStatus.init(rawValue:))
                ?? .draft,
            seedQuery: stringValue(payload["region"]) ?? stringValue(payload["seedQuery"]),
            dataConfidence: codableValue(CampaignDataConfidenceSummary.self, from: payload["data_confidence_summary"])
                ?? codableValue(CampaignDataConfidenceSummary.self, from: payload["dataConfidence"]),
            provisionStatus: stringValue(payload["provision_status"]).flatMap(CampaignProvisionStatus.init(rawValue:))
                ?? stringValue(payload["provisionStatus"]).flatMap(CampaignProvisionStatus.init(rawValue:)),
            provisionSource: stringValue(payload["provision_source"]).flatMap(CampaignProvisionSource.init(rawValue:))
                ?? stringValue(payload["provisionSource"]).flatMap(CampaignProvisionSource.init(rawValue:)),
            provisionPhase: stringValue(payload["provision_phase"]).flatMap(CampaignProvisionPhase.init(rawValue:))
                ?? stringValue(payload["provisionPhase"]).flatMap(CampaignProvisionPhase.init(rawValue:)),
            addressesReadyAt: dateValue(payload["addresses_ready_at"]) ?? dateValue(payload["addressesReadyAt"]),
            mapReadyAt: dateValue(payload["map_ready_at"]) ?? dateValue(payload["mapReadyAt"]),
            optimizedAt: dateValue(payload["optimized_at"]) ?? dateValue(payload["optimizedAt"]),
            hasParcels: boolValue(payload["has_parcels"]) ?? boolValue(payload["hasParcels"]),
            buildingLinkConfidence: doubleValue(payload["building_link_confidence"]) ?? doubleValue(payload["buildingLinkConfidence"]),
            mapMode: stringValue(payload["map_mode"]).flatMap(CampaignMapMode.init(rawValue:))
                ?? stringValue(payload["mapMode"]).flatMap(CampaignMapMode.init(rawValue:)),
            coverageScore: intValue(payload["coverage_score"]) ?? intValue(payload["coverageScore"]),
            dataQuality: stringValue(payload["data_quality"]).flatMap(CampaignDataQuality.init(rawValue:))
                ?? stringValue(payload["dataQuality"]).flatMap(CampaignDataQuality.init(rawValue:)),
            standardModeRecommended: boolValue(payload["standard_mode_recommended"]) ?? boolValue(payload["standardModeRecommended"]),
            dataQualityReason: stringValue(payload["data_quality_reason"]) ?? stringValue(payload["dataQualityReason"])
        )
    }

    private static func campaignPayloadJSON(from row: CampaignDBRow, totalFlyers: Int?) -> String? {
        guard
            let encoded = OfflineJSONCodec.encode(row),
            let data = encoded.data(using: .utf8),
            var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let totalFlyers {
            payload["total_flyers"] = totalFlyers
            payload["address_count"] = totalFlyers
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return encoded
        }
        return String(data: payloadData, encoding: .utf8)
    }

    private static func campaignAddresses(
        from records: [CachedAddressRecord],
        campaignId: String
    ) -> [CampaignAddress] {
        records.compactMap { record in
            guard let addressId = uuidValue(from: record, campaignId: campaignId) else { return nil }
            let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
            let coordinate = coordinateValue(from: record, feature: feature)
            let label = feature?.properties.formatted?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? record.address?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Address"

            return CampaignAddress(
                id: addressId,
                address: label.isEmpty ? "Address" : label,
                coordinate: coordinate
            )
        }
    }

    private static func addressRows(
        from records: [CachedAddressRecord],
        campaignId: String
    ) -> [CampaignAddressRow] {
        records.compactMap { record in
            guard let addressId = uuidValue(from: record, campaignId: campaignId) else { return nil }
            let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
            guard let coordinate = coordinateValue(from: record, feature: feature) else { return nil }
            let label = feature?.properties.formatted?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? record.address?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Address"

            return CampaignAddressRow(
                id: addressId,
                formatted: label.isEmpty ? "Address" : label,
                lat: coordinate.latitude,
                lon: coordinate.longitude
            )
        }
    }

    private static func uuidValue(from record: CachedAddressRecord, campaignId: String) -> UUID? {
        let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
        let scopedPrefix = "\(campaignId.lowercased()):"
        let unscopedRecordId = record.id.lowercased().hasPrefix(scopedPrefix)
            ? String(record.id.dropFirst(scopedPrefix.count))
            : record.id

        return [
            feature?.properties.id,
            feature?.id,
            unscopedRecordId
        ]
        .compactMap { $0 }
        .lazy
        .compactMap(UUID.init(uuidString:))
        .first
    }

    private static func record(
        _ record: CachedAddressRecord,
        campaignId: String,
        matchesAddressId normalizedAddressId: String
    ) -> Bool {
        let feature = OfflineJSONCodec.decode(AddressFeature.self, from: record.payloadJSON)
        let scopedPrefix = "\(campaignId.lowercased()):"
        let unscopedRecordId = record.id.lowercased().hasPrefix(scopedPrefix)
            ? String(record.id.dropFirst(scopedPrefix.count))
            : record.id

        let ids = [
            feature?.properties.id,
            feature?.id,
            unscopedRecordId
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        return ids.contains(normalizedAddressId)
    }

    private static func deleteAddressRows(
        _ db: Database,
        campaignId: String,
        normalizedAddressId: String
    ) throws {
        let addressRecords = try CachedAddressRecord
            .filter(Column("campaign_id") == campaignId)
            .fetchAll(db)

        let addressCacheIds = addressRecords
            .filter { record($0, campaignId: campaignId, matchesAddressId: normalizedAddressId) }
            .map(\.id)

        if !addressCacheIds.isEmpty {
            try CachedAddressRecord
                .filter(addressCacheIds.contains(Column("id")))
                .deleteAll(db)
        }

        let linkIds = try CachedBuildingAddressLinkRecord
            .filter(Column("campaign_id") == campaignId)
            .fetchAll(db)
            .compactMap { record -> String? in
                record.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAddressId
                    ? record.id
                    : nil
            }

        if !linkIds.isEmpty {
            try CachedBuildingAddressLinkRecord
                .filter(linkIds.contains(Column("id")))
                .deleteAll(db)
        }

        let statusIds = try CachedAddressStatusRecord
            .filter(Column("campaign_id") == campaignId)
            .fetchAll(db)
            .compactMap { record -> String? in
                record.addressId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAddressId
                    ? record.id
                    : nil
            }

        if !statusIds.isEmpty {
            try CachedAddressStatusRecord
                .filter(statusIds.contains(Column("id")))
                .deleteAll(db)
        }

        let metadataIds = try CachedAddressCaptureMetadataRecord
            .filter(Column("campaign_id") == campaignId)
            .fetchAll(db)
            .compactMap { record -> String? in
                record.addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAddressId
                    ? record.id
                    : nil
            }

        if !metadataIds.isEmpty {
            try CachedAddressCaptureMetadataRecord
                .filter(metadataIds.contains(Column("id")))
                .deleteAll(db)
        }
    }

    private static func coordinateValue(
        from record: CachedAddressRecord,
        feature: AddressFeature?
    ) -> CLLocationCoordinate2D? {
        if let latitude = record.latitude,
           let longitude = record.longitude {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }

        if let point = feature?.geometry.asPoint,
           point.count >= 2 {
            let coordinate = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
            return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        }

        return nil
    }

    private static func jsonObject(from string: String?) -> [String: Any] {
        guard let string,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func isQuickStartCampaign(payloadJSON: String?) -> Bool {
        let payload = jsonObject(from: payloadJSON)
        return (stringValue(payload["tags"]) ?? "")
            .lowercased()
            .contains("quick_start")
    }

    private static func codableValue<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value) else {
            return nil
        }
        return try? JSONDecoder.supabaseDates.decode(type, from: data)
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return Bool(value)
        default:
            return nil
        }
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? String {
            return OfflineDateCodec.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        }
        return nil
    }

    private static func pointGeometry(for coordinate: CLLocationCoordinate2D) -> MapFeatureGeoJSONGeometry? {
        mapFeatureGeometry(type: "Point", coordinates: [coordinate.longitude, coordinate.latitude])
    }

    private static func fallbackBuildingId(addressId: UUID) -> String {
        "fallback_\(addressId.uuidString.lowercased())"
    }

    private static func fallbackRectangleGeometry(
        center: CLLocationCoordinate2D,
        widthMeters: Double = 10,
        depthMeters: Double = 8
    ) -> MapFeatureGeoJSONGeometry? {
        guard CLLocationCoordinate2DIsValid(center) else { return nil }
        let metersPerDegreeLatitude = 111_320.0
        let latitudeRadians = center.latitude * .pi / 180
        let metersPerDegreeLongitude = max(1, metersPerDegreeLatitude * cos(latitudeRadians))
        let halfLatitude = (depthMeters / 2) / metersPerDegreeLatitude
        let halfLongitude = (widthMeters / 2) / metersPerDegreeLongitude
        let west = center.longitude - halfLongitude
        let east = center.longitude + halfLongitude
        let south = center.latitude - halfLatitude
        let north = center.latitude + halfLatitude
        let ring = [
            [west, south],
            [east, south],
            [east, north],
            [west, north],
            [west, south]
        ]
        return mapFeatureGeometry(type: "Polygon", coordinates: [ring])
    }

    private static func mapFeatureGeometry(type: String, coordinates: Any) -> MapFeatureGeoJSONGeometry? {
        let payload: [String: Any] = [
            "type": type,
            "coordinates": coordinates
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
