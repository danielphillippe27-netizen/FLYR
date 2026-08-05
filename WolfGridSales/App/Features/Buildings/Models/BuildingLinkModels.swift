// MARK: - Building-Address Link Models
// These types extend the existing building/address models with link-specific data
// Single source of truth: BuildingProperties, CampaignAddress, BuildingFeature (here)

import Foundation
import CoreLocation

// MARK: - Building Properties (from map RPC / S3)

/// Building feature properties from Supabase RPC (Gold, Silver/Diamond, address_point)
struct BuildingProperties: Codable {
    let id: String
    let buildingId: String?
    let addressId: String?
    let addressIds: [String]
    let gersId: String?
    let publicBuildingId: String?
    let canonicalBuildingId: String?
    let buildingIdentifierSource: String?
    let height: Double
    let heightM: Double?
    let minHeight: Double
    let isTownhome: Bool
    let unitsCount: Int
    let addressText: String?
    let matchMethod: String?
    let featureStatus: String?
    let featureType: String?
    let status: String
    let scansToday: Int
    let scansTotal: Int
    let lastScanSecondsAgo: Double?
    /// Gold/address_point: house number
    let houseNumber: String?
    /// Gold/address_point: street name
    let streetName: String?
    /// Match confidence 0.5–1.0
    let confidence: Double?
    /// "gold", "silver", or "address_point"
    let source: String?
    /// Gold multi-address: number of addresses in this building (RPC)
    let addressCount: Int?
    /// Source footprint area, used to filter non-linkable sheds/outbuildings.
    let areaSqm: Double?
    /// Source building classification, e.g. shed, garage, residential.
    let buildingType: String?
    /// QR code was scanned
    let qrScanned: Bool?
    /// True when the backend knows at least one campaign address is linked to this building.
    let isLinked: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case buildingId = "building_id"
        case addressId = "address_id"
        case addressIds = "address_ids"
        case gersId = "gers_id"
        case publicBuildingId = "public_building_id"
        case canonicalBuildingId = "canonical_building_id"
        case buildingIdentifierSource = "building_identifier_source"
        case height
        case heightM = "height_m"
        case minHeight = "min_height"
        case isTownhome = "is_townhome"
        case unitsCount = "units_count"
        case addressText = "address_text"
        case matchMethod = "match_method"
        case featureStatus = "feature_status"
        case featureType = "feature_type"
        case status
        case scansToday = "scans_today"
        case scansTotal = "scans_total"
        case lastScanSecondsAgo = "last_scan_seconds_ago"
        case houseNumber = "house_number"
        case streetName = "street_name"
        case confidence
        case source
        case addressCount = "address_count"
        case areaSqm = "area_sqm"
        case buildingType = "building_type"
        case qrScanned = "qr_scanned"
        case isLinked = "is_linked"
    }

    private struct FlexiblePropertyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    private static func decodeTrimmedString(
        from container: KeyedDecodingContainer<FlexiblePropertyKey>,
        keys: [String]
    ) -> String? {
        for rawKey in keys {
            guard let key = FlexiblePropertyKey(stringValue: rawKey) else { continue }
            if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? container.decodeIfPresent(Double.self, forKey: key), value.isFinite {
                let rounded = value.rounded()
                return abs(value - rounded) < .ulpOfOne ? String(Int64(rounded)) : String(value)
            }
        }
        return nil
    }

    private static func decodeStringArray(
        from container: KeyedDecodingContainer<FlexiblePropertyKey>,
        keys: [String]
    ) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for rawKey in keys {
            guard let key = FlexiblePropertyKey(stringValue: rawKey) else { continue }
            let rawValues: [String]
            if let decoded = try? container.decodeIfPresent([String].self, forKey: key) {
                rawValues = decoded
            } else if let decoded = try? container.decodeIfPresent([Int].self, forKey: key) {
                rawValues = decoded.map(String.init)
            } else {
                rawValues = []
            }

            for value in rawValues {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
                values.append(trimmed)
            }
        }
        return values
    }

    init(
        id: String,
        buildingId: String?,
        addressId: String?,
        addressIds: [String] = [],
        gersId: String?,
        publicBuildingId: String? = nil,
        canonicalBuildingId: String? = nil,
        buildingIdentifierSource: String? = nil,
        height: Double,
        heightM: Double?,
        minHeight: Double,
        isTownhome: Bool,
        unitsCount: Int,
        addressText: String?,
        matchMethod: String?,
        featureStatus: String?,
        featureType: String?,
        status: String,
        scansToday: Int,
        scansTotal: Int,
        lastScanSecondsAgo: Double?,
        houseNumber: String?,
        streetName: String?,
        confidence: Double?,
        source: String?,
        addressCount: Int?,
        areaSqm: Double?,
        buildingType: String?,
        qrScanned: Bool?,
        isLinked: Bool? = nil
    ) {
        self.id = id
        self.buildingId = buildingId
        self.addressId = addressId
        self.addressIds = addressIds
        self.gersId = gersId
        self.publicBuildingId = publicBuildingId
        self.canonicalBuildingId = canonicalBuildingId
        self.buildingIdentifierSource = buildingIdentifierSource
        self.height = height
        self.heightM = heightM
        self.minHeight = minHeight
        self.isTownhome = isTownhome
        self.unitsCount = unitsCount
        self.addressText = addressText
        self.matchMethod = matchMethod
        self.featureStatus = featureStatus
        self.featureType = featureType
        self.status = status
        self.scansToday = scansToday
        self.scansTotal = scansTotal
        self.lastScanSecondsAgo = lastScanSecondsAgo
        self.houseNumber = houseNumber
        self.streetName = streetName
        self.confidence = confidence
        self.source = source
        self.addressCount = addressCount
        self.areaSqm = areaSqm
        self.buildingType = buildingType
        self.qrScanned = qrScanned
        self.isLinked = isLinked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try decoder.container(keyedBy: FlexiblePropertyKey.self)

        func decodeDouble(_ key: CodingKeys, default fallback: Double) -> Double {
            if let value = try? c.decode(Double.self, forKey: key) { return value }
            if let value = try? c.decode(Int.self, forKey: key) { return Double(value) }
            return fallback
        }

        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        buildingId = try? c.decodeIfPresent(String.self, forKey: .buildingId)
        addressId = try? c.decodeIfPresent(String.self, forKey: .addressId)
        addressIds = Self.decodeStringArray(
            from: raw,
            keys: ["linked_address_ids", "address_ids", "campaign_address_ids"]
        )
        gersId = try? c.decodeIfPresent(String.self, forKey: .gersId)
        publicBuildingId = try? c.decodeIfPresent(String.self, forKey: .publicBuildingId)
        canonicalBuildingId = try? c.decodeIfPresent(String.self, forKey: .canonicalBuildingId)
        buildingIdentifierSource = try? c.decodeIfPresent(String.self, forKey: .buildingIdentifierSource)
        height = decodeDouble(.height, default: 10)
        heightM = (try? c.decodeIfPresent(Double.self, forKey: .heightM)) ?? (try? c.decodeIfPresent(Int.self, forKey: .heightM)).map(Double.init)
        minHeight = decodeDouble(.minHeight, default: 0)
        isTownhome = (try? c.decodeIfPresent(Bool.self, forKey: .isTownhome)) ?? false
        unitsCount = (try? c.decodeIfPresent(Int.self, forKey: .unitsCount)) ?? 1
        addressText = Self.decodeTrimmedString(
            from: raw,
            keys: ["address_text", "formatted", "formatted_address", "full_address", "display_address", "label", "address"]
        )
        matchMethod = try? c.decodeIfPresent(String.self, forKey: .matchMethod)
        featureStatus = try? c.decodeIfPresent(String.self, forKey: .featureStatus)
        featureType = try? c.decodeIfPresent(String.self, forKey: .featureType)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "not_visited"
        scansToday = (try? c.decodeIfPresent(Int.self, forKey: .scansToday)) ?? 0
        scansTotal = (try? c.decodeIfPresent(Int.self, forKey: .scansTotal)) ?? 0
        lastScanSecondsAgo = (try? c.decodeIfPresent(Double.self, forKey: .lastScanSecondsAgo)) ?? (try? c.decodeIfPresent(Int.self, forKey: .lastScanSecondsAgo)).map(Double.init)
        houseNumber = Self.decodeTrimmedString(
            from: raw,
            keys: ["house_number", "house_number_label", "houseNumber", "street_number", "street_no", "address_number", "number", "addr:housenumber"]
        )
        streetName = Self.decodeTrimmedString(
            from: raw,
            keys: ["street_name", "streetName", "primary_street_name", "street", "road_name", "road", "addr:street"]
        )
        confidence = (try? c.decodeIfPresent(Double.self, forKey: .confidence)) ?? (try? c.decodeIfPresent(Int.self, forKey: .confidence)).map(Double.init)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        addressCount = try? c.decodeIfPresent(Int.self, forKey: .addressCount)
        areaSqm = (try? c.decodeIfPresent(Double.self, forKey: .areaSqm)) ?? (try? c.decodeIfPresent(Int.self, forKey: .areaSqm)).map(Double.init)
        buildingType = try? c.decodeIfPresent(String.self, forKey: .buildingType)
        qrScanned = try? c.decodeIfPresent(Bool.self, forKey: .qrScanned)
        isLinked = try? c.decodeIfPresent(Bool.self, forKey: .isLinked)
    }

    var statusColor: String {
        if scansTotal > 0 || (qrScanned ?? false) { return "#8b5cf6" }
        switch status {
        case "hot", "lead", "appointment", "future_seller", "hot_lead": return "#facc15"
        case "visited": return "#22c55e"
        default: return "#ef4444"
        }
    }

    /// Canonical public identifier for a building feature.
    /// GERS/Overture and Diamond municipal ids both flow through this path.
    var canonicalBuildingIdentifier: String? {
        buildingIdentifierCandidates.first
    }

    var effectiveIsLinked: Bool {
        if let isLinked { return isLinked }
        if let addressId, !addressId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !addressUUIDs.isEmpty { return true }
        if (addressCount ?? 0) > 0 { return true }
        return featureStatus?.lowercased() == "matched"
    }

    var addressUUIDs: [UUID] {
        let rawIds = addressIds + [addressId].compactMap { $0 }
        var seen = Set<UUID>()
        return rawIds.compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { seen.insert($0).inserted }
    }

    func mergedLinkMetadata(from richer: BuildingProperties) -> BuildingProperties {
        let mergedAddressIds = {
            var seen = Set<String>()
            return (addressIds + richer.addressIds)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        }()

        return BuildingProperties(
            id: id,
            buildingId: buildingId ?? richer.buildingId,
            addressId: addressId ?? richer.addressId,
            addressIds: mergedAddressIds,
            gersId: gersId ?? richer.gersId,
            publicBuildingId: publicBuildingId ?? richer.publicBuildingId,
            canonicalBuildingId: canonicalBuildingId ?? richer.canonicalBuildingId,
            buildingIdentifierSource: buildingIdentifierSource ?? richer.buildingIdentifierSource,
            height: height,
            heightM: heightM ?? richer.heightM,
            minHeight: minHeight,
            isTownhome: isTownhome || richer.isTownhome,
            unitsCount: max(unitsCount, richer.unitsCount),
            addressText: addressText ?? richer.addressText,
            matchMethod: matchMethod ?? richer.matchMethod,
            featureStatus: featureStatus ?? richer.featureStatus,
            featureType: featureType ?? richer.featureType,
            status: status,
            scansToday: max(scansToday, richer.scansToday),
            scansTotal: max(scansTotal, richer.scansTotal),
            lastScanSecondsAgo: lastScanSecondsAgo ?? richer.lastScanSecondsAgo,
            houseNumber: houseNumber ?? richer.houseNumber,
            streetName: streetName ?? richer.streetName,
            confidence: confidence ?? richer.confidence,
            source: source ?? richer.source,
            addressCount: max(addressCount ?? 0, richer.addressCount ?? 0) > 0
                ? max(addressCount ?? 0, richer.addressCount ?? 0)
                : nil,
            areaSqm: areaSqm ?? richer.areaSqm,
            buildingType: buildingType ?? richer.buildingType,
            qrScanned: qrScanned ?? richer.qrScanned,
            isLinked: isLinked ?? richer.isLinked
        )
    }

    /// All known identifiers for matching a feature across Gold/Silver/Diamond responses.
    var buildingIdentifierCandidates: [String] {
        let rawValues = [publicBuildingId, canonicalBuildingId, buildingId, gersId, id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        return rawValues.filter { seen.insert($0.lowercased()).inserted }
    }
}

typealias BuildingFeature = MapFeatureGeoJSONFeature<BuildingProperties>
typealias BuildingFeatureCollection = MapFeatureGeoJSONFeatureCollection<BuildingProperties>

// MARK: - Campaign Address (persistent model)

public struct CampaignAddress: Identifiable, Equatable, Codable {
    public let id: UUID
    public let address: String
    public let coordinate: CLLocationCoordinate2D?
    public let buildingOutline: [[CLLocationCoordinate2D]]?

    public init(
        id: UUID = .init(),
        address: String,
        coordinate: CLLocationCoordinate2D? = nil,
        buildingOutline: [[CLLocationCoordinate2D]]? = nil
    ) {
        self.id = id
        self.address = address
        self.coordinate = coordinate
        self.buildingOutline = buildingOutline
    }

    public static func == (lhs: CampaignAddress, rhs: CampaignAddress) -> Bool {
        lhs.id == rhs.id
    }
}

extension CampaignAddress {
    var hasCoord: Bool { coordinate != nil }
    var lat: Double? { coordinate?.latitude }
    var lon: Double? { coordinate?.longitude }
    var houseNumber: String? { address.extractHouseNumber() }
}

// MARK: - Link types

/// Link between a building (from S3 GeoJSON) and an address (from Supabase)
struct BuildingAddressLink: Codable {
    let id: String
    let buildingId: String       // GERS ID
    let addressId: String        // UUID
    let matchType: String        // containment_verified, proximity_fallback, etc.
    let confidence: Double       // 0.0 - 1.0
    let isMultiUnit: Bool
    let unitCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case buildingId = "building_id"
        case addressId = "address_id"
        case matchType = "match_type"
        case confidence
        case isMultiUnit = "is_multi_unit"
        case unitCount = "unit_count"
    }
}

// MARK: - Building Stats (for real-time updates)

struct BuildingStats: Codable {
    let gersId: String
    let status: String           // not_visited, visited, hot
    let scansTotal: Int
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case status
        case scansTotal = "scans_total"
    }
}

// MARK: - Combined Model

struct BuildingWithAddress {
    let building: MapFeatureGeoJSONFeature<BuildingProperties>
    let link: BuildingAddressLink?
    let address: CampaignAddress?
    let stats: BuildingStats?
}

// MARK: - Building Unit (for townhouses)

struct BuildingUnit: Codable {
    let id: String
    let parentBuildingId: String
    let addressId: String
    let unitNumber: String
    let status: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case parentBuildingId = "parent_building_id"
        case addressId = "address_id"
        case unitNumber = "unit_number"
        case status
    }
}

// MARK: - Campaign Building Data

struct CampaignBuildingData {
    let buildings: [BuildingWithAddress]
    let links: [BuildingAddressLink]
    let addresses: [CampaignAddress]
    let stats: [String: BuildingStats]  // gers_id -> stats
}
