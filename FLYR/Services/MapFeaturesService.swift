import Foundation
import CoreLocation
import Combine
import Supabase

// MARK: - Map Feature GeoJSON Types (scoped to avoid conflict with Features/Buildings/Models/GeoJSON.swift)

/// Decodes Double or String (parsed to Double) for coordinates that sometimes come as strings.
struct LossyDouble: Codable, Sendable {
    let value: Double
    
    init(_ value: Double) { self.value = value }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            value = d
            return
        }
        if let s = try? container.decode(String.self), let d = Double(s) {
            value = d
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected Double or numeric String")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Recursive node for GeoJSON coordinates: number or array of nodes. Supports Point, LineString, Polygon, MultiPolygon, MultiLineString.
struct GeoJSONCoordinatesNode: Codable, Sendable {
    private let value: EitherNumberOrArray
    
    private enum EitherNumberOrArray: Sendable {
        case number(Double)
        case array([GeoJSONCoordinatesNode])
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = .number(0)
            return
        }
        if let d = try? container.decode(Double.self) {
            value = .number(d)
            return
        }
        if let s = try? container.decode(String.self), let d = Double(s) {
            value = .number(d)
            return
        }
        if let arr = try? container.decode([GeoJSONCoordinatesNode].self) {
            value = .array(arr)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "GeoJSON coordinates: expected number, numeric string, or array")
    }
    
    func encode(to encoder: Encoder) throws {
        switch value {
        case .number(let d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case .array(let a):
            var c = encoder.unkeyedContainer()
            for node in a { try c.encode(node) }
        }
    }
    
    private var asNumber: Double? {
        if case .number(let d) = value { return d }
        return nil
    }
    
    private var asArray: [GeoJSONCoordinatesNode]? {
        if case .array(let a) = value { return a }
        return nil
    }
    
    var asPoint: [Double]? {
        guard let arr = asArray else { return nil }
        let nums = arr.compactMap(\.asNumber)
        return nums.count == arr.count ? nums : nil
    }
    
    var asLineString: [[Double]]? {
        guard let arr = asArray else { return nil }
        let rings = arr.compactMap(\.asPoint)
        return rings.count == arr.count ? rings : nil
    }
    
    var asPolygon: [[[Double]]]? {
        guard let arr = asArray else { return nil }
        let rings = arr.compactMap(\.asLineString)
        return rings.count == arr.count ? rings : nil
    }
    
    var asMultiPolygon: [[[[Double]]]]? {
        guard let arr = asArray else { return nil }
        let polys = arr.compactMap(\.asPolygon)
        return polys.count == arr.count ? polys : nil
    }
    
    var asMultiLineString: [[[Double]]]? {
        guard let arr = asArray else { return nil }
        let lines = arr.compactMap(\.asLineString)
        return lines.count == arr.count ? lines : nil
    }
}

/// GeoJSON Geometry types for map feature RPCs
enum MapFeatureGeoJSONGeometryType: String, Codable {
    case point = "Point"
    case lineString = "LineString"
    case polygon = "Polygon"
    case multiPolygon = "MultiPolygon"
    case multiLineString = "MultiLineString"
}

/// GeoJSON Geometry for map feature RPCs (decodes Point, LineString, Polygon, MultiPolygon, MultiLineString).
struct MapFeatureGeoJSONGeometry: Codable {
    let type: String
    let coordinates: GeoJSONCoordinatesNode
    
    var asPoint: [Double]? { coordinates.asPoint }
    var asPolygon: [[[Double]]]? { coordinates.asPolygon }
    var asMultiPolygon: [[[[Double]]]]? { coordinates.asMultiPolygon }
    var asLineString: [[Double]]? { coordinates.asLineString }
    var asMultiLineString: [[[Double]]]? { coordinates.asMultiLineString }
}

/// GeoJSON Feature for map feature RPCs (generic properties)
struct MapFeatureGeoJSONFeature<P: Codable>: Codable {
    let type: String
    let id: String?
    let geometry: MapFeatureGeoJSONGeometry
    let properties: P

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case geometry
        case properties
    }

    init(
        type: String = "Feature",
        id: String? = nil,
        geometry: MapFeatureGeoJSONGeometry,
        properties: P
    ) {
        self.type = type
        self.id = id
        self.geometry = geometry
        self.properties = properties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Feature"
        id = Self.decodeFlexibleStringIfPresent(container, forKey: .id)
        geometry = try container.decode(MapFeatureGeoJSONGeometry.self, forKey: .geometry)
        properties = try container.decode(P.self, forKey: .properties)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(geometry, forKey: .geometry)
        try container.encode(properties, forKey: .properties)
    }

    private static func decodeFlexibleStringIfPresent(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key),
           doubleValue.isFinite {
            let rounded = doubleValue.rounded()
            if abs(doubleValue - rounded) < .ulpOfOne {
                return String(Int64(rounded))
            }
            return String(doubleValue)
        }
        return nil
    }
}

/// GeoJSON FeatureCollection for map feature RPCs
struct MapFeatureGeoJSONFeatureCollection<P: Codable>: Codable {
    let type: String
    var features: [MapFeatureGeoJSONFeature<P>]
}

// MARK: - Address Properties

/// Address feature properties
struct AddressProperties: Codable {
    let id: String?
    let gersId: String?
    let buildingGersId: String?
    let houseNumber: String?
    let streetName: String?
    let postalCode: String?
    let locality: String?
    let formatted: String?
    let source: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
        case buildingGersId = "building_gers_id"
        case houseNumber = "house_number"
        case streetName = "street_name"
        case postalCode = "postal_code"
        case locality
        case formatted
        case source
    }
}

// MARK: - Road Properties

/// Road feature properties
struct RoadProperties: Codable {
    let id: String?
    let gersId: String?
    let roadClass: String?
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
        case roadClass = "class"
        case name
    }
}

// MARK: - Type Aliases
// BuildingFeature / BuildingFeatureCollection live in BuildingLinkModels.swift

typealias AddressFeature = MapFeatureGeoJSONFeature<AddressProperties>
typealias AddressFeatureCollection = MapFeatureGeoJSONFeatureCollection<AddressProperties>

struct ParcelProperties: Codable {
    let id: String?
    let parcelId: String?
    let externalId: String?
    let addressId: String?
    let addressIds: [String]?
    let source: String?
    let areaSqm: Double?

    init(
        id: String?,
        parcelId: String?,
        externalId: String?,
        source: String?,
        areaSqm: Double?,
        addressId: String? = nil,
        addressIds: [String]? = nil
    ) {
        self.id = id
        self.parcelId = parcelId
        self.externalId = externalId
        self.addressId = addressId
        self.addressIds = addressIds
        self.source = source
        self.areaSqm = areaSqm
    }

    enum CodingKeys: String, CodingKey {
        case id
        case parcelId = "parcel_id"
        case externalId = "external_id"
        case addressId = "address_id"
        case addressIds = "address_ids"
        case source
        case areaSqm = "area_sqm"
    }
}

typealias ParcelFeature = MapFeatureGeoJSONFeature<ParcelProperties>
typealias ParcelFeatureCollection = MapFeatureGeoJSONFeatureCollection<ParcelProperties>

typealias RoadFeature = MapFeatureGeoJSONFeature<RoadProperties>
typealias RoadFeatureCollection = MapFeatureGeoJSONFeatureCollection<RoadProperties>

struct CampaignMapBundleCounts: Codable {
    let addresses: Int?
    let buildings: Int?
    let parcels: Int?
    let roads: Int?
}

struct CampaignMapBundle: Codable {
    let campaignId: String?
    let status: String?
    let phase: String?
    let source: String?
    let region: String?
    let mapReady: Bool?
    let addresses: AddressFeatureCollection
    let buildings: BuildingFeatureCollection
    let parcels: ParcelFeatureCollection
    let roads: RoadFeatureCollection
    let counts: CampaignMapBundleCounts?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case status
        case phase
        case source
        case region
        case mapReady = "map_ready"
        case addresses
        case buildings
        case parcels
        case roads
        case counts
        case updatedAt = "updated_at"
    }
}

struct ResolvedCampaignTarget {
    let id: String
    let label: String
    let coordinate: CLLocationCoordinate2D
    let addressId: String?
    let buildingId: String?
    let houseNumber: String?
    let streetName: String?
}

enum CampaignTargetResolver {
    static func preferredSessionTargets(
        buildings: [BuildingFeature],
        addresses: [AddressFeature]
    ) -> [ResolvedCampaignTarget] {
        let buildingTargets = buildingTargets(from: buildings)
        return buildingTargets.isEmpty ? addressTargets(from: addresses) : buildingTargets
    }

    /// Flyer sessions score proximity per address whenever address points exist.
    /// If address coverage is missing, supplement with single-address building centroids.
    static func flyerTargets(
        buildings: [BuildingFeature],
        addresses: [AddressFeature]
    ) -> [ResolvedCampaignTarget] {
        let addressTargets = addressTargets(from: addresses)
        guard !addressTargets.isEmpty else { return buildingTargets(from: buildings) }

        let coveredAddressIds = Set(addressTargets.compactMap { $0.addressId?.lowercased() })
        let coveredBuildingIds = Set(addressTargets.compactMap { $0.buildingId?.lowercased() })
        var seenTargetIds = Set(addressTargets.map { $0.id.lowercased() })

        let fallbackTargets = buildings.compactMap { feature -> ResolvedCampaignTarget? in
            let addressCount = max(feature.properties.addressCount ?? 0, feature.properties.unitsCount)
            guard addressCount <= 1,
                  let coordinate = coordinate(for: feature.geometry) else {
                return nil
            }

            let buildingId = normalizedSessionTargetId(
                feature.properties.canonicalBuildingIdentifier ?? feature.id
            )
            let addressId = normalizedUUIDString(feature.properties.addressId) ?? normalizedUUIDString(feature.id)

            if let addressId, coveredAddressIds.contains(addressId.lowercased()) {
                return nil
            }
            if let buildingId, coveredBuildingIds.contains(buildingId.lowercased()) {
                return nil
            }

            guard let targetId = addressId ?? buildingId,
                  seenTargetIds.insert(targetId.lowercased()).inserted else {
                return nil
            }

            return ResolvedCampaignTarget(
                id: targetId,
                label: displayAddressText(
                    formatted: feature.properties.addressText,
                    houseNumber: feature.properties.houseNumber,
                    streetName: feature.properties.streetName
                ) ?? "Building",
                coordinate: coordinate,
                addressId: addressId,
                buildingId: buildingId,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }

        return addressTargets + fallbackTargets
    }

    static func buildingTargets(from features: [BuildingFeature]) -> [ResolvedCampaignTarget] {
        var seen = Set<String>()

        return features.compactMap { feature in
            guard let rawId = normalizedSessionTargetId(
                feature.properties.canonicalBuildingIdentifier ?? feature.id
            ),
                  let coordinate = coordinate(for: feature.geometry),
                  seen.insert(rawId.lowercased()).inserted else {
                return nil
            }

            return ResolvedCampaignTarget(
                id: rawId,
                label: displayAddressText(
                    formatted: feature.properties.addressText,
                    houseNumber: feature.properties.houseNumber,
                    streetName: feature.properties.streetName
                ) ?? "Building",
                coordinate: coordinate,
                addressId: normalizedUUIDString(feature.properties.addressId) ?? normalizedUUIDString(feature.id),
                buildingId: rawId,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }
    }

    static func addressTargets(from features: [AddressFeature]) -> [ResolvedCampaignTarget] {
        var seen = Set<String>()

        return features.compactMap { feature in
            guard let rawId = normalizedUUIDString(feature.properties.id ?? feature.id),
                  let coordinate = coordinate(for: feature.geometry),
                  seen.insert(rawId.lowercased()).inserted else {
                return nil
            }

            return ResolvedCampaignTarget(
                id: rawId,
                label: displayAddressText(
                    formatted: feature.properties.formatted,
                    houseNumber: feature.properties.houseNumber,
                    streetName: feature.properties.streetName
                ) ?? "Address",
                coordinate: coordinate,
                addressId: rawId,
                buildingId: normalizedSessionTargetId(feature.properties.buildingGersId ?? feature.properties.gersId),
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }
    }

    static func coordinate(for geometry: MapFeatureGeoJSONGeometry) -> CLLocationCoordinate2D? {
        if let point = geometry.asPoint, point.count >= 2 {
            return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        }
        if let polygon = geometry.asPolygon {
            return centroidCoordinate(fromPolygonCoordinates: polygon)
        }
        if let multiPolygon = geometry.asMultiPolygon {
            let flattened = multiPolygon.flatMap { $0 }
            return centroidCoordinate(fromPolygonCoordinates: flattened)
        }
        return nil
    }

    static func displayAddressText(formatted: String?, houseNumber: String?, streetName: String?) -> String? {
        let formattedValue = formatted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !formattedValue.isEmpty {
            return formattedValue
        }
        let house = houseNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let street = streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(house) \(street)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    static func deduplicatedAddressFeaturesForClientDisplay(_ features: [AddressFeature]) -> [AddressFeature] {
        guard features.count > 1 else { return features }

        var orderedKeys: [String] = []
        var featuresByKey: [String: AddressFeature] = [:]

        for feature in features {
            let key = normalizedAddressFeatureIdentity(feature)
                ?? normalizedUUIDString(feature.properties.id ?? feature.id)
                ?? feature.id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                ?? UUID().uuidString

            guard let existing = featuresByKey[key] else {
                orderedKeys.append(key)
                featuresByKey[key] = feature
                continue
            }

            if addressFeatureDisplayPriority(feature) > addressFeatureDisplayPriority(existing) {
                featuresByKey[key] = feature
            }
        }

        return orderedKeys.compactMap { featuresByKey[$0] }
    }

    private static func centroidCoordinate(fromPolygonCoordinates polygon: [[[Double]]]) -> CLLocationCoordinate2D? {
        var sumLat = 0.0
        var sumLon = 0.0
        var count = 0

        for ring in polygon {
            for point in ring where point.count >= 2 {
                sumLon += point[0]
                sumLat += point[1]
                count += 1
            }
        }

        guard count > 0 else { return nil }
        return CLLocationCoordinate2D(
            latitude: sumLat / Double(count),
            longitude: sumLon / Double(count)
        )
    }

    private static func normalizedSessionTargetId(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedUUIDString(_ rawValue: String?) -> String? {
        guard let id = normalizedSessionTargetId(rawValue),
              let uuid = UUID(uuidString: id) else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

    private static func normalizedAddressFeatureIdentity(_ feature: AddressFeature) -> String? {
        let house = normalizedAddressPart(feature.properties.houseNumber)
        let street = normalizedStreetIdentityPart(feature.properties.streetName)
        let locality = normalizedAddressPart(feature.properties.locality)
        let postalCode = normalizedAddressPart(feature.properties.postalCode)

        if !house.isEmpty || !street.isEmpty {
            let identity = [house, street, locality, postalCode]
                .filter { !$0.isEmpty }
                .joined(separator: "|")
            return identity.isEmpty ? nil : identity
        }

        let formatted = normalizedAddressPart(feature.properties.formatted)
        guard !formatted.isEmpty else { return nil }

        let identity = [formatted, locality, postalCode]
            .filter { !$0.isEmpty }
            .joined(separator: "|")
        return identity.isEmpty ? nil : identity
    }

    private static func normalizedAddressPart(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedStreetIdentityPart(_ value: String?) -> String {
        normalizedAddressPart(value)
            .split(separator: " ")
            .map { word -> String in
                switch word {
                case "st", "str": return "street"
                case "rd": return "road"
                case "ave", "av": return "avenue"
                case "blvd": return "boulevard"
                case "dr": return "drive"
                case "ct", "crt": return "court"
                case "cres": return "crescent"
                case "ln": return "lane"
                case "pl": return "place"
                case "trl": return "trail"
                case "pkwy": return "parkway"
                case "hwy": return "highway"
                default: return String(word)
                }
            }
            .joined(separator: " ")
    }

    private static func addressFeatureDisplayPriority(_ feature: AddressFeature) -> Int {
        var score = 0
        if feature.properties.buildingGersId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 4 }
        if feature.properties.gersId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 2 }
        if feature.properties.formatted?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { score += 1 }
        if CampaignTargetResolver.coordinate(for: feature.geometry) != nil { score += 1 }
        return score
    }
}

// MARK: - FeatureCollection Decode Helper (array vs object)

/// Decode GeoJSON FeatureCollection from RPC response that may be object or array.
private func decodeFeatureCollection<F: Codable>(_ data: Data) throws -> MapFeatureGeoJSONFeatureCollection<F> {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let first = data.first(where: { $0 != 32 && $0 != 10 && $0 != 9 && $0 != 13 })
    if first == 91 { // [
        let features = try decoder.decode([MapFeatureGeoJSONFeature<F>].self, from: data)
        return MapFeatureGeoJSONFeatureCollection(type: "FeatureCollection", features: features)
    } else {
        return try decoder.decode(MapFeatureGeoJSONFeatureCollection<F>.self, from: data)
    }
}

private func campaignApiBaseURL() -> URL {
    Config.backendAPIURL
}

private func fetchCampaignAddressGeoJSONFromAPI(campaignId: UUID) async throws -> AddressFeatureCollection {
    let url = campaignApiBaseURL()
        .appendingPathComponent("api")
        .appendingPathComponent("campaigns")
        .appendingPathComponent(campaignId.uuidString)
        .appendingPathComponent("addresses")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let session = try? await SupabaseManager.shared.client.auth.session {
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
        throw NSError(domain: "MapFeatures", code: -1, userInfo: [NSLocalizedDescriptionKey: "Address GeoJSON request failed"])
    }

    return try decodeFeatureCollection(data)
}

// MARK: - Map Features Service

/// Service for fetching map features (buildings, addresses, roads) from Supabase
@MainActor
final class MapFeaturesService: ObservableObject {
    static let shared = MapFeaturesService()
    private static let minimumRenderableBuildingAreaSqm = 30.0
    
    private let supabase = SupabaseClientShim()
    
    @Published var buildings: BuildingFeatureCollection?
    @Published var addresses: AddressFeatureCollection?
    @Published var parcels: ParcelFeatureCollection?
    @Published var roads: RoadFeatureCollection?
    @Published var diamondManifest: DiamondManifest?
    @Published var displayModeHint: String?
    @Published var isLoading = false
    @Published var clientLinkingProgress: ClientLinkingProgress = .idle
    @Published var error: Error?

    // Campaign-scoped prewarmed building polygons (e.g. Quick Start ensure response before DB links are ready).
    private var prewarmedBuildingsByCampaign: [String: BuildingFeatureCollection] = [:]
    // Campaign-scoped Diamond manifests already proven ready by the creation flow.
    private var prewarmedDiamondManifestsByCampaign: [String: DiamondManifest] = [:]
    private var diamondManifestPrewarmTasks: [String: Task<Void, Never>] = [:]
    private let diamondPMTilesRenderingEnabled = false
    private var unsupportedDiamondManifestCampaigns: Set<String> = []
    private var parcelRetryTask: Task<Void, Never>?
    private var canonicalBundleRefreshTask: Task<Bool, Never>?
    private var canonicalBundleRefreshCampaignIdLower: String?
    private var canonicalBundleRefreshSignature: String?
    private var clientLinkingTask: Task<Void, Never>?
    private var clientLinkingSignature: String?
    private var canonicalBundleRefreshResultByCampaign: [String: String] = [:]
    private var currentCanonicalBundleLinksStatus: String?
    /// Tracks latest campaign fetch so stale async responses are ignored.
    private var activeCampaignRequestId: UUID?
    private var activeCampaignIdLower: String?
    private struct CampaignFeatureSnapshot {
        var buildings: BuildingFeatureCollection? = nil
        var addresses: AddressFeatureCollection? = nil
        var parcels: ParcelFeatureCollection? = nil
        var roads: RoadFeatureCollection? = nil
        var diamondManifest: DiamondManifest? = nil
        var displayModeHint: String? = nil
    }
    private var featureSnapshotsByCampaign: [String: CampaignFeatureSnapshot] = [:]
    private let campaignRepository = CampaignRepository.shared
    
    private init() {}

    func hasUsableCampaignData(campaignId: String) -> Bool {
        guard activeCampaignIdLower == campaignId.lowercased() else { return false }
        return !(buildings?.features.isEmpty ?? true) || !(addresses?.features.isEmpty ?? true)
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func isActiveCampaignRequest(campaignId: String, requestId: UUID?) -> Bool {
        guard let requestId else { return activeCampaignIdLower == campaignId.lowercased() }
        return activeCampaignRequestId == requestId && activeCampaignIdLower == campaignId.lowercased()
    }

    func isScopedToCampaign(_ campaignId: String) -> Bool {
        activeCampaignIdLower == campaignId.lowercased()
    }

    func buildings(for campaignId: String) -> BuildingFeatureCollection? {
        if isScopedToCampaign(campaignId) { return buildings }
        return featureSnapshotsByCampaign[campaignId.lowercased()]?.buildings
    }

    func addresses(for campaignId: String) -> AddressFeatureCollection? {
        if isScopedToCampaign(campaignId) { return addresses }
        return featureSnapshotsByCampaign[campaignId.lowercased()]?.addresses
    }

    func parcels(for campaignId: String) -> ParcelFeatureCollection? {
        if isScopedToCampaign(campaignId) { return parcels }
        return featureSnapshotsByCampaign[campaignId.lowercased()]?.parcels
    }

    func roads(for campaignId: String) -> RoadFeatureCollection? {
        if isScopedToCampaign(campaignId) { return roads }
        return featureSnapshotsByCampaign[campaignId.lowercased()]?.roads
    }

    func diamondManifest(for campaignId: String) -> DiamondManifest? {
        if isScopedToCampaign(campaignId) { return diamondManifest }
        return featureSnapshotsByCampaign[campaignId.lowercased()]?.diamondManifest
    }

    func displayModeHint(for campaignId: String) -> String? {
        if isScopedToCampaign(campaignId) { return displayModeHint }
        return featureSnapshotsByCampaign[campaignId.lowercased()]?.displayModeHint
    }

    private func updateFeatureSnapshot(
        campaignId: String,
        notifyInactiveObservers: Bool = false,
        _ update: (inout CampaignFeatureSnapshot) -> Void
    ) {
        let campaignKey = campaignId.lowercased()
        var snapshot = featureSnapshotsByCampaign[campaignKey] ?? CampaignFeatureSnapshot()
        update(&snapshot)
        featureSnapshotsByCampaign[campaignKey] = snapshot
        if notifyInactiveObservers && !isScopedToCampaign(campaignId) {
            objectWillChange.send()
        }
    }

    private func storeCurrentFeatureSnapshot(campaignId: String) {
        updateFeatureSnapshot(campaignId: campaignId) { snapshot in
            snapshot.buildings = buildings
            snapshot.addresses = addresses
            snapshot.parcels = parcels
            snapshot.roads = roads
            snapshot.diamondManifest = diamondManifest
            snapshot.displayModeHint = displayModeHint
        }
    }

    private func seedCurrentFeaturesFromSnapshot(campaignId: String) {
        let snapshot = featureSnapshotsByCampaign[campaignId.lowercased()]
        self.buildings = snapshot?.buildings ?? BuildingFeatureCollection(type: "FeatureCollection", features: [])
        self.addresses = snapshot?.addresses ?? AddressFeatureCollection(type: "FeatureCollection", features: [])
        self.parcels = snapshot?.parcels ?? ParcelFeatureCollection(type: "FeatureCollection", features: [])
        self.roads = snapshot?.roads ?? RoadFeatureCollection(type: "FeatureCollection", features: [])
        self.diamondManifest = snapshot?.diamondManifest
        self.displayModeHint = snapshot?.displayModeHint
    }

    func primeBuildingPolygons(campaignId: String, features: [GeoJSONFeature]) {
        let collection = filteredRenderableBuildingCollection(
            buildingFeatureCollectionFromGeoJSON(GeoJSONFeatureCollection(features: features))
        )
        guard !collection.features.isEmpty else { return }
        prewarmedBuildingsByCampaign[campaignId.lowercased()] = collection
        updateFeatureSnapshot(campaignId: campaignId, notifyInactiveObservers: true) { snapshot in
            snapshot.buildings = collection
        }
        if isScopedToCampaign(campaignId) {
            self.buildings = collection
            storeCurrentFeatureSnapshot(campaignId: campaignId)
        }
        print("✅ [MapFeatures] Primed \(collection.features.count) prewarmed building polygons for campaign \(campaignId)")
    }

    func primeBuildingFeatures(campaignId: String, features: [BuildingFeature]) {
        let collection = filteredRenderableBuildingCollection(
            BuildingFeatureCollection(type: "FeatureCollection", features: features)
        )
        guard !collection.features.isEmpty else { return }
        prewarmedBuildingsByCampaign[campaignId.lowercased()] = collection
        updateFeatureSnapshot(campaignId: campaignId, notifyInactiveObservers: true) { snapshot in
            snapshot.buildings = collection
        }
        if isScopedToCampaign(campaignId) {
            self.buildings = collection
            storeCurrentFeatureSnapshot(campaignId: campaignId)
        }
        print("✅ [MapFeatures] Primed \(collection.features.count) prewarmed building features for campaign \(campaignId)")
    }

    func primeDiamondManifest(campaignId: String, manifest: DiamondManifest) {
        let campaignKey = campaignId.lowercased()
        guard diamondPMTilesRenderingEnabled else {
            print("💎 [DIAMOND] Ignoring PMTiles manifest for campaign \(campaignId); GeoJSON renderer is enabled")
            return
        }
        guard !unsupportedDiamondManifestCampaigns.contains(campaignKey) else {
            print("💎 [DIAMOND] Ignoring PMTiles manifest for campaign \(campaignId); GeoJSON fallback is locked for this session")
            return
        }
        guard manifest.hasRenderablePMTilesGeometry || manifest.hasRenderablePMTilesAddresses || manifest.hasRenderablePMTilesParcels else { return }

        prewarmedDiamondManifestsByCampaign[campaignKey] = manifest

        if isScopedToCampaign(campaignId) {
            self.diamondManifest = manifest
            if manifest.hasRenderablePMTilesGeometry {
                self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
            }
            storeCurrentFeatureSnapshot(campaignId: campaignId)
        } else {
            updateFeatureSnapshot(campaignId: campaignId, notifyInactiveObservers: true) { snapshot in
                snapshot.diamondManifest = manifest
                if manifest.hasRenderablePMTilesGeometry {
                    snapshot.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
                }
            }
        }

        print("💎 [DIAMOND] Primed ready PMTiles manifest for campaign \(campaignId)")
    }

    func beginDiamondManifestPrewarm(campaignId: String, timeoutSeconds: TimeInterval = 90) {
        let campaignKey = campaignId.lowercased()
        guard diamondPMTilesRenderingEnabled else { return }
        guard !unsupportedDiamondManifestCampaigns.contains(campaignKey) else { return }
        guard diamondManifestPrewarmTasks[campaignKey] == nil,
              let campaignUUID = UUID(uuidString: campaignId) else {
            return
        }

        diamondManifestPrewarmTasks[campaignKey] = Task { [weak self] in
            do {
                let manifest = try await DiamondManifestAPI.shared.waitForReadyManifest(
                    campaignId: campaignUUID,
                    timeoutSeconds: timeoutSeconds,
                    pollIntervalSeconds: 2
                )
                guard !Task.isCancelled else { return }
                self?.finishDiamondManifestPrewarm(campaignId: campaignId, manifest: manifest)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishDiamondManifestPrewarm(campaignId: campaignId, manifest: nil)
                print("💎 [DIAMOND] Background manifest prewarm ended without ready geometry: \(error.localizedDescription)")
            }
        }
    }

    private func finishDiamondManifestPrewarm(campaignId: String, manifest: DiamondManifest?) {
        diamondManifestPrewarmTasks[campaignId.lowercased()] = nil
        guard let manifest else { return }
        primeDiamondManifest(campaignId: campaignId, manifest: manifest)
    }

    func markDiamondManifestUnsupported(campaignId: String, reason: String) {
        let campaignKey = campaignId.lowercased()
        unsupportedDiamondManifestCampaigns.insert(campaignKey)
        prewarmedDiamondManifestsByCampaign.removeValue(forKey: campaignKey)
        diamondManifestPrewarmTasks[campaignKey]?.cancel()
        diamondManifestPrewarmTasks[campaignKey] = nil

        if isScopedToCampaign(campaignId) {
            diamondManifest = nil
        }

        print("💎 [DIAMOND] Disabled PMTiles manifest for campaign \(campaignId); falling back to GeoJSON (\(reason))")
    }
    
    // MARK: - Campaign Full Features (Fetch Once, Render Forever)
    
    /// Fetch ALL features for a campaign without viewport filtering
    /// This enables buttery smooth pan/zoom without re-fetching
    func fetchCampaignFullFeatures(campaignId: String) async {
        isLoading = true
        error = nil
        
        do {
            print("🗺️ [MapFeatures] Fetching full campaign features for: \(campaignId)")
            
            // Defensive: Validate campaign ID format
            guard let campaignUUID = UUID(uuidString: campaignId) else {
                print("❌ [MapFeatures] Invalid campaign ID format: \(campaignId)")
                self.error = NSError(domain: "MapFeatures", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid campaign ID format"])
                isLoading = false
                return
            }
            
            let data = try await supabase.callRPCData(
                "rpc_get_campaign_full_features",
                params: ["p_campaign_id": campaignUUID.uuidString]
            )
            
            // Defensive: Check if data is empty
            if data.isEmpty {
                print("⚠️ [MapFeatures] Empty response from RPC")
                self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
                isLoading = false
                return
            }
            
            // Log raw response for debugging (first 500 chars)
            if let responseText = String(data: data, encoding: .utf8) {
                print("🔍 [MapFeatures] RPC response: \(responseText.prefix(500))")
            }
            
            let result: BuildingFeatureCollection = try decodeFeatureCollection(data)
            let filtered = filteredRenderableBuildingCollection(result)
            self.buildings = filtered
            print("✅ [MapFeatures] Loaded \(filtered.features.count) building features")
            
        } catch let decodingError as DecodingError {
            self.error = decodingError
            print("❌ [MapFeatures] Decoding error: \(decodingError)")
            // Set empty collection instead of failing completely
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
            
        } catch {
            self.error = error
            print("❌ [MapFeatures] Error fetching campaign features: \(error)")
            // Set empty collection instead of failing completely
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
        }
        
        isLoading = false
    }
    
    // MARK: - Viewport-Based Queries (Exploration Mode)
    
    /// Fetch buildings in a bounding box (for exploration mode without campaign)
    func fetchBuildingsInBbox(
        minLon: Double,
        minLat: Double,
        maxLon: Double,
        maxLat: Double,
        campaignId: String? = nil
    ) async {
        isLoading = true
        error = nil
        
        do {
            var params: [String: Any] = [
                "min_lon": minLon,
                "min_lat": minLat,
                "max_lon": maxLon,
                "max_lat": maxLat
            ]
            
            if let campaignId = campaignId, let campaignUUID = UUID(uuidString: campaignId) {
                params["p_campaign_id"] = campaignUUID.uuidString
            }
            
            print("🗺️ [MapFeatures] Fetching buildings in bbox: [\(minLon), \(minLat), \(maxLon), \(maxLat)]")
            
            let result: BuildingFeatureCollection = try await supabase.callRPC(
                "rpc_get_buildings_in_bbox",
                params: params
            )
            
            let filtered = filteredRenderableBuildingCollection(result)
            self.buildings = filtered
            print("✅ [MapFeatures] Loaded \(filtered.features.count) buildings in viewport")
            
        } catch {
            self.error = error
            print("❌ [MapFeatures] Error fetching buildings: \(error)")
        }
        
        isLoading = false
    }
    
    /// Fetch addresses in a bounding box
    func fetchAddressesInBbox(
        minLon: Double,
        minLat: Double,
        maxLon: Double,
        maxLat: Double,
        campaignId: String? = nil
    ) async {
        do {
            var params: [String: Any] = [
                "min_lon": minLon,
                "min_lat": minLat,
                "max_lon": maxLon,
                "max_lat": maxLat
            ]
            
            if let campaignId = campaignId, let campaignUUID = UUID(uuidString: campaignId) {
                params["p_campaign_id"] = campaignUUID.uuidString
            }
            
            print("🗺️ [MapFeatures] Fetching addresses in bbox")
            
            let result: AddressFeatureCollection = try await supabase.callRPC(
                "rpc_get_addresses_in_bbox",
                params: params
            )
            
            self.addresses = result
            print("✅ [MapFeatures] Loaded \(result.features.count) addresses")
            
        } catch {
            print("❌ [MapFeatures] Error fetching addresses: \(error)")
        }
    }
    
    // MARK: - Campaign All Features (Buildings + Addresses + Roads)
    
    /// Fetch all map features for a campaign (buildings, addresses, roads).
    ///
    /// Building source priority (handled server-side by /api/campaigns/{id}/buildings):
    ///   1. Gold, if any Gold buildings exist
    ///   2. Silver, only when no Gold buildings exist
    ///
    /// Addresses come from the backend map address endpoint, which returns DB/RPC rows first
    /// and falls back to the Silver snapshot for non-Gold campaigns with no DB rows.
    func fetchAllCampaignFeatures(campaignId: String, forceRefresh: Bool = false) async {
        let debugLoadStartedAt = Date()
        let trace = PerfTrace.begin("campaign_open", "fetch_all_campaign_features", fields: [
            "campaign": campaignId,
            "forceRefresh": forceRefresh
        ])
        let campaignIdLower = campaignId.lowercased()
        if isLoading, activeCampaignIdLower == campaignIdLower, !forceRefresh {
            print("ℹ️ [MapFeatures] Campaign \(campaignId) load already in flight; coalescing duplicate request")
            print("🧪 [MAP_DEBUG] campaign_load_coalesced campaign=\(campaignId)")
            trace.end(status: "coalesced")
            return
        }
        if isLoading, activeCampaignIdLower == campaignIdLower, forceRefresh {
            print("🧪 [MAP_DEBUG] campaign_load_superseded campaign=\(campaignId) reason=force_refresh")
        }

        let isRefreshingSameCampaign = activeCampaignIdLower == campaignIdLower
        let requestId = UUID()
        activeCampaignRequestId = requestId
        activeCampaignIdLower = campaignIdLower
        parcelRetryTask?.cancel()
        parcelRetryTask = nil
        if !isRefreshingSameCampaign || forceRefresh {
            canonicalBundleRefreshTask?.cancel()
            canonicalBundleRefreshTask = nil
            canonicalBundleRefreshCampaignIdLower = nil
            canonicalBundleRefreshSignature = nil
        }
        currentCanonicalBundleLinksStatus = nil
        clientLinkingProgress = .idle
        isLoading = true
        error = nil
        print("🧪 [MAP_DEBUG] campaign_load_start campaign=\(campaignId) refreshingSameCampaign=\(isRefreshingSameCampaign)")

        // Keep existing features visible when reloading the same campaign (for example after adding
        // a manual home) so the map never collapses to empty while refresh requests are in flight.
        // We still clear immediately when switching to a different campaign.
        if !isRefreshingSameCampaign {
            seedCurrentFeaturesFromSnapshot(campaignId: campaignId)
        }

        var loadedCachedFirstDrawBundle = false
        var cachedBundleHasBuildings = false
        var cachedBundleHasAddresses = false
        var cachedBundleNeedsLinkRefresh = false
        var cachedBundleIsFresh = false
        var cachedBundleRequiresClientFallback = false
        var cachedBundleMetadata: CachedCampaignMapBundleMetadata?

        if let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
           isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) {
            self.buildings = filteredRenderableBuildingCollection(cachedBundle.buildings)
            self.addresses = cachedBundle.addresses
            self.parcels = cachedBundle.parcels
            self.roads = cachedBundle.roads
            self.displayModeHint = cachedBundle.metadata?.displayModeHint
            self.currentCanonicalBundleLinksStatus = cachedBundle.metadata?.linksStatus
            cachedBundleMetadata = cachedBundle.metadata
            loadedCachedFirstDrawBundle = true
            cachedBundleIsFresh = cachedBundle.metadata?.isFresh == true
            cachedBundleRequiresClientFallback = cachedBundle.metadata?.requiresClientFallback == true
            cachedBundleHasBuildings = !(self.buildings?.features.isEmpty ?? true)
            cachedBundleHasAddresses = !cachedBundle.addresses.features.isEmpty
            cachedBundleNeedsLinkRefresh = cachedBundleHasBuildings
                && cachedBundleHasAddresses
                && !Self.hasLinkedAddressIdentity(
                    buildings: self.buildings,
                    addresses: cachedBundle.addresses
                )
                && (cachedBundle.metadata == nil || cachedBundleRequiresClientFallback)
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            isLoading = false
            print(
                "🧪 [MAP_DEBUG] cache_bundle_loaded campaign=\(campaignId) " +
                "buildingsGeoJSON=\(self.buildings?.features.count ?? 0) addressesGeoJSON=\(self.addresses?.features.count ?? 0) " +
                "parcelsGeoJSON=\(self.parcels?.features.count ?? 0) roads=\(self.roads?.features.count ?? 0) " +
                "fresh=\(cachedBundleIsFresh) linksStatus=\(cachedBundle.metadata?.linksStatus ?? "unknown")"
            )
            if cachedBundleNeedsLinkRefresh {
                print("🧪 [MAP_DEBUG] cache_bundle_link_identity_missing campaign=\(campaignId) action=refresh_canonical_bundle")
            }
            if cachedBundleNeedsLinkRefresh {
                scheduleClientLinkingIfReady(campaignId: campaignId, requestId: requestId)
            }
            PerfTrace.event("campaign_open", "local_bundle_first_draw", fields: [
                "campaign": campaignId,
                "buildings": self.buildings?.features.count ?? 0,
                "addresses": self.addresses?.features.count ?? 0,
                "parcels": self.parcels?.features.count ?? 0,
                "roads": self.roads?.features.count ?? 0,
                "fresh": cachedBundleIsFresh,
                "linksStatus": cachedBundle.metadata?.linksStatus ?? "unknown",
                "needsLinkRefresh": cachedBundleNeedsLinkRefresh
            ])
        } else {
            self.roads = RoadFeatureCollection(type: "FeatureCollection", features: [])
        }

        guard NetworkMonitor.shared.isOnline else {
            if (buildings?.features.isEmpty ?? true) && (addresses?.features.isEmpty ?? true) {
                self.error = NSError(
                    domain: "MapFeatures",
                    code: -1009,
                    userInfo: [NSLocalizedDescriptionKey: "Campaign data is not cached on this device yet."]
                )
            } else {
                print(
                    "📴 [MapFeatures] Offline campaign load using cached GeoJSON " +
                    "buildings=\(self.buildings?.features.count ?? 0) addresses=\(self.addresses?.features.count ?? 0)"
                )
            }
            isLoading = false
            trace.end(status: loadedCachedFirstDrawBundle ? "offline_cached" : "offline_no_cache", fields: [
                "buildings": self.buildings?.features.count ?? 0,
                "addresses": self.addresses?.features.count ?? 0
            ])
            return
        }

        if self.buildings?.features.isEmpty ?? true {
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
        }

        let cachedBundleLinksFresh = Self.canonicalLinksAreFresh(cachedBundleMetadata?.linksStatus)
        let cachedBundleCanSkipLegacyGeoJSON = loadedCachedFirstDrawBundle
            && cachedBundleIsFresh
            && cachedBundleLinksFresh
            && cachedBundleHasBuildings
            && cachedBundleHasAddresses
            && !cachedBundleRequiresClientFallback
            && !cachedBundleNeedsLinkRefresh

        if cachedBundleCanSkipLegacyGeoJSON,
           let metadata = cachedBundleMetadata {
            print(
                "🧪 [MAP_DEBUG] cache_bundle_first_draw_ready campaign=\(campaignId) " +
                "buildingsGeoJSON=\(self.buildings?.features.count ?? 0) addressesGeoJSON=\(self.addresses?.features.count ?? 0) " +
                "parcelsGeoJSON=\(self.parcels?.features.count ?? 0) linksStatus=\(metadata.linksStatus ?? "unknown")"
            )
            print("🧪 [MAP_DEBUG] buildings_geojson_skipped campaign=\(campaignId) reason=cached_bundle_first_draw")
            print("🧪 [MAP_DEBUG] addresses_geojson_skipped campaign=\(campaignId) reason=cached_bundle_first_draw")
            print("🧪 [MAP_DEBUG] parcels_geojson_skipped campaign=\(campaignId) reason=cached_bundle_first_draw")
            isLoading = false
            print(
                "🧪 [MAP_DEBUG] cache_bundle_first_draw_refreshing campaign=\(campaignId) " +
                "action=refresh_canonical_bundle_background"
            )
            startCanonicalMapBundleRefresh(
                campaignId: campaignId,
                requestId: requestId,
                localSignature: forceRefresh ? nil : metadata.assetSignature
            )
            let debugTotalMilliseconds = Int(Date().timeIntervalSince(debugLoadStartedAt) * 1000)
            print(
                "🧪 [MAP_DEBUG] campaign_hydration_done campaign=\(campaignId) totalMs=\(debugTotalMilliseconds) " +
                "renderer=local_canonical_cache buildingsGeoJSON=\(self.buildings?.features.count ?? 0) " +
                "addressesGeoJSON=\(self.addresses?.features.count ?? 0) parcelsGeoJSON=\(self.parcels?.features.count ?? 0) roads=\(self.roads?.features.count ?? 0)"
            )
            trace.end(status: "local_cache_background_refresh", fields: [
                "renderer": "local_canonical_cache",
                "buildings": self.buildings?.features.count ?? 0,
                "addresses": self.addresses?.features.count ?? 0,
                "parcels": self.parcels?.features.count ?? 0,
                "roads": self.roads?.features.count ?? 0
            ])
            return
        }

        let shouldFetchCanonicalBundle = forceRefresh
            || !loadedCachedFirstDrawBundle
            || !cachedBundleIsFresh
            || !cachedBundleLinksFresh
            || cachedBundleRequiresClientFallback
            || cachedBundleNeedsLinkRefresh
            || !cachedBundleHasBuildings
            || !cachedBundleHasAddresses

        if shouldFetchCanonicalBundle {
            let refreshReason: String
            if forceRefresh {
                refreshReason = "force_refresh"
            } else if !loadedCachedFirstDrawBundle {
                refreshReason = "missing_local_bundle"
            } else if !cachedBundleIsFresh {
                refreshReason = "stale_local_bundle"
            } else if cachedBundleRequiresClientFallback {
                refreshReason = "client_fallback_required"
            } else {
                refreshReason = "partial_local_bundle"
            }
            print(
                "🧪 [MAP_DEBUG] canonical_map_bundle_foreground_start campaign=\(campaignId) " +
                "reason=\(refreshReason)"
            )
            let canonicalLoaded = await fetchCanonicalCampaignMapBundle(
                campaignId: campaignId,
                requestId: requestId,
                localSignature: nil,
                startedAt: debugLoadStartedAt,
                timeoutNanoseconds: nil
            )
            if canonicalLoaded {
                isLoading = false
                let debugTotalMilliseconds = Int(Date().timeIntervalSince(debugLoadStartedAt) * 1000)
                print(
                    "🧪 [MAP_DEBUG] campaign_hydration_done campaign=\(campaignId) totalMs=\(debugTotalMilliseconds) " +
                    "renderer=canonical_bundle buildingsGeoJSON=\(self.buildings?.features.count ?? 0) " +
                    "addressesGeoJSON=\(self.addresses?.features.count ?? 0) parcelsGeoJSON=\(self.parcels?.features.count ?? 0) roads=\(self.roads?.features.count ?? 0)"
                )
                trace.end(status: "foreground_canonical_bundle", fields: [
                    "renderer": "canonical_bundle",
                    "buildings": self.buildings?.features.count ?? 0,
                    "addresses": self.addresses?.features.count ?? 0,
                    "parcels": self.parcels?.features.count ?? 0,
                    "roads": self.roads?.features.count ?? 0
                ])
                return
            }

            if !loadedCachedFirstDrawBundle {
                self.error = NSError(
                    domain: "MapFeatures",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Campaign map bundle could not be loaded."]
                )
            } else {
                print(
                    "🧪 [MAP_DEBUG] canonical_map_bundle_only_using_cached campaign=\(campaignId) " +
                    "reason=\(refreshReason)"
                )
            }
        }

        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
        
        isLoading = false
        let debugTotalMilliseconds = Int(Date().timeIntervalSince(debugLoadStartedAt) * 1000)
        let renderer = loadedCachedFirstDrawBundle ? "local_canonical_cache" : "canonical_bundle_unavailable"
        print(
            "🧪 [MAP_DEBUG] campaign_hydration_done campaign=\(campaignId) totalMs=\(debugTotalMilliseconds) " +
            "renderer=\(renderer) buildingsGeoJSON=\(self.buildings?.features.count ?? 0) " +
            "addressesGeoJSON=\(self.addresses?.features.count ?? 0) parcelsGeoJSON=\(self.parcels?.features.count ?? 0) roads=\(self.roads?.features.count ?? 0)"
        )
        trace.end(status: renderer, fields: [
            "buildings": self.buildings?.features.count ?? 0,
            "addresses": self.addresses?.features.count ?? 0,
            "parcels": self.parcels?.features.count ?? 0,
            "roads": self.roads?.features.count ?? 0
        ])
        storeCurrentFeatureSnapshot(campaignId: campaignId)
    }

    private enum CanonicalBundleTimedResult: Sendable {
        case fetched(CampaignMapBundleFetchResult)
        case failed(String)
        case timedOut
    }

    @discardableResult
    private func startCanonicalMapBundleRefresh(
        campaignId: String,
        requestId: UUID,
        localSignature: String?
    ) -> Bool {
        let campaignIdLower = campaignId.lowercased()
        let signatureKey = localSignature ?? "full"
        if canonicalBundleRefreshTask != nil,
           canonicalBundleRefreshCampaignIdLower == campaignIdLower,
           canonicalBundleRefreshSignature == signatureKey {
            print(
                "🧪 [MAP_DEBUG] canonical_map_bundle_reused campaign=\(campaignId) " +
                "signature=\(localSignature ?? "none")"
            )
            return true
        }
        canonicalBundleRefreshTask?.cancel()
        canonicalBundleRefreshCampaignIdLower = campaignIdLower
        canonicalBundleRefreshSignature = signatureKey
        canonicalBundleRefreshTask = Task { [weak self] in
            guard let self else { return false }
            let loaded = await self.fetchCanonicalCampaignMapBundle(
                campaignId: campaignId,
                requestId: nil,
                localSignature: localSignature,
                startedAt: Date(),
                timeoutNanoseconds: nil
            )
            if self.canonicalBundleRefreshCampaignIdLower == campaignIdLower,
               self.canonicalBundleRefreshSignature == signatureKey {
                self.canonicalBundleRefreshTask = nil
                self.canonicalBundleRefreshCampaignIdLower = nil
                self.canonicalBundleRefreshSignature = nil
            }
            return loaded
        }
        _ = requestId
        return true
    }

    @discardableResult
    private func fetchCanonicalCampaignMapBundle(
        campaignId: String,
        requestId: UUID?,
        localSignature: String?,
        startedAt debugStartedAt: Date,
        timeoutNanoseconds: UInt64?
    ) async -> Bool {
        if let timeoutNanoseconds {
            return await withTaskGroup(of: CanonicalBundleTimedResult.self) { group in
                group.addTask {
                    guard NetworkMonitor.shared.isOnline else {
                        return .failed("offline")
                    }

                    do {
                        let result = try await BuildingLinkService.shared.fetchCanonicalCampaignMapBundle(
                            campaignId: campaignId,
                            localSignature: localSignature
                        )
                        return .fetched(result)
                    } catch {
                        return .failed(error.localizedDescription)
                    }
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return .timedOut
                }

                guard let first = await group.next() else {
                    group.cancelAll()
                    return false
                }
                group.cancelAll()
                switch first {
                case .fetched(let result):
                    return await self.persistAndApplyCanonicalCampaignMapBundleResult(
                        result,
                        campaignId: campaignId,
                        requestId: requestId,
                        startedAt: debugStartedAt
                    )
                case .failed(let errorDescription):
                    guard self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }
                    self.canonicalBundleRefreshResultByCampaign[campaignId.lowercased()] = "failed"
                    print(
                        "🧪 [MAP_DEBUG] canonical_map_bundle_failed campaign=\(campaignId) " +
                        "ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(errorDescription)"
                    )
                    return false
                case .timedOut:
                    self.canonicalBundleRefreshResultByCampaign[campaignId.lowercased()] = "timeout"
                    print(
                        "🧪 [MAP_DEBUG] canonical_map_bundle_timeout campaign=\(campaignId) " +
                        "waitedMs=\(Int(Double(timeoutNanoseconds) / 1_000_000.0)) action=bundle_only_retry"
                    )
                    return false
                }
            }
        }

        return await fetchCanonicalCampaignMapBundleOnce(
            campaignId: campaignId,
            requestId: requestId,
            localSignature: localSignature,
            startedAt: debugStartedAt
        )
    }

    @discardableResult
    private func fetchCanonicalCampaignMapBundleOnce(
        campaignId: String,
        requestId: UUID?,
        localSignature: String?,
        startedAt debugStartedAt: Date
    ) async -> Bool {
        guard NetworkMonitor.shared.isOnline else { return false }
        let trace = PerfTrace.begin("campaign_open", "canonical_map_bundle_fetch", fields: [
            "campaign": campaignId,
            "hasLocalSignature": localSignature != nil
        ])
        do {
            let result = try await BuildingLinkService.shared.fetchCanonicalCampaignMapBundle(
                campaignId: campaignId,
                localSignature: localSignature
            )
            let didApply = await persistAndApplyCanonicalCampaignMapBundleResult(
                result,
                campaignId: campaignId,
                requestId: requestId,
                startedAt: debugStartedAt
            )
            trace.end(status: didApply ? "success" : "not_applied")
            return didApply
        } catch {
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }
            canonicalBundleRefreshResultByCampaign[campaignId.lowercased()] = "failed"
            print(
                "🧪 [MAP_DEBUG] canonical_map_bundle_failed campaign=\(campaignId) " +
                "ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(error.localizedDescription)"
            )
            trace.end(status: "error", fields: [
                "error": error.localizedDescription
            ])
            return false
        }
    }

    @discardableResult
    private func persistAndApplyCanonicalCampaignMapBundleResult(
        _ result: CampaignMapBundleFetchResult,
        campaignId: String,
        requestId: UUID?,
        startedAt debugStartedAt: Date
    ) async -> Bool {
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }

        switch result {
        case .notModified:
            canonicalBundleRefreshResultByCampaign[campaignId.lowercased()] = "304"
            print(
                "🧪 [MAP_DEBUG] canonical_map_bundle_304 campaign=\(campaignId) " +
                "ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) action=keep_local_cache"
            )
            PerfTrace.event("campaign_open", "canonical_map_bundle_result", fields: [
                "campaign": campaignId,
                "result": "not_modified"
            ])
            return true
        case .bundle(let bundle):
            let persistTrace = PerfTrace.begin("campaign_open", "persist_apply_canonical_bundle", fields: [
                "campaign": campaignId,
                "buildings": bundle.buildings.features.count,
                "addresses": bundle.addresses.features.count,
                "parcels": bundle.parcels.features.count,
                "roads": bundle.roads.features.count,
                "links": bundle.links.count
            ])
            let bundleToApply = await bundlePreservingLocalBuildingsIfNeeded(
                bundle,
                campaignId: campaignId
            )
            let persisted = await campaignRepository.replaceCampaignMapBundle(
                campaignId: campaignId,
                bundle: bundleToApply
            )
            guard persisted,
                  isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else {
                persistTrace.end(status: persisted ? "inactive_request" : "persist_failed")
                return false
            }
            await applyCanonicalCampaignMapBundle(bundleToApply, campaignId: campaignId, requestId: requestId)
            canonicalBundleRefreshResultByCampaign[campaignId.lowercased()] = "200"
            print(
                "🧪 [MAP_DEBUG] canonical_map_bundle_200 campaign=\(campaignId) " +
                "ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) " +
                "signature=\(bundleToApply.assetSignature) linksStatus=\(bundleToApply.linksStatus ?? "unknown")"
            )
            persistTrace.end(status: "success", fields: [
                "linksStatus": bundleToApply.linksStatus ?? "unknown",
                "signature": bundleToApply.assetSignature
            ])
            return true
        }
    }

    private func bundlePreservingLocalBuildingsIfNeeded(
        _ bundle: CanonicalCampaignMapBundle,
        campaignId: String
    ) async -> CanonicalCampaignMapBundle {
        let incomingRenderableBuildings = filteredRenderableBuildingCollection(bundle.buildings)
        guard incomingRenderableBuildings.features.isEmpty else { return bundle }

        let hasLinkedAddressState = !bundle.links.isEmpty
            || (bundle.counts?.links ?? 0) > 0
            || bundle.addresses.features.contains { feature in
                let buildingId = feature.properties.buildingGersId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return buildingId?.isEmpty == false
            }
        guard hasLinkedAddressState else { return bundle }

        let inMemoryBuildings = self.buildings.map(filteredRenderableBuildingCollection)
        let cachedBuildings = await campaignRepository
            .getCampaignMapBundle(campaignId: campaignId)?
            .buildings
        let localBuildings = [inMemoryBuildings, cachedBuildings]
            .compactMap { $0 }
            .first { !$0.features.isEmpty }
        guard let localBuildings, !localBuildings.features.isEmpty else { return bundle }

        let mergedBuildings = await campaignRepository.mergeLocalFallbackBuildings(
            campaignId: campaignId,
            into: localBuildings
        )
        let preservedCount = mergedBuildings.features.count
        guard preservedCount > 0 else { return bundle }

        print(
            "🧪 [MAP_DEBUG] canonical_map_bundle_preserved_local_buildings campaign=\(campaignId) " +
            "incoming=0 preserved=\(preservedCount) links=\(bundle.links.count)"
        )

        let counts = CanonicalCampaignMapBundleCounts(
            addresses: bundle.counts?.addresses ?? bundle.addresses.features.count,
            buildings: preservedCount,
            parcels: bundle.counts?.parcels ?? bundle.parcels.features.count,
            roads: bundle.counts?.roads ?? bundle.roads.features.count,
            links: bundle.counts?.links ?? bundle.links.count
        )

        return CanonicalCampaignMapBundle(
            campaignId: bundle.campaignId,
            assetSignature: bundle.assetSignature,
            sourceVersion: bundle.sourceVersion,
            displayModeHint: "buildings",
            linksStatus: bundle.linksStatus,
            addresses: bundle.addresses,
            buildings: mergedBuildings,
            parcels: bundle.parcels,
            roads: bundle.roads,
            links: bundle.links,
            counts: counts,
            layerFetchedAt: bundle.layerFetchedAt,
            builtAt: bundle.builtAt,
            expiresAt: bundle.expiresAt,
            updatedAt: bundle.updatedAt
        )
    }

    private func applyCanonicalCampaignMapBundle(
        _ bundle: CanonicalCampaignMapBundle,
        campaignId: String,
        requestId: UUID?
    ) async {
        let mergedBuildings = await campaignRepository.mergeLocalFallbackBuildings(
            campaignId: campaignId,
            into: bundle.buildings
        )
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }

        self.buildings = filteredRenderableBuildingCollection(mergedBuildings)
        self.addresses = bundle.addresses
        self.parcels = bundle.parcels
        self.roads = bundle.roads
        self.displayModeHint = bundle.displayModeHint
        self.currentCanonicalBundleLinksStatus = bundle.linksStatus
        storeCurrentFeatureSnapshot(campaignId: campaignId)

        if !bundle.links.isEmpty {
            applyClientLinks(bundle.links, toCampaignId: campaignId)
        }

        scheduleClientLinkingIfReady(campaignId: campaignId, requestId: requestId)
    }

    private func loadDiamondManifestIfAvailable(campaignId: String, requestId: UUID? = nil) async -> Bool {
        guard diamondPMTilesRenderingEnabled else {
            self.diamondManifest = nil
            print("💎 [DIAMOND] PMTiles renderer disabled for campaign \(campaignId); using GeoJSON fallback")
            return false
        }

        guard let campaignUUID = UUID(uuidString: campaignId) else {
            self.diamondManifest = nil
            return false
        }

        let campaignKey = campaignId.lowercased()
        if unsupportedDiamondManifestCampaigns.contains(campaignKey) {
            self.diamondManifest = nil
            print("💎 [DIAMOND] PMTiles disabled for campaign \(campaignId); using GeoJSON fallback")
            return false
        }

        if let prewarmedManifest = prewarmedDiamondManifestsByCampaign.removeValue(forKey: campaignKey),
           prewarmedManifest.hasRenderablePMTilesGeometry || prewarmedManifest.hasRenderablePMTilesAddresses || prewarmedManifest.hasRenderablePMTilesParcels {
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }
            self.diamondManifest = prewarmedManifest
            print("💎 [DIAMOND] Using primed PMTiles manifest for campaign \(campaignId)")
            return true
        }

        do {
            let manifest = try await DiamondManifestAPI.shared.fetchManifest(campaignId: campaignUUID)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }

            guard manifest.hasRenderablePMTilesGeometry || manifest.hasRenderablePMTilesAddresses || manifest.hasRenderablePMTilesParcels else {
                self.diamondManifest = nil
                print(
                    "💎 [DIAMOND] Manifest unavailable or unsupported " +
                    "(provider=\(manifest.geometryProvider ?? "nil"), hasTileTemplate=\(manifest.vectorTileUrlTemplate != nil), hasAddressTileTemplate=\(manifest.addressVectorTileUrlTemplate != nil), hasParcelTileTemplate=\(manifest.parcelVectorTileUrlTemplate != nil), buildingsLayer=\(manifest.sourceLayers?.buildings ?? "nil"), addressCirclesLayer=\(manifest.sourceLayers?.addressCircles ?? "nil"), addressesLayer=\(manifest.sourceLayers?.addresses ?? "nil"), parcelsLayer=\(manifest.sourceLayers?.parcels ?? "nil")); PMTiles geometry unavailable"
                )
                storeCurrentFeatureSnapshot(campaignId: campaignId)
                return false
            }

            self.diamondManifest = manifest
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            print("💎 [DIAMOND] Loaded PMTiles manifest for campaign \(campaignId)")
            if !manifest.hasRenderablePMTilesAddresses {
                beginDiamondManifestPrewarm(campaignId: campaignId, timeoutSeconds: 90)
                print("💎 [DIAMOND] Manifest is missing renderable PMTiles addresses; waiting for address tile layer")
            }
            return true
        } catch {
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }

            self.diamondManifest = nil
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            if shouldRetryDiamondManifest(error) {
                beginDiamondManifestPrewarm(campaignId: campaignId, timeoutSeconds: 90)
                print("💎 [DIAMOND] Manifest pending (\(error.localizedDescription)); continuing while it warms in the background")
            } else {
                print("💎 [DIAMOND] Manifest request failed (\(error.localizedDescription)); PMTiles geometry unavailable")
            }
            return false
        }
    }

    private func shouldRetryDiamondManifest(_ error: Error) -> Bool {
        guard let manifestError = error as? DiamondManifestAPIError else { return false }
        return manifestError.statusCode == 202 || manifestError.statusCode == 404
    }

    private static func hasLinkedAddressIdentity(
        buildings: BuildingFeatureCollection?,
        addresses: AddressFeatureCollection
    ) -> Bool {
        if addresses.features.contains(where: { feature in
            let buildingId = feature.properties.buildingGersId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return buildingId?.isEmpty == false
        }) {
            return true
        }

        return buildings?.features.contains(where: { feature in
            if feature.properties.isLinked == true { return true }
            let addressId = feature.properties.addressId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return addressId?.isEmpty == false
        }) == true
    }

    private static func canonicalLinksAreFresh(_ status: String?) -> Bool {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ok", "fresh", "ready":
            return true
        default:
            return false
        }
    }

    private func canonicalBundleRefreshDiagnostic(for campaignId: String) -> String {
        canonicalBundleRefreshResultByCampaign[campaignId.lowercased()] ?? "none"
    }

    @discardableResult
    private func fetchCampaignMapBundle(campaignId: String, requestId: UUID? = nil, startedAt debugStartedAt: Date = Date()) async -> Bool {
        do {
            guard let campaignUUID = UUID(uuidString: campaignId) else {
                print("❌ [MapFeatures] Invalid campaign ID format for map bundle: \(campaignId)")
                print("🧪 [MAP_DEBUG] map_bundle_failed campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=invalid_campaign_id")
                return false
            }

            let data = try await supabase.callRPCData(
                "rpc_get_campaign_map_bundle",
                params: ["p_campaign_id": campaignUUID.uuidString]
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bundle = try decoder.decode(CampaignMapBundle.self, from: data)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }

            await campaignRepository.upsertBuildings(campaignId: campaignId, features: bundle.buildings.features)
            let mergedBuildings = await campaignRepository.mergeLocalFallbackBuildings(
                campaignId: campaignId,
                into: bundle.buildings
            )
            let filteredBuildings = filteredRenderableBuildingCollection(mergedBuildings)
            self.buildings = filteredBuildings
            self.addresses = bundle.addresses
            self.parcels = bundle.parcels
            self.roads = bundle.roads
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }

            await campaignRepository.upsertAddresses(campaignId: campaignId, features: bundle.addresses.features)
            await campaignRepository.upsertParcels(campaignId: campaignId, features: bundle.parcels.features)

            print(
                "🧪 [MAP_DEBUG] map_bundle_loaded campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) " +
                "phase=\(bundle.phase ?? "unknown") source=\(bundle.source ?? "unknown") " +
                "addresses=\(bundle.addresses.features.count) buildings=\(filteredBuildings.features.count) parcels=\(bundle.parcels.features.count) roads=\(bundle.roads.features.count)"
            )
            return true
        } catch {
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }
            print("❌ [MapFeatures] Error fetching campaign map bundle: \(error)")
            print("🧪 [MAP_DEBUG] map_bundle_failed campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(error.localizedDescription)")
            return false
        }
    }

    private func fetchCampaignBuildings(campaignId: String, requestId: UUID? = nil) async {
        let debugStartedAt = Date()

        if let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
           isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) {
            let filtered = filteredRenderableBuildingCollection(cachedBundle.buildings)
            self.buildings = filtered
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            print(
                "🧪 [MAP_DEBUG] buildings_geojson_cache_loaded campaign=\(campaignId) " +
                "cached=\(cachedBundle.buildings.features.count) renderable=\(filtered.features.count)"
            )
        }

        guard NetworkMonitor.shared.isOnline else {
            if self.buildings?.features.isEmpty ?? true {
                print("📴 [MapFeatures] No cached building GeoJSON available while offline for campaign \(campaignId)")
            }
            return
        }

        do {
            let features = try await BuildingLinkService.shared.fetchBuildings(campaignId: campaignId)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }

            let collection = BuildingFeatureCollection(type: "FeatureCollection", features: features)
            await campaignRepository.upsertBuildings(campaignId: campaignId, features: features)
            let merged = await campaignRepository.mergeLocalFallbackBuildings(campaignId: campaignId, into: collection)
            let filtered = filteredRenderableBuildingCollection(merged)
            self.buildings = filtered
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            print("✅ [MapFeatures] Loaded \(filtered.features.count) stable linked campaign buildings")
            print(
                "🧪 [MAP_DEBUG] buildings_geojson_loaded campaign=\(campaignId) " +
                "ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) " +
                "cached=\(features.count) renderable=\(filtered.features.count) role=state_overlay_or_fallback"
            )
            scheduleClientLinkingIfReady(campaignId: campaignId, requestId: requestId)
        } catch {
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }

            print("❌ [MapFeatures] Error fetching stable linked campaign buildings: \(error)")
            print("🧪 [MAP_DEBUG] buildings_geojson_failed campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(error.localizedDescription)")
            if self.buildings?.features.isEmpty ?? true {
                self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
            }
        }
    }

    /// Fetch route-scoped features from the backend assignment map endpoint.
    /// Falls back to full campaign loading if the scoped endpoint is unavailable.
    func fetchRouteScopedCampaignFeatures(assignmentId: UUID, campaignId: String) async {
        let trace = PerfTrace.begin("campaign_open", "fetch_route_scoped_features", fields: [
            "assignment": assignmentId.uuidString,
            "campaign": campaignId
        ])
        let campaignIdLower = campaignId.lowercased()
        let requestId = UUID()
        activeCampaignRequestId = requestId
        activeCampaignIdLower = campaignIdLower
        isLoading = true
        error = nil

        do {
            let payload = try await RouteAssignmentsAPI.shared.fetchAssignmentMap(assignmentId: assignmentId)
            await applyRouteScopedPayload(payload, assignmentId: assignmentId, campaignId: campaignId, requestId: requestId)
            trace.end(status: "remote_success", fields: [
                "buildings": payload.buildings.features.count,
                "addresses": payload.addresses.features.count
            ])
        } catch {
            if isCancellationError(error) {
                print("ℹ️ [MapFeatures] Route-scoped request cancelled")
                trace.end(status: "cancelled")
                return
            }

            if case RouteAssignmentsAPIError.unauthorized = error {
                print("⚠️ [MapFeatures] Route-scoped load returned unauthorized; retrying once before full fallback")
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    let payload = try await RouteAssignmentsAPI.shared.fetchAssignmentMap(assignmentId: assignmentId)
                    await applyRouteScopedPayload(payload, assignmentId: assignmentId, campaignId: campaignId, requestId: requestId)
                    isLoading = false
                    trace.end(status: "remote_retry_success", fields: [
                        "buildings": payload.buildings.features.count,
                        "addresses": payload.addresses.features.count
                    ])
                    return
                } catch {
                    if isCancellationError(error) {
                        print("ℹ️ [MapFeatures] Route-scoped retry cancelled")
                        trace.end(status: "retry_cancelled")
                        return
                    }
                    print("⚠️ [MapFeatures] Route-scoped retry failed (\(error))")
                }
            }

            print("⚠️ [MapFeatures] Route-scoped load failed (\(error)); falling back to full campaign data")
            await fetchAllCampaignFeatures(campaignId: campaignId)
            trace.end(status: "full_campaign_fallback", fields: [
                "error": error.localizedDescription
            ])
            return
        }

        isLoading = false
    }

    private func applyRouteScopedPayload(
        _ payload: RouteAssignmentMapPayload,
        assignmentId: UUID,
        campaignId: String,
        requestId: UUID
    ) async {
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }

        self.buildings = filteredRenderableBuildingCollection(payload.buildings)
        self.addresses = payload.addresses
        self.roads = RoadFeatureCollection(type: "FeatureCollection", features: [])
        self.diamondManifest = nil
        storeCurrentFeatureSnapshot(campaignId: campaignId)

        print(
            "✅ [MapFeatures] Loaded route-scoped map for assignment \(assignmentId.uuidString) " +
            "buildings=\(payload.buildings.features.count) addresses=\(payload.addresses.features.count)"
        )

    }
    
    private func filteredRenderableBuildingCollection(_ collection: BuildingFeatureCollection) -> BuildingFeatureCollection {
        BuildingFeatureCollection(
            type: collection.type,
            features: filteredRenderableBuildingFeatures(collection.features)
        )
    }

    private func filteredRenderableBuildingFeatures(_ features: [BuildingFeature]) -> [BuildingFeature] {
        let filtered = features.filter(Self.isRenderableBuildingFeature)
        let removed = features.count - filtered.count
        if removed > 0 {
            print("🧹 [MapFeatures] Filtered \(removed) building feature(s) under \(Int(Self.minimumRenderableBuildingAreaSqm))m²")
        }
        return filtered
    }

    private static func isRenderableBuildingFeature(_ feature: BuildingFeature) -> Bool {
        let geometryType = feature.geometry.type.lowercased()
        guard geometryType == "polygon" || geometryType == "multipolygon" else {
            return false
        }

        guard !isAddressProxyBuildingFeature(feature) else {
            return false
        }

        let source = feature.properties.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source == "manual" || source == "manual_fallback" {
            return true
        }

        if let areaSqm = feature.properties.areaSqm,
           areaSqm > 0,
           areaSqm < minimumRenderableBuildingAreaSqm {
            return false
        }

        return true
    }

    private static func isAddressProxyBuildingFeature(_ feature: BuildingFeature) -> Bool {
        func normalized(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        }

        let source = normalized(feature.properties.source)
        let featureType = normalized(feature.properties.featureType)
        let featureStatus = normalized(feature.properties.featureStatus)
        let identifierSource = normalized(feature.properties.buildingIdentifierSource)
        let identifiers = [
            feature.id,
            feature.properties.id,
            feature.properties.gersId,
            feature.properties.buildingId,
            feature.properties.publicBuildingId,
            feature.properties.canonicalBuildingId
        ].map(normalized)

        return source == "address_proxy"
            || featureType == "address_proxy"
            || featureStatus == "missing_footprint_proxy"
            || identifierSource == "address_proxy"
            || identifiers.contains(where: { $0.hasPrefix("address-proxy-") })
    }

    private func replayCampaignCreationPathIfNeeded(campaignId: String, requestId: UUID? = nil) async {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }

        let campaignRow: CampaignDBRow
        do {
            campaignRow = try await CampaignsAPI.shared.fetchCampaignDBRow(id: campaignUUID)
        } catch {
            print("⚠️ [MapFeatures] Could not read campaign metadata for replay: \(error.localizedDescription)")
            return
        }

        guard campaignRow.addressSource == .map else {
            print("ℹ️ [MapFeatures] Empty map payload for non-polygon campaign; no replayable create path")
            return
        }

        guard let polygon = await CampaignsAPI.shared.fetchTerritoryBoundary(campaignId: campaignUUID),
              let polygonGeoJSON = polygonGeoJSONString(from: polygon) else {
            print("⚠️ [MapFeatures] Empty polygon campaign missing territory_boundary; cannot replay create path")
            return
        }

        print("🔁 [MapFeatures] Replaying polygon create flow for empty campaign \(campaignId)")

        print("🔁 [MapFeatures] Territory boundary payload size: \(polygonGeoJSON.count) bytes")

        do {
            let provisionResponse = try await CampaignsAPI.shared.provisionCampaign(campaignId: campaignUUID)
            if provisionResponse?.provisionStatus == .ready {
                print(
                    "✅ [MapFeatures] Replay provision finished with status \(provisionResponse?.provisionStatus?.rawValue ?? "unknown") " +
                    "phase \(provisionResponse?.provisionPhase?.rawValue ?? "unknown")"
                )
            } else {
                let state = try await CampaignsAPI.shared.waitForProvisionReady(
                    campaignId: campaignUUID,
                    timeoutSeconds: 45,
                    pollIntervalSeconds: 2
                )
                print("✅ [MapFeatures] Replay provision finished with status \(state.provisionStatus?.rawValue ?? "unknown") phase \(state.provisionPhase?.rawValue ?? "unknown")")
            }
        } catch {
            print("⚠️ [MapFeatures] provision replay failed: \(error.localizedDescription)")
        }

        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
    }

    private func polygonGeoJSONString(from polygon: [CLLocationCoordinate2D]) -> String? {
        guard polygon.count >= 3 else { return nil }

        var ring = polygon.map { [$0.longitude, $0.latitude] }
        if ring.first != ring.last, let first = ring.first {
            ring.append(first)
        }

        let geoJSON = GeoJSONPolygon(type: "Polygon", coordinates: [ring])
        guard let data = try? JSONEncoder().encode(geoJSON) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Partition RPC full-features by geometry: Polygon/MultiPolygon -> buildings, Point -> address fallback.
    private func partitionFeaturesByGeometry(_ features: [BuildingFeature]) -> (polygons: [BuildingFeature], points: [BuildingFeature]) {
        var polygons: [BuildingFeature] = []
        var points: [BuildingFeature] = []
        for f in features {
            let geoType = f.geometry.type.lowercased()
            if geoType == "polygon" || geoType == "multipolygon" {
                polygons.append(f)
            } else if geoType == "point" {
                points.append(f)
            }
        }
        return (polygons, points)
    }
    
    /// Convert Point building features (address_point fallback) to AddressFeature for the addresses layer.
    private func addressFeaturesFromPointBuildingFeatures(_ points: [BuildingFeature]) -> [AddressFeature] {
        points.compactMap { feature in
            guard feature.geometry.asPoint != nil else { return nil }
            let p = feature.properties
            let formatted = p.addressText ?? "\(p.houseNumber ?? "") \(p.streetName ?? "")".trimmingCharacters(in: .whitespaces)
            let addrProps = AddressProperties(
                id: p.addressId,
                gersId: p.gersId,
                buildingGersId: p.buildingId,
                houseNumber: p.houseNumber,
                streetName: p.streetName,
                postalCode: nil,
                locality: nil,
                formatted: formatted.isEmpty ? nil : formatted,
                source: p.source
            )
            return AddressFeature(
                type: "Feature",
                id: p.addressId ?? feature.id,
                geometry: feature.geometry,
                properties: addrProps
            )
        }
    }
    
    /// Merge address features: existing plus additional, deduped by address id.
    private func mergeAddressFeatures(existing: AddressFeatureCollection?, additional: [AddressFeature]) -> [AddressFeature] {
        var seenIds = Set((existing?.features ?? []).compactMap { $0.properties.id ?? $0.id }.map { $0.lowercased() })
        var result = existing?.features ?? []
        for addr in additional {
            let id = (addr.properties.id ?? addr.id ?? "").lowercased()
            if !id.isEmpty {
                if !seenIds.contains(id) {
                    seenIds.insert(id)
                    result.append(addr)
                }
            } else {
                result.append(addr)
            }
        }
        return result
    }
    
    /// Convert GeoJSON feature collection to BuildingFeatureCollection for the map layer.
    private func buildingFeatureCollectionFromGeoJSON(_ collection: GeoJSONFeatureCollection) -> BuildingFeatureCollection {
        let features = collection.features.compactMap { geoFeature -> BuildingFeature? in
            guard let geometry = mapFeatureGeometryFromGeoJSON(geoFeature.geometry) else { return nil }
            let props = buildingPropertiesFromGeoJSONFeature(geoFeature)
            return BuildingFeature(
                type: "Feature",
                id: geoFeature.id,
                geometry: geometry,
                properties: props
            )
        }
        return BuildingFeatureCollection(type: "FeatureCollection", features: features)
    }
    
    /// Decode GeoJSON geometry (Polygon/MultiPolygon) as MapFeatureGeoJSONGeometry for map layer.
    private func mapFeatureGeometryFromGeoJSON(_ geo: GeoJSONGeometry) -> MapFeatureGeoJSONGeometry? {
        guard geo.type == "Polygon" || geo.type == "MultiPolygon" else { return nil }
        do {
            let data = try JSONEncoder().encode(geo)
            return try JSONDecoder().decode(MapFeatureGeoJSONGeometry.self, from: data)
        } catch {
            return nil
        }
    }
    
    /// Build BuildingProperties from GeoJSON feature properties with safe defaults for closest-home fallback.
    private func buildingPropertiesFromGeoJSONFeature(_ feature: GeoJSONFeature) -> BuildingProperties {
        let p = feature.properties
        func str(_ key: String) -> String? {
            (p[key]?.value as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        func int(_ key: String) -> Int { (p[key]?.value as? Int) ?? (p[key]?.value as? Double).map(Int.init) ?? 0 }
        func double(_ key: String) -> Double { (p[key]?.value as? Double) ?? (p[key]?.value as? Int).map(Double.init) ?? 0 }
        func bool(_ key: String) -> Bool? {
            (p[key]?.value as? Bool) ?? (p[key]?.value as? Int).map { $0 != 0 }
        }
        func stringArray(_ key: String) -> [String] {
            if let values = p[key]?.value as? [String] {
                return values
            }
            if let values = p[key]?.value as? [Any] {
                return values.compactMap { $0 as? String }
            }
            return []
        }
        let fallbackId = (str("building_id") ?? str("gers_id") ?? feature.id ?? UUID().uuidString).lowercased()
        let rawPublicId = str("public_building_id")
            ?? str("canonical_building_id")
            ?? str("gers_id")
            ?? str("building_id")
            ?? feature.id
            ?? UUID().uuidString
        let rawGersId = str("gers_id") ?? rawPublicId
        return BuildingProperties(
            id: str("building_id") ?? str("id") ?? fallbackId,
            buildingId: str("building_id"),
            addressId: str("address_id"),
            addressIds: stringArray("address_ids"),
            gersId: rawGersId.lowercased(),
            publicBuildingId: rawPublicId.lowercased(),
            canonicalBuildingId: (str("canonical_building_id") ?? rawPublicId).lowercased(),
            buildingIdentifierSource: str("building_identifier_source"),
            height: double("height") > 0 ? double("height") : 10,
            heightM: (p["height_m"]?.value as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 10,
            minHeight: double("min_height"),
            isTownhome: (p["is_townhome"]?.value as? Bool) ?? false,
            unitsCount: int("units_count") > 0 ? int("units_count") : 1,
            addressText: str("address_text"),
            matchMethod: str("match_method"),
            featureStatus: str("feature_status"),
            featureType: str("feature_type"),
            status: str("status") ?? "not_visited",
            scansToday: int("scans_today"),
            scansTotal: int("scans_total"),
            lastScanSecondsAgo: (p["last_scan_seconds_ago"]?.value as? Double),
            houseNumber: str("house_number"),
            streetName: str("street_name"),
            confidence: (p["confidence"]?.value as? Double).flatMap { $0 >= 0 ? $0 : nil },
            source: str("source"),
            addressCount: int("address_count") > 0 ? int("address_count") : nil,
            areaSqm: double("area_sqm") > 0 ? double("area_sqm") : nil,
            buildingType: str("building_type"),
            qrScanned: bool("qr_scanned"),
            isLinked: bool("is_linked")
        )
    }
    
    private func applyFreshCanonicalAddressesIfAvailable(
        campaignId: String,
        requestId: UUID?,
        caller: String,
        startedAt debugStartedAt: Date
    ) async -> Bool {
        guard let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
              let metadata = cachedBundle.metadata,
              metadata.hasUsableFreshCanonicalBundle,
              !cachedBundle.addresses.features.isEmpty else {
            return false
        }

        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else {
            return true
        }

        self.addresses = cachedBundle.addresses
        storeCurrentFeatureSnapshot(campaignId: campaignId)
        let canonicalRefresh = canonicalBundleRefreshDiagnostic(for: campaignId)
        print(
            "🔷 [SHIM] SKIP RPC rpc_get_campaign_addresses reason=fresh_canonical_bundle " +
            "caller=\(caller) hasLocalBundle=true bundleFresh=\(metadata.isFresh) " +
            "canonicalRefresh=\(canonicalRefresh)"
        )
        print(
            "🧪 [MAP_DEBUG] addresses_geojson_skipped campaign=\(campaignId) " +
            "reason=fresh_canonical_bundle caller=\(caller) cached=\(cachedBundle.addresses.features.count) " +
            "linksStatus=\(metadata.linksStatus ?? "unknown") ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000))"
        )
        return true
    }

    /// Fetch Supabase campaign address points when the Diamond manifest has no address tile layer.
    private func fetchCampaignAddresses(campaignId: String, requestId: UUID? = nil) async {
        let debugStartedAt = Date()
        do {
            guard let campaignUUID = UUID(uuidString: campaignId) else {
                print("❌ [MapFeatures] Invalid campaign ID format for addresses: \(campaignId)")
                print("🧪 [MAP_DEBUG] addresses_geojson_failed campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=invalid_campaign_id")
                return
            }
            if await applyFreshCanonicalAddressesIfAvailable(
                campaignId: campaignId,
                requestId: requestId,
                caller: "MapFeaturesService.fetchCampaignAddresses",
                startedAt: debugStartedAt
            ) {
                return
            }
            let fallbackMetadata = await campaignRepository.getCampaignMapBundleMetadata(campaignId: campaignId)
            let data = try await supabase.callRPCData(
                "rpc_get_campaign_addresses",
                params: ["p_campaign_id": campaignUUID.uuidString],
                reason: "legacy_geojson_cold_fallback",
                caller: "MapFeaturesService.fetchCampaignAddresses",
                hasLocalBundle: fallbackMetadata != nil,
                bundleFresh: fallbackMetadata?.isFresh,
                canonicalRefresh: canonicalBundleRefreshDiagnostic(for: campaignId)
            )
            let result: AddressFeatureCollection = try decodeFeatureCollection(data)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            let finalResult: AddressFeatureCollection
            if result.features.isEmpty {
                let pmtilesResult = try await fetchCampaignAddressGeoJSONFromAPI(campaignId: campaignUUID)
                finalResult = pmtilesResult.features.isEmpty ? result : pmtilesResult
            } else {
                finalResult = result
            }
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            self.addresses = finalResult
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            await campaignRepository.upsertAddresses(campaignId: campaignId, features: finalResult.features)
            print("✅ [MapFeatures] Loaded \(finalResult.features.count) campaign address points")
            print("🧪 [MAP_DEBUG] addresses_geojson_loaded campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) features=\(finalResult.features.count) role=proximity_and_fallback")
            scheduleClientLinkingIfReady(campaignId: campaignId, requestId: requestId)
        } catch {
            print("❌ [MapFeatures] Error fetching campaign addresses: \(error)")
            print("🧪 [MAP_DEBUG] addresses_geojson_failed campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(error.localizedDescription)")
        }
    }

    /// Load roads from local cache first, then refresh from the existing campaign road service.
    func fetchCampaignRoads(campaignId: String, requestId: UUID? = nil) async {
        let debugStartedAt = Date()
        if let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
           isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) {
            self.roads = cachedBundle.roads
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            print("🧪 [MAP_DEBUG] roads_cache_loaded campaign=\(campaignId) features=\(cachedBundle.roads.features.count)")
        }

        let corridors = await CampaignRoadService.shared.getRoadsForSession(campaignId: campaignId)
        await campaignRepository.upsertRoads(campaignId: campaignId, corridors: corridors)
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
        if let refreshedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId) {
            self.roads = refreshedBundle.roads
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            print("🧪 [MAP_DEBUG] roads_loaded campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) corridors=\(corridors.count) features=\(refreshedBundle.roads.features.count) role=background")
        }
    }

    private func fetchCampaignParcels(campaignId: String, requestId: UUID? = nil) async {
        let debugStartedAt = Date()
        let loadedSuccessfully = await fetchCampaignParcelsOnce(
            campaignId: campaignId,
            requestId: requestId,
            attempt: 1,
            startedAt: debugStartedAt,
            clearOnFailure: true
        )

        if !loadedSuccessfully, isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) {
            scheduleCampaignParcelsRetry(campaignId: campaignId, requestId: requestId, startedAt: debugStartedAt)
        }
    }

    @discardableResult
    private func fetchCampaignParcelsOnce(
        campaignId: String,
        requestId: UUID?,
        attempt: Int,
        startedAt debugStartedAt: Date,
        clearOnFailure: Bool
    ) async -> Bool {
        do {
            guard let campaignUUID = UUID(uuidString: campaignId) else {
                print("❌ [MapFeatures] Invalid campaign ID format for parcels: \(campaignId)")
                print("🧪 [MAP_DEBUG] parcels_geojson_failed campaign=\(campaignId) attempt=\(attempt) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=invalid_campaign_id")
                return true
            }

            let result: ParcelFeatureCollection
            do {
                let apiResult = try await BuildingLinkService.shared.fetchCampaignParcels(campaignId: campaignId)
                if apiResult.features.isEmpty {
                    let data = try await supabase.callRPCData(
                        "rpc_get_campaign_parcels",
                        params: ["p_campaign_id": campaignUUID.uuidString]
                    )
                    result = try decodeFeatureCollection(data)
                } else {
                    result = apiResult
                }
            } catch {
                let data = try await supabase.callRPCData(
                    "rpc_get_campaign_parcels",
                    params: ["p_campaign_id": campaignUUID.uuidString]
                )
                result = try decodeFeatureCollection(data)
            }
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }
            self.parcels = result
            storeCurrentFeatureSnapshot(campaignId: campaignId)
            await campaignRepository.upsertParcels(campaignId: campaignId, features: result.features)
            print("✅ [MapFeatures] Loaded \(result.features.count) campaign parcels")
            print("🧪 [MAP_DEBUG] parcels_geojson_loaded campaign=\(campaignId) attempt=\(attempt) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) features=\(result.features.count) role=geojson_render")
            scheduleClientLinkingIfReady(campaignId: campaignId, requestId: requestId)
            return true
        } catch {
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return false }
            if clearOnFailure {
                self.parcels = ParcelFeatureCollection(type: "FeatureCollection", features: [])
                storeCurrentFeatureSnapshot(campaignId: campaignId)
            }
            print("❌ [MapFeatures] Error fetching campaign parcels: \(error)")
            print("🧪 [MAP_DEBUG] parcels_geojson_failed campaign=\(campaignId) attempt=\(attempt) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000)) error=\(error.localizedDescription)")
            return false
        }
    }

    private func scheduleCampaignParcelsRetry(campaignId: String, requestId: UUID?, startedAt debugStartedAt: Date) {
        parcelRetryTask?.cancel()
        parcelRetryTask = Task { [weak self] in
            let delays: [UInt64] = [
                2_000_000_000,
                4_000_000_000,
                8_000_000_000,
                15_000_000_000
            ]

            for (index, delay) in delays.enumerated() {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else { return }
                guard self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
                print("🧪 [MAP_DEBUG] parcels_geojson_retry campaign=\(campaignId) attempt=\(index + 2)")
                let loadedSuccessfully = await self.fetchCampaignParcelsOnce(
                    campaignId: campaignId,
                    requestId: requestId,
                    attempt: index + 2,
                    startedAt: debugStartedAt,
                    clearOnFailure: false
                )
                if loadedSuccessfully {
                    return
                }
            }

            guard let self, self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            print("🧪 [MAP_DEBUG] parcels_geojson_retry_exhausted campaign=\(campaignId) ms=\(Int(Date().timeIntervalSince(debugStartedAt) * 1000))")
        }
    }

    private static func clientLinkingSignature(
        campaignId: String,
        buildings: BuildingFeatureCollection,
        addresses: AddressFeatureCollection,
        parcels: ParcelFeatureCollection?
    ) -> String {
        let buildingIds = buildings.features
            .compactMap { $0.properties.canonicalBuildingIdentifier ?? $0.id }
            .map { $0.lowercased() }
            .sorted()
        let addressIds = addresses.features
            .compactMap { $0.properties.id ?? $0.id }
            .map { $0.lowercased() }
            .sorted()
        let parcelIds = (parcels?.features ?? [])
            .compactMap { $0.properties.parcelId ?? $0.properties.externalId ?? $0.id }
            .map { $0.lowercased() }
            .sorted()

        return [
            campaignId.lowercased(),
            "b\(buildings.features.count):\(stableSignatureHash(buildingIds))",
            "a\(addresses.features.count):\(stableSignatureHash(addressIds))",
            "p\(parcels?.features.count ?? 0):\(stableSignatureHash(parcelIds))"
        ].joined(separator: ":")
    }

    private static func stableSignatureHash(_ values: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        for value in values {
            for byte in value.utf8 {
                hash ^= UInt64(byte)
                hash &*= prime
            }
            hash ^= 0xff
            hash &*= prime
        }
        return String(hash, radix: 16)
    }

    private static func unlinkedAddressCount(_ addresses: AddressFeatureCollection) -> Int {
        addresses.features.filter { feature in
            let buildingId = feature.properties.buildingGersId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return buildingId?.isEmpty != false
        }.count
    }

    private func scheduleClientLinkingIfReady(campaignId: String, requestId: UUID? = nil) {
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
        guard let buildings, let addresses else { return }
        guard !buildings.features.isEmpty, !addresses.features.isEmpty else {
            clientLinkingProgress = ClientLinkingProgress(
                processed: addresses.features.count,
                total: addresses.features.count,
                linked: 0
            )
            return
        }
        if let linksStatus = currentCanonicalBundleLinksStatus,
           linksStatus != "client_fallback_required",
           Self.hasLinkedAddressIdentity(buildings: buildings, addresses: addresses) {
            let linkedAddressCount = addresses.features.filter {
                let buildingId = $0.properties.buildingGersId?.trimmingCharacters(in: .whitespacesAndNewlines)
                return buildingId?.isEmpty == false
            }.count
            clientLinkingProgress = ClientLinkingProgress(
                processed: addresses.features.count,
                total: addresses.features.count,
                linked: max(linkedAddressCount, 0)
            )
            print(
                "🧪 [MAP_DEBUG] client_linking_skipped campaign=\(campaignId) " +
                "reason=canonical_bundle_links_status linksStatus=\(linksStatus)"
            )
            return
        }

        let signature = Self.clientLinkingSignature(
            campaignId: campaignId,
            buildings: buildings,
            addresses: addresses,
            parcels: parcels
        )

        if clientLinkingSignature == signature,
           clientLinkingTask != nil || clientLinkingProgress.percent == 100 {
            return
        }

        clientLinkingTask?.cancel()
        clientLinkingSignature = signature
        let snapshotBuildings = buildings
        let snapshotAddresses = addresses
        let snapshotParcels = parcels
        let unlinkedAddressCount = Self.unlinkedAddressCount(snapshotAddresses)

        clientLinkingTask = Task { [weak self] in
            guard let self else { return }
            if NetworkMonitor.shared.isOnline,
               let canonicalLinks = try? await BuildingLinkService.shared.fetchLinks(campaignId: campaignId),
               !canonicalLinks.isEmpty {
                let canonicalClientLinks = canonicalLinks.map { link in
                    ClientBuildingAddressLink(
                        id: link.id,
                        buildingId: link.buildingId,
                        addressId: link.addressId,
                        matchType: link.matchType,
                        confidence: link.confidence,
                        distanceMeters: 0
                    )
                }
                await MainActor.run {
                    guard self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
                    self.applyClientLinks(canonicalClientLinks, toCampaignId: campaignId)
                    self.clientLinkingProgress = ClientLinkingProgress(
                        processed: snapshotAddresses.features.count,
                        total: snapshotAddresses.features.count,
                        linked: canonicalClientLinks.count
                    )
                    self.clientLinkingTask = nil
                    print(
                        "🧪 [MAP_DEBUG] backend_links_applied campaign=\(campaignId) " +
                        "links=\(canonicalClientLinks.count) source=supabase"
                    )
                }
                return
            }

            if let cachedBatch = await self.campaignRepository.getClientGeneratedLinkBatch(
                campaignId: campaignId,
                assetSignature: signature
            ) {
                let cachedLinks = cachedBatch.summary.links
                if cachedLinks.isEmpty, unlinkedAddressCount > 0, !snapshotBuildings.features.isEmpty {
                    print(
                        "🧪 [MAP_DEBUG] client_linking_cache_ignored campaign=\(campaignId) " +
                        "reason=zero_links_with_unlinked_addresses unlinked=\(unlinkedAddressCount) signature=\(cachedBatch.assetSignature)"
                    )
                } else {
                    await MainActor.run {
                        guard self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
                        self.applyClientLinks(cachedLinks, toCampaignId: campaignId)
                        self.clientLinkingProgress = cachedBatch.summary.progress
                        self.clientLinkingTask = nil
                        print(
                            "🧪 [MAP_DEBUG] client_linking_cache_hit campaign=\(campaignId) " +
                            "links=\(cachedLinks.count) signature=\(cachedBatch.assetSignature)"
                        )
                    }
                    return
                }
            }

            let summary = await ClientMapLinkerService.shared.link(
                buildings: snapshotBuildings,
                addresses: snapshotAddresses,
                parcels: snapshotParcels,
                progress: { progress in
                    await MainActor.run {
                        guard self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
                        self.clientLinkingProgress = progress
                    }
                }
            )
            guard !Task.isCancelled else { return }
            if !summary.links.isEmpty || unlinkedAddressCount == 0 {
                await self.campaignRepository.upsertClientGeneratedBuildingAddressLinks(
                    campaignId: campaignId,
                    links: summary.links,
                    assetSignature: signature,
                    buildingCount: snapshotBuildings.features.count,
                    addressCount: snapshotAddresses.features.count,
                    parcelCount: snapshotParcels?.features.count ?? 0
                )
            } else {
                print(
                    "🧪 [MAP_DEBUG] client_linking_zero_not_cached campaign=\(campaignId) " +
                    "unlinked=\(unlinkedAddressCount) buildings=\(snapshotBuildings.features.count)"
                )
            }
            await MainActor.run {
                guard self.isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
                self.applyClientLinks(summary.links, toCampaignId: campaignId)
                self.clientLinkingProgress = summary.progress
                self.clientLinkingTask = nil
                print(
                    "🧪 [MAP_DEBUG] client_linking_complete campaign=\(campaignId) " +
                    "links=\(summary.links.count) total=\(summary.progress.total)"
                )
            }

            guard !Task.isCancelled, NetworkMonitor.shared.isOnline, !summary.links.isEmpty else { return }
            // Client links are local-render-only in production.
            // Canonical links are written exclusively by the backend provision linker.
            // See: flyr-linking-restructure task 3
            #if DEBUG
            do {
                try await BuildingLinkService.shared.publishClientGeneratedLinks(
                    campaignId: campaignId,
                    links: summary.links,
                    assetSignature: signature
                )
            } catch {
                print("⚠️ [MapFeatures] Failed to publish client generated links: \(error.localizedDescription)")
            }
            #endif
        }
    }

    private func applyClientLinks(_ clientLinks: [ClientBuildingAddressLink], toCampaignId campaignId: String) {
        guard !clientLinks.isEmpty else { return }
        let linksByBuilding = Dictionary(grouping: clientLinks) { $0.buildingId.lowercased() }
        let addressesById: [String: AddressFeature] = Dictionary(uniqueKeysWithValues: (addresses?.features ?? []).compactMap { feature -> (String, AddressFeature)? in
            guard let id = feature.properties.id ?? feature.id else { return nil }
            return (id.lowercased(), feature)
        })

        if let currentBuildings = buildings {
            let updatedFeatures = currentBuildings.features.map { feature -> BuildingFeature in
                let candidates = feature.properties.buildingIdentifierCandidates.map { $0.lowercased() }
                let links = candidates.flatMap { linksByBuilding[$0] ?? [] }
                guard !links.isEmpty else { return feature }

                let linkedAddresses = links.compactMap { addressesById[$0.addressId.lowercased()] }
                let addressIds = Array(Set(feature.properties.addressIds + links.map(\.addressId))).sorted()
                let firstAddress = linkedAddresses.first
                let bestConfidence = max(
                    feature.properties.confidence ?? 0,
                    links.map(\.confidence).max() ?? 0
                )
                let bestMatch = links.sorted { $0.confidence > $1.confidence }.first?.matchType
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
            buildings = BuildingFeatureCollection(type: currentBuildings.type, features: updatedFeatures)
        }

        if let currentAddresses = addresses {
            let buildingByAddress = Dictionary(uniqueKeysWithValues: clientLinks.map { ($0.addressId.lowercased(), $0.buildingId) })
            let updatedAddresses = currentAddresses.features.map { feature -> AddressFeature in
                guard let id = feature.properties.id ?? feature.id,
                      let buildingId = buildingByAddress[id.lowercased()] else { return feature }
                let updatedProperties = AddressProperties(
                    id: feature.properties.id,
                    gersId: feature.properties.gersId,
                    buildingGersId: feature.properties.buildingGersId ?? buildingId,
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
            addresses = AddressFeatureCollection(type: currentAddresses.type, features: updatedAddresses)
        }

        storeCurrentFeatureSnapshot(campaignId: campaignId)
    }
    
    // MARK: - Real-time Updates
    
    /// Update a building's status (for real-time QR scan updates)
    func updateBuildingStatus(gersId: String, status: String, scansTotal: Int) {
        guard let buildings = self.buildings else { return }
        
        // Find and update the feature
        if buildings.features.contains(where: { feature in
            feature.properties.buildingIdentifierCandidates.contains(where: {
                $0.caseInsensitiveCompare(gersId) == .orderedSame
            }) || feature.id?.caseInsensitiveCompare(gersId) == .orderedSame
        }) {
            // Note: In a real implementation, you'd create a mutable copy
            // For now, we'll refetch to get updated data
            print("🔄 [MapFeatures] Building \(gersId) status updated to: \(status), scans: \(scansTotal)")
        }
    }
    
    // MARK: - Helpers
    
    /// Center coordinate for the current campaign features (from first building or address)
    /// Used to fly the map camera to the campaign area.
    func campaignCenterCoordinate() -> CLLocationCoordinate2D? {
        // Prefer first building polygon centroid
        if let buildings = buildings, let first = buildings.features.first {
            let geom = first.geometry
            if let poly = geom.asPolygon, let firstRing = poly.first, let firstPoint = firstRing.first, firstPoint.count >= 2 {
                return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
            }
            if let multi = geom.asMultiPolygon, let firstPoly = multi.first, let firstRing = firstPoly.first, let firstPoint = firstRing.first, firstPoint.count >= 2 {
                return CLLocationCoordinate2D(latitude: firstPoint[1], longitude: firstPoint[0])
            }
        }
        // Fallback: first address point
        if let addresses = addresses, let first = addresses.features.first {
            let geom = first.geometry
            if let point = geom.asPoint, point.count >= 2 {
                return CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
            }
        }
        return nil
    }
    
    /// Convert GeoJSON to Data for Mapbox source
    func buildingsAsGeoJSONData() -> Data? {
        guard let buildings = buildings else { return nil }
        return try? JSONEncoder().encode(buildings)
    }
    
    func addressesAsGeoJSONData() -> Data? {
        guard let addresses = addresses else { return nil }
        return try? JSONEncoder().encode(addresses)
    }

    func parcelsAsGeoJSONData() -> Data? {
        guard let parcels = parcels else { return nil }
        return try? JSONEncoder().encode(parcels)
    }
    
    func roadsAsGeoJSONData() -> Data? {
        guard let roads = roads else { return nil }
        return try? JSONEncoder().encode(roads)
    }
    
    /// Build GeoJSON coordinates from array
    private func buildGeoJSONCoordinates(from coordinates: [[Double]]) -> GeoJSONCoordinatesNode {
        do {
            let data = try JSONSerialization.data(withJSONObject: coordinates)
            return try JSONDecoder().decode(GeoJSONCoordinatesNode.self, from: data)
        } catch {
            print("⚠️ [MapFeatures] Failed to build coordinates: \(error)")
            return try! JSONDecoder().decode(GeoJSONCoordinatesNode.self, from: "[]".data(using: .utf8)!)
        }
    }
}
