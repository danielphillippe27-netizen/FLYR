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
    
    enum CodingKeys: String, CodingKey {
        case id
        case gersId = "gers_id"
        case buildingGersId = "building_gers_id"
        case houseNumber = "house_number"
        case streetName = "street_name"
        case postalCode = "postal_code"
        case locality
        case formatted
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

    // Campaign-scoped prewarmed building polygons (e.g. Quick Start ensure response before DB links are ready).
    private var prewarmedBuildingsByCampaign: [String: BuildingFeatureCollection] = [:]
    
    private init() {}

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
    
    /// Fetch roads in a bounding box
    func fetchRoadsInBbox(
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
            
            print("🗺️ [MapFeatures] Fetching roads in bbox")
            
            let result: RoadFeatureCollection = try await supabase.callRPC(
                "rpc_get_roads_in_bbox",
                params: params
            )
            
            self.roads = result
            print("✅ [MapFeatures] Loaded \(result.features.count) roads")
            
        } catch {
            print("❌ [MapFeatures] Error fetching roads: \(error)")
        }
    }
    
    // MARK: - Campaign All Features (Buildings + Addresses + Roads)
    
    /// Max addresses to use for closest-home building fallback (avoid excessive Edge Function calls)
    private static let fallbackAddressCap = 50
    
    /// Fetch all map features for a campaign (buildings, addresses, roads)
    func fetchAllCampaignFeatures(campaignId: String) async {
        isLoading = true
        error = nil
        
        // Clear to empty so any updateMapData() before fetch completes gets polygon-only/empty (avoids stale data and FillBucket LineString)
        self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: [])
        self.addresses = AddressFeatureCollection(type: "FeatureCollection", features: [])
        self.roads = RoadFeatureCollection(type: "FeatureCollection", features: [])
        
        // Fetch in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.fetchCampaignFullFeatures(campaignId: campaignId)
            }
            group.addTask {
                await self.fetchCampaignAddresses(campaignId: campaignId)
            }
            group.addTask {
                await self.fetchCampaignRoads(campaignId: campaignId)
            }
        }
        
        // Partition Gold RPC result: Polygon -> buildings, Point -> merge into addresses
        if let buildings = self.buildings, !buildings.features.isEmpty {
            let (polygons, points) = partitionFeaturesByGeometry(buildings.features)
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: polygons)
            let pointAddressFeatures = addressFeaturesFromPointBuildingFeatures(points)
            if !pointAddressFeatures.isEmpty {
                let merged = mergeAddressFeatures(existing: self.addresses, additional: pointAddressFeatures)
                self.addresses = AddressFeatureCollection(type: "FeatureCollection", features: merged)
            }
        }

        // If campaign RPC only returned address points, use prewarmed polygons captured during ensureBuildingPolygons.
        if (self.buildings?.features.isEmpty ?? true),
           let prewarmed = prewarmedBuildingsByCampaign[campaignId.lowercased()],
           !prewarmed.features.isEmpty {
            self.buildings = prewarmed
            print("✅ [MapFeatures] Using prewarmed building polygons (\(prewarmed.features.count)) for campaign \(campaignId)")
        }
        
        // Silver fallback: if no polygon buildings, try S3 snapshot
        if (buildings?.features.isEmpty ?? true), let silverFeatures = try? await BuildingLinkService.shared.fetchBuildings(campaignId: campaignId) {
            self.buildings = BuildingFeatureCollection(type: "FeatureCollection", features: silverFeatures)
            print("✅ [MapFeatures] Silver fallback loaded \(silverFeatures.count) building features")
        }
        
        // Closest-home: if we still have no buildings but have addresses, fetch buildings per address via Edge Function
        if (buildings?.features.isEmpty ?? true) && (addresses?.features.isEmpty == false) {
            await fetchBuildingsForAddressesFallback(campaignId: campaignId)
        }
        
        isLoading = false
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
                formatted: formatted.isEmpty ? nil : formatted
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
    private func fetchBuildingsForAddressesFallback(campaignId: String) async {
        guard let addresses = addresses, !addresses.features.isEmpty else { return }
        
        let addressRows = campaignAddressRowsFromAddressFeatures(addresses.features, cap: Self.fallbackAddressCap)
        guard !addressRows.isEmpty else { return }
        
        do {
            print("🗺️ [MapFeatures] Closest-home fallback: ensuring building polygons for \(addressRows.count) addresses")
            let ensureResponse = try await BuildingsAPI.shared.ensureBuildingPolygons(addresses: addressRows)

            // If edge function returned features directly, render those immediately.
            if let ensureFeatures = ensureResponse.features, !ensureFeatures.isEmpty {
                let immediate = buildingFeatureCollectionFromGeoJSON(GeoJSONFeatureCollection(features: ensureFeatures))
                if !immediate.features.isEmpty {
                    self.buildings = immediate
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
            self.buildings = buildingCollection
            print("✅ [MapFeatures] Fallback loaded \(buildingCollection.features.count) building features")

            if !buildingCollection.features.isEmpty {
                prewarmedBuildingsByCampaign[campaignId.lowercased()] = buildingCollection
            }
        } catch {
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
        let fallbackId = (feature.id ?? UUID().uuidString).lowercased()
        let rawGersId = str("gers_id") ?? feature.id ?? UUID().uuidString
        return BuildingProperties(
            id: str("id") ?? fallbackId,
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
    private func fetchCampaignAddresses(campaignId: String) async {
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
            self.addresses = result
            print("✅ [MapFeatures] Loaded \(result.features.count) addresses for campaign")
        } catch {
            print("❌ [MapFeatures] Error fetching campaign addresses: \(error)")
        }
    }
    
    /// Fetch roads for a campaign
    func fetchCampaignRoads(campaignId: String) async {
        do {
            guard let campaignUUID = UUID(uuidString: campaignId) else {
                print("❌ [MapFeatures] Invalid campaign ID format for roads: \(campaignId)")
                return
            }
            let data = try await supabase.callRPCData(
                "rpc_get_campaign_roads",
                params: ["p_campaign_id": campaignUUID.uuidString]
            )
            let result: RoadFeatureCollection = try decodeFeatureCollection(data)
            self.roads = result
            print("✅ [MapFeatures] Loaded \(result.features.count) roads for campaign")
        } catch {
            print("❌ [MapFeatures] Error fetching campaign roads: \(error)")
        }
    }
    
    // MARK: - Real-time Updates
    
    /// Update a building's status (for real-time QR scan updates)
    func updateBuildingStatus(gersId: String, status: String, scansTotal: Int) {
        guard var buildings = self.buildings else { return }
        
        // Find and update the feature
        if let index = buildings.features.firstIndex(where: { $0.properties.gersId == gersId }) {
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
}
