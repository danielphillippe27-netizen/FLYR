import Foundation
import CoreLocation
import Combine

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
}

/// GeoJSON FeatureCollection for map feature RPCs
struct MapFeatureGeoJSONFeatureCollection<P: Codable>: Codable {
    let type: String
    let features: [MapFeatureGeoJSONFeature<P>]
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

typealias RoadFeature = MapFeatureGeoJSONFeature<RoadProperties>
typealias RoadFeatureCollection = MapFeatureGeoJSONFeatureCollection<RoadProperties>

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

// MARK: - Map Features Service

/// Service for fetching map features (buildings, addresses, roads) from Supabase
@MainActor
final class MapFeaturesService: ObservableObject {
    static let shared = MapFeaturesService()
    
    private let supabase = SupabaseClientShim()
    
    @Published var buildings: BuildingFeatureCollection?
    @Published var addresses: AddressFeatureCollection?
    @Published var roads: RoadFeatureCollection?
    @Published var isLoading = false
    @Published var error: Error?

    /// Silver linking table: gers_id (lowercase) → [address_id UUIDs].
    /// Populated from building_address_links whenever buildings are fetched.
    /// Used by resolveAddressForBuilding as the primary strategy for Silver S3 buildings.
    @Published var silverBuildingLinks: [String: [String]] = [:]

    // Campaign-scoped prewarmed building polygons (e.g. Quick Start ensure response before DB links are ready).
    private var prewarmedBuildingsByCampaign: [String: BuildingFeatureCollection] = [:]
    /// Tracks latest campaign fetch so stale async responses are ignored.
    private var activeCampaignRequestId: UUID?
    private var activeCampaignIdLower: String?
    private let campaignRepository = CampaignRepository.shared
    
    private init() {}

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
        guard let requestId else { return true }
        return activeCampaignRequestId == requestId && activeCampaignIdLower == campaignId.lowercased()
    }

    func isScopedToCampaign(_ campaignId: String) -> Bool {
        activeCampaignIdLower == campaignId.lowercased()
    }

    func primeBuildingPolygons(campaignId: String, features: [GeoJSONFeature]) {
        let collection = buildingFeatureCollectionFromGeoJSON(GeoJSONFeatureCollection(features: features))
        guard !collection.features.isEmpty else { return }
        prewarmedBuildingsByCampaign[campaignId.lowercased()] = collection
        print("✅ [MapFeatures] Primed \(collection.features.count) prewarmed building polygons for campaign \(campaignId)")
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
            self.buildings = result
            print("✅ [MapFeatures] Loaded \(result.features.count) building features")
            
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
            
            self.buildings = result
            print("✅ [MapFeatures] Loaded \(result.features.count) buildings in viewport")
            
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
    
    /// Max addresses to use for closest-home building fallback.
    /// Set high enough to cover large Silver campaigns (e.g. Texas 832) when S3 snapshot is unavailable.
    private static let fallbackAddressCap = 400
    
    /// Fetch all map features for a campaign (buildings, addresses, roads).
    ///
    /// Building source priority (handled server-side by /api/campaigns/{id}/buildings):
    ///   1. Gold  — rpc_get_campaign_full_features (building_id FK set)
    ///   2. Silver DB — rpc_get_campaign_full_features (building_address_links + buildings table)
    ///   3. S3 snapshot — Lambda-generated buildings.geojson.gz (always present for Lambda campaigns)
    ///
    /// Addresses always come from rpc_get_campaign_addresses (enriched with building links + status IDs).
    func fetchAllCampaignFeatures(campaignId: String) async {
        let campaignIdLower = campaignId.lowercased()
        let isRefreshingSameCampaign = activeCampaignIdLower == campaignIdLower
        let requestId = UUID()
        activeCampaignRequestId = requestId
        activeCampaignIdLower = campaignIdLower
        isLoading = true
        error = nil

        // Keep existing features visible when reloading the same campaign (for example after adding
        // a manual home) so the map never collapses to empty while refresh requests are in flight.
        // We still clear immediately when switching to a different campaign.
        if !isRefreshingSameCampaign {
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
            self.addresses = AddressFeatureCollection(type: "FeatureCollection", features: [])
            self.roads = RoadFeatureCollection(type: "FeatureCollection", features: [])
            self.silverBuildingLinks = [:]
        }

        if let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
           isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) {
            self.buildings = cachedBundle.buildings
            self.addresses = cachedBundle.addresses
            self.roads = cachedBundle.roads
            self.silverBuildingLinks = cachedBundle.silverBuildingLinks
            isLoading = false
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
            }
            isLoading = false
            return
        }
        
        // Fetch the core campaign map data in parallel.
        // Buildings go through the backend API which routes Gold → Silver DB → S3 automatically.
        // Addresses come from DB (enriched with building link IDs and status metadata).
        // Silver links (building_address_links) are fetched directly — used by the iOS tap resolver
        // when Gold address_id is absent (i.e. Silver S3 buildings whose features don't carry address_id).
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.fetchBuildingsFromAPI(campaignId: campaignId, requestId: requestId)
            }
            group.addTask {
                await self.fetchCampaignAddresses(campaignId: campaignId, requestId: requestId)
            }
            group.addTask {
                await self.fetchSilverBuildingLinks(campaignId: campaignId, requestId: requestId)
            }
            group.addTask {
                await self.fetchCampaignRoads(campaignId: campaignId, requestId: requestId)
            }
        }

        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
        
        // Use prewarmed polygons (from Quick Start ensureBuildingPolygons) if API returned nothing.
        // This covers the window between campaign creation and when the S3 snapshot is available.
        if (self.buildings?.features.isEmpty ?? true),
           let prewarmed = prewarmedBuildingsByCampaign[campaignId.lowercased()],
           !prewarmed.features.isEmpty {
            self.buildings = prewarmed
            print("✅ [MapFeatures] Using prewarmed building polygons (\(prewarmed.features.count)) for campaign \(campaignId)")
        }
        
        // Last resort: Edge Function per-address lookup when S3 snapshot is also unavailable.
        if (self.buildings?.features.isEmpty ?? true) && (addresses?.features.isEmpty == false) {
            await fetchBuildingsForAddressesFallback(campaignId: campaignId, requestId: requestId)
        }

        // If the campaign still has no buildings or addresses, replay the same polygon-backed
        // create flow used by NewCampaignScreen: generate-address-list -> provision -> reload.
        if (self.buildings?.features.isEmpty ?? true) && (self.addresses?.features.isEmpty ?? true) {
            await replayCampaignCreationPathIfNeeded(campaignId: campaignId, requestId: requestId)
        }
        
        isLoading = false
    }

    /// Fetch route-scoped features from the backend assignment map endpoint.
    /// Falls back to full campaign loading if the scoped endpoint is unavailable.
    func fetchRouteScopedCampaignFeatures(assignmentId: UUID, campaignId: String) async {
        let campaignIdLower = campaignId.lowercased()
        let requestId = UUID()
        activeCampaignRequestId = requestId
        activeCampaignIdLower = campaignIdLower
        isLoading = true
        error = nil

        do {
            let payload = try await RouteAssignmentsAPI.shared.fetchAssignmentMap(assignmentId: assignmentId)
            await applyRouteScopedPayload(payload, assignmentId: assignmentId, campaignId: campaignId, requestId: requestId)
        } catch {
            if isCancellationError(error) {
                print("ℹ️ [MapFeatures] Route-scoped request cancelled")
                return
            }

            if case RouteAssignmentsAPIError.unauthorized = error {
                print("⚠️ [MapFeatures] Route-scoped load returned unauthorized; retrying once before full fallback")
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                    let payload = try await RouteAssignmentsAPI.shared.fetchAssignmentMap(assignmentId: assignmentId)
                    await applyRouteScopedPayload(payload, assignmentId: assignmentId, campaignId: campaignId, requestId: requestId)
                    isLoading = false
                    return
                } catch {
                    if isCancellationError(error) {
                        print("ℹ️ [MapFeatures] Route-scoped retry cancelled")
                        return
                    }
                    print("⚠️ [MapFeatures] Route-scoped retry failed (\(error))")
                }
            }

            print("⚠️ [MapFeatures] Route-scoped load failed (\(error)); falling back to full campaign data")
            await fetchAllCampaignFeatures(campaignId: campaignId)
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

        self.buildings = payload.buildings
        self.addresses = payload.addresses
        self.roads = RoadFeatureCollection(type: "FeatureCollection", features: [])

        print(
            "✅ [MapFeatures] Loaded route-scoped map for assignment \(assignmentId.uuidString) " +
            "buildings=\(payload.buildings.features.count) addresses=\(payload.addresses.features.count)"
        )

    }
    
    /// Fetch building polygons from the backend API.
    /// The server handles routing: Gold (RPC) → Silver DB (RPC) → S3 snapshot.
    /// This is always the authoritative source — no client-side Silver fallback needed.
    private func fetchBuildingsFromAPI(campaignId: String, requestId: UUID? = nil) async {
        do {
            let features = try await BuildingLinkService.shared.fetchBuildings(campaignId: campaignId)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: features)
            await campaignRepository.upsertBuildings(campaignId: campaignId, features: features)
            print("✅ [MapFeatures] Loaded \(features.count) building features from API (Gold/Silver/S3)")
        } catch {
            if isCancellationError(error) {
                print("ℹ️ [MapFeatures] Buildings API request cancelled")
                return
            }
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            if self.buildings?.features.isEmpty == false {
                print("⚠️ [MapFeatures] API buildings fetch failed (\(error)); keeping existing buildings")
            } else {
                print("⚠️ [MapFeatures] API buildings fetch failed (\(error)); buildings will be empty")
                self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
            }
        }
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

        do {
            _ = try await OvertureAddressService.shared.getAddressesInPolygon(
                polygonGeoJSON: polygonGeoJSON,
                campaignId: campaignUUID
            )
        } catch {
            print("⚠️ [MapFeatures] generate-address-list replay failed: \(error.localizedDescription)")
        }

        do {
            _ = try await CampaignsAPI.shared.provisionCampaign(campaignId: campaignUUID)
            let state = try await CampaignsAPI.shared.waitForProvisionReady(
                campaignId: campaignUUID,
                timeoutSeconds: 45,
                pollIntervalSeconds: 2
            )
            print("✅ [MapFeatures] Replay provision finished with status \(state.provisionStatus ?? "unknown")")
        } catch {
            print("⚠️ [MapFeatures] provision replay failed: \(error.localizedDescription)")
        }

        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.fetchBuildingsFromAPI(campaignId: campaignId, requestId: requestId)
            }
            group.addTask {
                await self.fetchCampaignAddresses(campaignId: campaignId, requestId: requestId)
            }
            group.addTask {
                await self.fetchSilverBuildingLinks(campaignId: campaignId, requestId: requestId)
            }
        }

        // If provision still has not yielded polygons, try the address-driven building fallback once more.
        if (self.buildings?.features.isEmpty ?? true) && (addresses?.features.isEmpty == false) {
            await fetchBuildingsForAddressesFallback(campaignId: campaignId, requestId: requestId)
        }
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
    
    /// Fetch building_address_links for the campaign and build a gers_id → [address_id] lookup.
    /// Used by resolveAddressForBuilding as the authoritative source for Silver S3 campaigns
    /// where buildings arrive without address_id embedded in their GeoJSON properties.
    private func fetchSilverBuildingLinks(campaignId: String, requestId: UUID? = nil) async {
        do {
            let links = try await BuildingLinkService.shared.fetchLinks(campaignId: campaignId)
            guard !links.isEmpty else { return }
            var dict: [String: [String]] = [:]
            for link in links {
                let key = link.buildingId.lowercased()
                dict[key, default: []].append(link.addressId)
            }
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            self.silverBuildingLinks = dict
            await campaignRepository.upsertBuildingAddressLinks(campaignId: campaignId, links: links)
            print("✅ [MapFeatures] Loaded \(links.count) Silver building links (\(dict.count) unique buildings)")
        } catch {
            print("⚠️ [MapFeatures] Silver links fetch failed (\(error))")
        }
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
    
    /// Fetch building polygons for campaigns that have addresses but no buildings (e.g. closest-home).
    /// Calls Edge Function to ensure building_polygons, then RPC to load them, and merges into buildings layer.
    private func fetchBuildingsForAddressesFallback(campaignId: String, requestId: UUID? = nil) async {
        guard let addresses = addresses, !addresses.features.isEmpty else { return }
        
        let addressRows = campaignAddressRowsFromAddressFeatures(addresses.features, cap: Self.fallbackAddressCap)
        guard !addressRows.isEmpty else { return }
        
        do {
            print("🗺️ [MapFeatures] Closest-home fallback: ensuring building polygons for \(addressRows.count) addresses")
            let ensureResponse = try await BuildingsAPI.shared.ensureBuildingPolygons(addresses: addressRows)
            var immediateCollection: BuildingFeatureCollection?

            // If edge function returned features directly, render those immediately.
            if let ensureFeatures = ensureResponse.features, !ensureFeatures.isEmpty {
                let immediate = buildingFeatureCollectionFromGeoJSON(GeoJSONFeatureCollection(features: ensureFeatures))
                if !immediate.features.isEmpty {
                    immediateCollection = immediate
                    guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
                    self.buildings = immediate
                    prewarmedBuildingsByCampaign[campaignId.lowercased()] = immediate
                    print("✅ [MapFeatures] Immediate ensure render loaded \(immediate.features.count) building features")
                }
            }

            // Prefer address-id fetch first (works immediately after ensureBuildingPolygons),
            // then fallback to campaign fetch/snapshot path.
            let addressIds = addressRows.map(\.id)
            var collection = try await BuildingsAPI.shared.fetchBuildingPolygons(addressIds: addressIds)
            if collection.features.isEmpty, let campaignUUID = UUID(uuidString: campaignId) {
                collection = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignUUID)
            }
            
            let buildingCollection = buildingFeatureCollectionFromGeoJSON(collection)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            if !buildingCollection.features.isEmpty {
                self.buildings = buildingCollection
            } else if let immediateCollection, !immediateCollection.features.isEmpty {
                self.buildings = immediateCollection
            } else {
                self.buildings = buildingCollection
            }
            print("✅ [MapFeatures] Fallback loaded \(buildingCollection.features.count) building features")

            if !buildingCollection.features.isEmpty {
                prewarmedBuildingsByCampaign[campaignId.lowercased()] = buildingCollection
            }
        } catch {
            if isCancellationError(error) {
                print("ℹ️ [MapFeatures] Fallback buildings fetch cancelled")
                return
            }
            print("❌ [MapFeatures] Fallback buildings fetch failed: \(error)")
            // Leave buildings empty; map still shows addresses
        }
    }
    
    /// Convert address features (from rpc_get_campaign_addresses) to CampaignAddressRow for BuildingsAPI.
    private func campaignAddressRowsFromAddressFeatures(_ features: [AddressFeature], cap: Int) -> [CampaignAddressRow] {
        var rows: [CampaignAddressRow] = []
        for feature in features.prefix(cap) {
            guard let point = feature.geometry.asPoint, point.count >= 2 else { continue }
            let idString = feature.id ?? feature.properties.id ?? ""
            guard let id = UUID(uuidString: idString) else { continue }
            let lon = point[0]
            let lat = point[1]
            let formatted = feature.properties.formatted ?? ""
            rows.append(CampaignAddressRow(id: id, formatted: formatted, lat: lat, lon: lon))
        }
        return rows
    }
    
    /// Convert GeoJSON feature collection from get_buildings_by_address_ids to BuildingFeatureCollection for the map layer.
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
        let fallbackId = (str("building_id") ?? str("gers_id") ?? feature.id ?? UUID().uuidString).lowercased()
        let rawGersId = str("gers_id") ?? str("building_id") ?? feature.id ?? UUID().uuidString
        return BuildingProperties(
            id: str("building_id") ?? str("id") ?? fallbackId,
            buildingId: str("building_id"),
            addressId: str("address_id"),
            gersId: rawGersId.lowercased(),
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
            qrScanned: bool("qr_scanned")
        )
    }
    
    /// Fetch addresses for a campaign
    private func fetchCampaignAddresses(campaignId: String, requestId: UUID? = nil) async {
        do {
            guard let campaignUUID = UUID(uuidString: campaignId) else {
                print("❌ [MapFeatures] Invalid campaign ID format for addresses: \(campaignId)")
                return
            }
            let data = try await supabase.callRPCData(
                "rpc_get_campaign_addresses",
                params: ["p_campaign_id": campaignUUID.uuidString]
            )
            let result: AddressFeatureCollection = try decodeFeatureCollection(data)
            guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
            self.addresses = result
            await campaignRepository.upsertAddresses(campaignId: campaignId, features: result.features)
            print("✅ [MapFeatures] Loaded \(result.features.count) addresses for campaign")
        } catch {
            print("❌ [MapFeatures] Error fetching campaign addresses: \(error)")
        }
    }
    
    /// Load roads from local cache first, then refresh from the existing campaign road service.
    func fetchCampaignRoads(campaignId: String, requestId: UUID? = nil) async {
        if let cachedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId),
           isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) {
            self.roads = cachedBundle.roads
        }

        let corridors = await CampaignRoadService.shared.getRoadsForSession(campaignId: campaignId)
        await campaignRepository.upsertRoads(campaignId: campaignId, corridors: corridors)
        guard isActiveCampaignRequest(campaignId: campaignId, requestId: requestId) else { return }
        if let refreshedBundle = await campaignRepository.getCampaignMapBundle(campaignId: campaignId) {
            self.roads = refreshedBundle.roads
        }
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
