import Foundation
import CoreLocation

enum CanonicalParcelFieldGeometry {
    static func contains(_ point: [Double], in geometry: CanonicalWKBGeometry) -> Bool {
        guard point.count >= 2 else { return false }
        func ringContains(_ ring: [[Double]]) -> Bool {
            guard ring.count >= 3, ring.allSatisfy({ $0.count >= 2 }) else { return false }
            var inside = false
            var previous = ring.count - 1
            for current in ring.indices {
                let a = ring[current], b = ring[previous]
                if (a[1] > point[1]) != (b[1] > point[1]),
                   point[0] < (b[0] - a[0]) * (point[1] - a[1]) / (b[1] - a[1]) + a[0] {
                    inside.toggle()
                }
                previous = current
            }
            return inside
        }
        switch geometry {
        case .polygon(let rings):
            guard let outer = rings.first, ringContains(outer) else { return false }
            return !rings.dropFirst().contains(where: ringContains)
        case .multiPolygon(let polygons), .collection(let polygons):
            return polygons.contains { contains(point, in: $0) }
        default:
            return false
        }
    }
    static func rings(for parcel: ParcelFeature, index: CanonicalCompactFieldIndex?) -> [[CLLocationCoordinate2D]] {
        // Field snapshots contain exact geometry plus local parcel corrections.
        // Never replace a moved parcel with its immutable archive shape.
        let current = SessionParcelAutoCompleteTarget.rings(from: parcel.geometry)
        if !current.isEmpty { return current }
        let rawId = [parcel.properties.parcelId, parcel.properties.externalId, parcel.id, parcel.properties.id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let id = rawId.map { UUID(uuidString: $0)?.uuidString.lowercased() ?? $0 }
        let exact = id.flatMap { value in try? index?.geometry(featureId: "parcel:\(value)") }
        if let exact {
            let rings = SessionParcelAutoCompleteTarget.rings(from: exact)
            if !rings.isEmpty { return rings }
        }
        return SessionParcelAutoCompleteTarget.rings(from: parcel.geometry)
    }
}

/// The compact v3 response carries feature metadata and links, while geometry
/// is loaded from the verified PMTiles and WGP1 files.
struct CanonicalCompactRecord<Properties: Codable>: Codable {
    let id: String
    let featureId: String
    let coordinate: [Double]
    let bounds: [Double]
    let properties: Properties
    enum CodingKeys: String, CodingKey { case id, coordinate, bounds, properties, featureId = "feature_id" }
}

struct CanonicalCompactCampaign: Decodable {
    struct Records: Decodable {
        let buildings: [CanonicalCompactRecord<BuildingProperties>]
        let addresses: [CanonicalCompactRecord<AddressProperties>]
        let parcels: [CanonicalCompactRecord<ParcelProperties>]
    }
    struct RoadRecord: Decodable {
        let id: String
        let sourceId: AnyCodable?
        let properties: RoadProperties
        enum CodingKeys: String, CodingKey { case id, properties, sourceId = "source_id" }
    }

    let schema: String
    let campaignId: String
    let assetSignature: String
    let canonicalSignature: String
    let sourceVersion: String
    let tiles: CanonicalCampaignTiles
    let records: Records
    let links: [ClientBuildingAddressLink]
    let buildingUnits: [CanonicalTownhouseUnit]
    let roadRecords: [RoadRecord]
    let addressOrphans: [AnyCodable]?
    let buildingOrphans: [AnyCodable]?
    let counts: CanonicalCampaignMapBundleCounts?
    let displayModeHint: String?
    let linksStatus: String?
    let reconciliation: CanonicalMapReconciliation?
    let reconciliationReport: CanonicalMapReconciliationReport?
    let builtAt: String?
    let expiresAt: String?
    let updatedAt: String?
    let layerFetchedAt: CanonicalCampaignMapLayerFetchedAt?

    enum CodingKeys: String, CodingKey {
        case schema, tiles, records, links, counts, reconciliation
        case campaignId = "campaign_id", assetSignature = "asset_signature", canonicalSignature = "canonical_signature"
        case sourceVersion = "source_version", buildingUnits = "building_units", roadRecords = "road_records"
        case addressOrphans = "address_orphans", buildingOrphans = "building_orphans"
        case displayModeHint = "display_mode_hint", linksStatus = "links_status", reconciliationReport = "reconciliation_report"
        case builtAt = "built_at", expiresAt = "expires_at", updatedAt = "updated_at", layerFetchedAt = "layer_fetched_at"
    }
}

/// Typed field objects built from compact metadata and binary WKB. The map
/// renderer continues to use the PMTiles archive, not these field shapes.
struct CanonicalCompactFieldSnapshot {
    let buildings: BuildingFeatureCollection
    let addresses: AddressFeatureCollection
    let parcels: ParcelFeatureCollection
    let roads: RoadFeatureCollection
}

struct CanonicalTileRenderPlan {
    var buildingIds: [String] = []
    var addressIds: [String] = []
    var parcelIds: [String] = []
    var buildingEdits: [BuildingFeature] = []
    var addressEdits: [AddressFeature] = []
    var parcelEdits: [ParcelFeature] = []

    mutating func upsertAddressOverlay(_ feature: AddressFeature) {
        let id = (feature.properties.id ?? feature.id ?? "").lowercased()
        guard !id.isEmpty else { return }
        addressIds.removeAll { $0.lowercased() == id }
        addressEdits.removeAll { ($0.properties.id ?? $0.id ?? "").lowercased() == id }
        addressEdits.append(feature)
    }

}

/// Stable record lookup plus on-demand exact WKB decoding for field actions.
/// Live visit and QR state remain separate from this immutable index.
final class CanonicalCompactFieldIndex {
    enum IndexError: Error { case incompatibleBundle, missingGeometry, duplicateIdentity }
    let campaign: CanonicalCompactCampaign
    private let pack: CanonicalGeometryPack
    private let buildingsById: [String: CanonicalCompactRecord<BuildingProperties>]
    private let addressesById: [String: CanonicalCompactRecord<AddressProperties>]
    private let parcelsById: [String: CanonicalCompactRecord<ParcelProperties>]
    private let buildingAliasOwners: [String: Set<String>]
    private let addressesByBuildingAlias: [String: [String]]
    private let bestLinkByAddress: [String: ClientBuildingAddressLink]
    private let parcelSelectionIdsByAddress: [String: [String]]
    private let geometryLock = NSLock()
    private var decodedGeometry: [String: CanonicalWKBGeometry] = [:]

    init(campaign: CanonicalCompactCampaign, pack: CanonicalGeometryPack) throws {
        guard campaign.schema == "tiles-v3", let manifest = campaign.tiles.geometryPack,
              manifest.count == pack.count else { throw IndexError.incompatibleBundle }
        let available = Set(pack.ids)
        func index<P>(_ records: [CanonicalCompactRecord<P>], prefix: String) throws -> [String: CanonicalCompactRecord<P>] {
            var result: [String: CanonicalCompactRecord<P>] = [:]
            for record in records {
                guard !record.id.isEmpty, record.featureId == "\(prefix):\(record.id)",
                      record.coordinate.count >= 2, record.bounds.count == 4,
                      record.coordinate.allSatisfy(\.isFinite), record.bounds.allSatisfy(\.isFinite) else {
                    throw IndexError.incompatibleBundle
                }
                guard result[record.id] == nil else { throw IndexError.duplicateIdentity }
                guard available.contains(record.featureId) else { throw IndexError.missingGeometry }
                result[record.id] = record
            }
            return result
        }
        buildingsById = try index(campaign.records.buildings, prefix: "building")
        addressesById = try index(campaign.records.addresses, prefix: "address")
        parcelsById = try index(campaign.records.parcels, prefix: "parcel")
        var owners: [String: Set<String>] = [:]
        for record in campaign.records.buildings {
            for alias in Set(([record.id] + record.properties.buildingIdentifierCandidates).map { $0.lowercased() }) {
                owners[alias, default: []].insert(record.id)
            }
        }
        buildingAliasOwners = owners
        var links: [String: [String]] = [:]
        for link in campaign.links { links[link.buildingId.lowercased(), default: []].append(link.addressId) }
        addressesByBuildingAlias = links
        var addressLinks: [String: ClientBuildingAddressLink] = [:]
        for link in campaign.links {
            let key = UUID(uuidString: link.addressId)?.uuidString.lowercased() ?? link.addressId.lowercased()
            if addressLinks[key] == nil || link.confidence > addressLinks[key]!.confidence { addressLinks[key] = link }
        }
        bestLinkByAddress = addressLinks
        var parcelSelections: [String: [String]] = [:]
        for record in campaign.records.parcels {
            let p = record.properties
            let aliases = [record.id, p.id, p.parcelId, p.externalId, p.addressId].compactMap { $0 }
            for addressId in ([p.addressId].compactMap { $0 } + (p.addressIds ?? [])) {
                let key = addressId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty { parcelSelections[key, default: []].append(contentsOf: aliases) }
            }
        }
        parcelSelectionIdsByAddress = parcelSelections
        self.campaign = campaign
        self.pack = pack
    }

    func building(_ id: String) -> CanonicalCompactRecord<BuildingProperties>? { buildingsById[id] }
    func address(_ id: String) -> CanonicalCompactRecord<AddressProperties>? { addressesById[id] }
    func parcel(_ id: String) -> CanonicalCompactRecord<ParcelProperties>? { parcelsById[id] }

    /// Resolve only an unambiguous containing parcel. Bounds avoid decoding the
    /// thousands of unrelated parcel shapes in a large downloaded campaign.
    func parcelContaining(longitude: Double, latitude: Double) -> CanonicalCompactRecord<ParcelProperties>? {
        guard longitude.isFinite, latitude.isFinite else { return nil }
        var match: CanonicalCompactRecord<ParcelProperties>?
        for parcel in campaign.records.parcels {
            let bounds = parcel.bounds
            guard bounds.count >= 4, longitude >= bounds[0], latitude >= bounds[1],
                  longitude <= bounds[2], latitude <= bounds[3] else { continue }
            // A missing candidate shape makes the answer ambiguous: another
            // overlapping parcel may contain the point. Never auto-link based
            // on an incomplete geometry package.
            guard let geometry = try? geometry(featureId: parcel.featureId) else { return nil }
            guard CanonicalParcelFieldGeometry.contains([longitude, latitude], in: geometry) else { continue }
            if match != nil { return nil }
            match = parcel
        }
        return match
    }

    func parcelSelectionIds(forAddress id: String) -> [String] {
        parcelSelectionIdsByAddress[id.lowercased()] ?? []
    }

    func addressFeature(id: String) -> AddressFeature? {
        let normalizedId = UUID(uuidString: id)?.uuidString.lowercased() ?? id
        guard let record = addressesById[normalizedId], record.coordinate.count >= 2 else { return nil }
        let p = record.properties
        let linkedBuilding = bestLinkByAddress[normalizedId.lowercased()]?.buildingId
        let properties = AddressProperties(id: p.id, gersId: p.gersId,
            buildingGersId: p.buildingGersId ?? linkedBuilding, linkedBuildingId: p.linkedBuildingId,
            houseNumber: p.houseNumber, houseNumberLabel: p.houseNumberLabel, streetName: p.streetName,
            postalCode: p.postalCode, locality: p.locality, formatted: p.formatted, source: p.source,
            featureType: p.featureType, parcelId: p.parcelId, campaignParcelId: p.campaignParcelId,
            hasBuildingLink: p.hasBuildingLink, hasParcelLink: p.hasParcelLink, labelVisibilityMode: p.labelVisibilityMode,
            pinPlacement: p.pinPlacement, labelAnchorLon: p.labelAnchorLon, labelAnchorLat: p.labelAnchorLat,
            labelGroupKey: p.labelGroupKey, labelGroupIndex: p.labelGroupIndex, labelGroupCount: p.labelGroupCount,
            labelPriority: p.labelPriority)
        return AddressFeature(id: record.id,
            geometry: MapFeatureGeoJSONGeometry(type: "Point", coordinates: GeoJSONCoordinatesNode(point: record.coordinate)),
            properties: properties)
    }

    /// A vector-tile hit carries a clipped fragment and limited properties.
    /// Decode just the selected home's original footprint and full metadata.
    func exactBuildingFeature(id: String) throws -> BuildingFeature? {
        let normalizedId = UUID(uuidString: id)?.uuidString.lowercased() ?? id
        let record = buildingsById[normalizedId] ?? buildingAliasOwners[normalizedId.lowercased()]
            .flatMap { $0.count == 1 ? $0.first : nil }.flatMap { buildingsById[$0] }
        guard let record, let shape = try geometry(featureId: record.featureId) else { return nil }
        let geometry: MapFeatureGeoJSONGeometry
        switch shape {
        case .polygon(let rings):
            geometry = MapFeatureGeoJSONGeometry(type: "Polygon", coordinates: GeoJSONCoordinatesNode(polygon: rings))
        case .multiPolygon(let children):
            var polygons: [[[[Double]]]] = []
            for child in children {
                guard case .polygon(let rings) = child else { throw IndexError.incompatibleBundle }
                polygons.append(rings)
            }
            geometry = MapFeatureGeoJSONGeometry(type: "MultiPolygon", coordinates: GeoJSONCoordinatesNode(multiPolygon: polygons))
        default: throw IndexError.incompatibleBundle
        }
        return BuildingFeature(id: record.id, geometry: geometry, properties: record.properties)
    }

    /// Compatibility for existing field workflows while they move to direct
    /// index lookups. No GeoJSON payload or intermediate JSON file is built.
    func fieldSnapshot() throws -> CanonicalCompactFieldSnapshot {
        func nativeShape(_ id: String) throws -> MapFeatureGeoJSONGeometry {
            guard let shape = try geometry(featureId: id) else { throw IndexError.missingGeometry }
            switch shape {
            case .point(let coordinate):
                return MapFeatureGeoJSONGeometry(type: "Point", coordinates: GeoJSONCoordinatesNode(point: coordinate))
            case .lineString(let coordinates):
                return MapFeatureGeoJSONGeometry(type: "LineString", coordinates: GeoJSONCoordinatesNode(line: coordinates))
            case .polygon(let coordinates):
                return MapFeatureGeoJSONGeometry(type: "Polygon", coordinates: GeoJSONCoordinatesNode(polygon: coordinates))
            case .multiPolygon(let children):
                let polygons = try children.map { child -> [[[Double]]] in
                    guard case .polygon(let coordinates) = child else { throw IndexError.incompatibleBundle }
                    return coordinates
                }
                return MapFeatureGeoJSONGeometry(type: "MultiPolygon", coordinates: GeoJSONCoordinatesNode(multiPolygon: polygons))
            case .multiLineString(let children):
                let lines = try children.map { child -> [[Double]] in
                    guard case .lineString(let coordinates) = child else { throw IndexError.incompatibleBundle }
                    return coordinates
                }
                return MapFeatureGeoJSONGeometry(type: "MultiLineString", coordinates: GeoJSONCoordinatesNode(multiLine: lines))
            default: throw IndexError.incompatibleBundle
            }
        }
        let buildings = try campaign.records.buildings.map { record in
            BuildingFeature(id: record.id, geometry: try nativeShape(record.featureId), properties: record.properties)
        }
        let addresses = try campaign.records.addresses.map { record -> AddressFeature in
            guard let feature = addressFeature(id: record.id) else { throw IndexError.incompatibleBundle }
            return feature
        }
        let parcels = try campaign.records.parcels.map { record in
            ParcelFeature(id: record.id, geometry: try nativeShape(record.featureId), properties: record.properties)
        }
        let roads = try campaign.roadRecords.map { record in
            RoadFeature(id: record.properties.id ?? (record.sourceId?.value as? String),
                geometry: try nativeShape(record.id), properties: record.properties)
        }
        return CanonicalCompactFieldSnapshot(
            buildings: BuildingFeatureCollection(type: "FeatureCollection", features: buildings),
            addresses: AddressFeatureCollection(type: "FeatureCollection", features: addresses),
            parcels: ParcelFeatureCollection(type: "FeatureCollection", features: parcels),
            roads: RoadFeatureCollection(type: "FeatureCollection", features: roads))
    }

    func fieldBundle() throws -> CanonicalCampaignMapBundle {
        let snapshot = try fieldSnapshot()
        var bundle = CanonicalCampaignMapBundle(campaignId: campaign.campaignId,
            assetSignature: campaign.assetSignature, sourceVersion: campaign.sourceVersion,
            displayModeHint: campaign.displayModeHint, linksStatus: campaign.linksStatus,
            addresses: snapshot.addresses, buildings: snapshot.buildings, parcels: snapshot.parcels, roads: snapshot.roads,
            links: campaign.links, addressOrphans: campaign.addressOrphans, buildingOrphans: campaign.buildingOrphans,
            buildingUnits: campaign.buildingUnits, reconciliation: campaign.reconciliation,
            reconciliationReport: campaign.reconciliationReport, counts: campaign.counts,
            layerFetchedAt: campaign.layerFetchedAt, builtAt: campaign.builtAt,
            expiresAt: campaign.expiresAt, updatedAt: campaign.updatedAt)
        bundle.tiles = campaign.tiles
        bundle.canonicalSignature = campaign.canonicalSignature
        bundle.storageFormat = "tiles-v3"
        return bundle
    }

    func addressIds(forBuilding id: String) -> [String] {
        let normalizedId = UUID(uuidString: id)?.uuidString.lowercased() ?? id
        let building = buildingsById[normalizedId] ?? buildingAliasOwners[normalizedId.lowercased()]
            .flatMap { $0.count == 1 ? $0.first : nil }.flatMap { buildingsById[$0] }
        guard let building else { return [] }
        let aliases = Set(([building.id] + building.properties.buildingIdentifierCandidates).map { $0.lowercased() })
        // Avoid assigning a shared legacy alias to either of two buildings.
        let uniqueAliases = aliases.filter { buildingAliasOwners[$0]?.count == 1 }
        let linked = uniqueAliases.sorted().flatMap { addressesByBuildingAlias[$0] ?? [] }
        let candidates = building.properties.addressIds + [building.properties.addressId].compactMap { $0 } + linked
        var seen = Set<String>()
        return candidates.compactMap { value in
            let canonical = UUID(uuidString: value)?.uuidString.lowercased() ?? value
            guard addressesById[canonical] != nil, seen.insert(canonical).inserted else { return nil }
            return canonical
        }
    }

    func geometry(featureId: String) throws -> CanonicalWKBGeometry? {
        geometryLock.lock()
        let cached = decodedGeometry[featureId]
        geometryLock.unlock()
        if let cached { return cached }
        guard let bytes = try pack.wkb(for: featureId) else { return nil }
        var reader = CanonicalWKBReader(bytes)
        let value = try reader.read()
        geometryLock.lock()
        decodedGeometry[featureId] = value
        geometryLock.unlock()
        return value
    }

    /// Scope vector layers by stable IDs. Only local changes need a small
    /// editable overlay; unchanged campaign geometry stays in the archive.
    func renderPlan(buildings: [BuildingFeature], addresses: [AddressFeature], parcels: [ParcelFeature], editedItems: Set<String> = []) throws -> CanonicalTileRenderPlan {
        try Task.checkCancellation()
        // The three collections are independent; matching exact geometry for a
        // large map should not serialize all three kinds on one worker.
        let lock = NSLock()
        var parts = [CanonicalTileRenderPlan(), CanonicalTileRenderPlan(), CanonicalTileRenderPlan()]
        var failure: Error?
        DispatchQueue.concurrentPerform(iterations: 3) { kind in
            do {
                var plan = CanonicalTileRenderPlan()
                switch kind {
                case 0:
        for (offset, feature) in buildings.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            let aliases = feature.properties.buildingIdentifierCandidates + [feature.id].compactMap { $0 }
            let ids = Set(aliases.flatMap { buildingAliasOwners[$0.lowercased()] ?? [] })
            guard ids.count == 1, let id = ids.first, let record = buildingsById[id],
                  !editedItems.contains(CampaignMapEdits.buildingItem(feature).id),
                  Set(feature.properties.addressUUIDs) == Set(record.properties.addressUUIDs),
                  feature.properties.addressText == record.properties.addressText,
                  let exact = try geometry(featureId: record.featureId), feature.geometry.nativeGeometry == exact else {
                plan.buildingEdits.append(feature)
                continue
            }
            plan.buildingIds.append(id)
        }
                case 1:
        for (offset, feature) in addresses.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            let raw = feature.id ?? feature.properties.id ?? ""
            let id = UUID(uuidString: raw)?.uuidString.lowercased() ?? raw
            guard !editedItems.contains(CampaignMapEdits.addressItem(feature).id),
                  let record = addressesById[id], let coordinate = feature.geometry.asPoint,
                  coordinate == record.coordinate else {
                plan.addressEdits.append(feature)
                continue
            }
            plan.addressIds.append(id)
        }
                default:
        for (offset, feature) in parcels.enumerated() {
            if offset.isMultiple(of: 256) { try Task.checkCancellation() }
            let raw = [feature.properties.parcelId, feature.properties.externalId, feature.id, feature.properties.id]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            guard let raw else { continue }
            let id = UUID(uuidString: raw)?.uuidString.lowercased() ?? raw
            guard let record = parcelsById[id],
                  !editedItems.contains(CampaignMapEdits.parcelItem(feature).id),
                  Set(feature.properties.addressIds ?? []) == Set(record.properties.addressIds ?? []),
                  let exact = try geometry(featureId: record.featureId), feature.geometry.nativeGeometry == exact else {
                plan.parcelEdits.append(feature)
                continue
            }
            plan.parcelIds.append(id)
        }
                }
                lock.lock(); parts[kind] = plan; lock.unlock()
            } catch {
                lock.lock(); if failure == nil { failure = error }; lock.unlock()
            }
        }
        try Task.checkCancellation()
        if let failure { throw failure }
        var plan = CanonicalTileRenderPlan()
        plan.buildingIds = parts[0].buildingIds
        plan.buildingEdits = parts[0].buildingEdits
        plan.addressIds = parts[1].addressIds
        plan.addressEdits = parts[1].addressEdits
        plan.parcelIds = parts[2].parcelIds
        plan.parcelEdits = parts[2].parcelEdits
        return plan
    }

    /// Resolve exact parcel shapes only for unambiguous session targets.
    func parcelAutoCompleteTargets(
        addressIdsByTargetId: [String: [UUID]], buildingIdsByTargetId: [String: String]
    ) throws -> [SessionParcelAutoCompleteTarget] {
        var targetIdsByAddress: [UUID: Set<String>] = [:]
        for (target, addresses) in addressIdsByTargetId {
            for address in addresses { targetIdsByAddress[address, default: []].insert(target) }
        }
        var resolved: [SessionParcelAutoCompleteTarget] = []
        for parcel in campaign.records.parcels {
            let linked = ([parcel.properties.addressId].compactMap { $0 } + (parcel.properties.addressIds ?? []))
                .compactMap(UUID.init(uuidString:))
            let matched = Set(linked.flatMap { targetIdsByAddress[$0] ?? [] })
            guard matched.count == 1, let targetId = matched.first,
                  let addresses = addressIdsByTargetId[targetId], !addresses.isEmpty,
                  let shape = try geometry(featureId: parcel.featureId),
                  let target = SessionParcelAutoCompleteTarget(targetId: targetId,
                    buildingId: buildingIdsByTargetId[targetId], addressIds: addresses,
                    rings: SessionParcelAutoCompleteTarget.rings(from: shape)) else { continue }
            resolved.append(target)
        }
        return resolved
    }
}
