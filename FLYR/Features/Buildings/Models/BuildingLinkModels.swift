// MARK: - Building-Address Link Models
// These types extend the existing building/address models with link-specific data
// Single source of truth: BuildingProperties, CampaignAddress, BuildingFeature (here)

import Foundation
import CoreLocation

// MARK: - Building Properties (from map RPC / S3)

/// Building feature properties from Supabase RPC (Gold, Silver, address_point)
struct BuildingProperties: Codable {
    let id: String
    let buildingId: String?
    let addressId: String?
    let gersId: String?
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
    /// QR code was scanned
    let qrScanned: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case buildingId = "building_id"
        case addressId = "address_id"
        case gersId = "gers_id"
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
        case qrScanned = "qr_scanned"
    }

    init(
        id: String,
        buildingId: String?,
        addressId: String?,
        gersId: String?,
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
        qrScanned: Bool?
    ) {
        self.id = id
        self.buildingId = buildingId
        self.addressId = addressId
        self.gersId = gersId
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
        self.qrScanned = qrScanned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func decodeDouble(_ key: CodingKeys, default fallback: Double) -> Double {
            if let value = try? c.decode(Double.self, forKey: key) { return value }
            if let value = try? c.decode(Int.self, forKey: key) { return Double(value) }
            return fallback
        }

        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        buildingId = try? c.decodeIfPresent(String.self, forKey: .buildingId)
        addressId = try? c.decodeIfPresent(String.self, forKey: .addressId)
        gersId = try? c.decodeIfPresent(String.self, forKey: .gersId)
        height = decodeDouble(.height, default: 10)
        heightM = (try? c.decodeIfPresent(Double.self, forKey: .heightM)) ?? (try? c.decodeIfPresent(Int.self, forKey: .heightM)).map(Double.init)
        minHeight = decodeDouble(.minHeight, default: 0)
        isTownhome = (try? c.decodeIfPresent(Bool.self, forKey: .isTownhome)) ?? false
        unitsCount = (try? c.decodeIfPresent(Int.self, forKey: .unitsCount)) ?? 1
        addressText = try? c.decodeIfPresent(String.self, forKey: .addressText)
        matchMethod = try? c.decodeIfPresent(String.self, forKey: .matchMethod)
        featureStatus = try? c.decodeIfPresent(String.self, forKey: .featureStatus)
        featureType = try? c.decodeIfPresent(String.self, forKey: .featureType)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "not_visited"
        scansToday = (try? c.decodeIfPresent(Int.self, forKey: .scansToday)) ?? 0
        scansTotal = (try? c.decodeIfPresent(Int.self, forKey: .scansTotal)) ?? 0
        lastScanSecondsAgo = (try? c.decodeIfPresent(Double.self, forKey: .lastScanSecondsAgo)) ?? (try? c.decodeIfPresent(Int.self, forKey: .lastScanSecondsAgo)).map(Double.init)
        houseNumber = try? c.decodeIfPresent(String.self, forKey: .houseNumber)
        streetName = try? c.decodeIfPresent(String.self, forKey: .streetName)
        confidence = (try? c.decodeIfPresent(Double.self, forKey: .confidence)) ?? (try? c.decodeIfPresent(Int.self, forKey: .confidence)).map(Double.init)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        addressCount = try? c.decodeIfPresent(Int.self, forKey: .addressCount)
        qrScanned = try? c.decodeIfPresent(Bool.self, forKey: .qrScanned)
    }

    var statusColor: String {
        if scansTotal > 0 || (qrScanned ?? false) { return "#8b5cf6" }
        switch status {
        case "hot": return "#3b82f6"
        case "visited": return "#22c55e"
        default: return "#ef4444"
        }
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
