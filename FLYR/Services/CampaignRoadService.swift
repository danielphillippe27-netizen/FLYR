import Foundation
import CoreLocation
import Supabase
import Auth

// MARK: - Types

/// Status of campaign road preparation
enum CampaignRoadStatus: String, Codable, Sendable {
    case pending = "pending"
    case fetching = "fetching"
    case ready = "ready"
    case failed = "failed"
}

/// Metadata for campaign road cache
struct CampaignRoadMetadata: Codable, Sendable {
    let campaignId: String
    let status: CampaignRoadStatus
    let roadCount: Int
    let cacheVersion: Int
    let corridorBuildVersion: Int
    let fetchedAt: Date?
    let expiresAt: Date?
    let ageDays: Double?
    let isStale: Bool
    let lastErrorMessage: String?
    let source: String
    
    enum CodingKeys: String, CodingKey {
        case campaignId = "campaign_id"
        case status = "roads_status"
        case roadCount = "road_count"
        case cacheVersion = "cache_version"
        case corridorBuildVersion = "corridor_build_version"
        case fetchedAt = "fetched_at"
        case expiresAt = "expires_at"
        case ageDays = "age_days"
        case isStale = "is_stale"
        case lastErrorMessage = "last_error_message"
        case source
    }
}

/// A campaign road record from Supabase
struct CampaignRoadRecord: Codable, Sendable {
    let id: String
    let roadId: String
    let roadName: String?
    let roadClass: String?
    let geometry: RoadGeometry
    let cacheVersion: Int
    let corridorBuildVersion: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case roadId = "road_id"
        case roadName = "road_name"
        case roadClass = "road_class"
        case geometry
        case cacheVersion = "cache_version"
        case corridorBuildVersion = "corridor_build_version"
    }
}

struct RoadGeometry: Codable, Sendable {
    let type: String
    let coordinates: [[Double]] // [[lon, lat], ...]
}

/// Bounding box for area queries
struct BoundingBox: Sendable {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double
    
    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
    }
    
    var diagonalMeters: Double {
        let sw = CLLocation(latitude: minLat, longitude: minLon)
        let ne = CLLocation(latitude: maxLat, longitude: maxLon)
        return sw.distance(from: ne)
    }
    
    init(minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }
    
    init(from polygon: [CLLocationCoordinate2D]) {
        let lats = polygon.map { $0.latitude }
        let lons = polygon.map { $0.longitude }
        self.minLat = lats.min() ?? 0
        self.maxLat = lats.max() ?? 0
        self.minLon = lons.min() ?? 0
        self.maxLon = lons.max() ?? 0
    }
}

// MARK: - Campaign Road Service

/// Service for campaign-scoped road management.
/// 
/// Responsibilities:
/// - Fetch roads from Mapbox for campaign area
/// - Normalize and store in Supabase (canonical store)
/// - Update campaign road metadata
/// - Support manual refresh
/// - Support device-side preload for offline use
@MainActor
final class CampaignRoadService {
    static let shared = CampaignRoadService()
    
    private let supabase = SupabaseClientShim()
    private let mapboxProvider: RoadGeometryProvider
    private var inFlightSessionRoadFetches: [String: Task<[StreetCorridor], Never>] = [:]
    
    private init() {
        self.mapboxProvider = EdgeFunctionRoadGeometryProvider()
    }
    
    // MARK: - Public API
    
    /// Prepare roads for a campaign (fetch from Mapbox, store in Supabase)
    /// Call this when campaign is created or when manual refresh is requested.
    /// Pass the campaign polygon so roads are clipped to the actual territory boundary.
    func prepareCampaignRoads(
        campaignId: String,
        bounds: BoundingBox,
        polygon: [CLLocationCoordinate2D]? = nil
    ) async throws -> [StreetCorridor] {
        print("🛣️ [CampaignRoadService] Preparing roads for campaign \(campaignId)")
        print("🛣️ [CampaignRoadService] Bounds: lat(\(bounds.minLat)-\(bounds.maxLat)), lon(\(bounds.minLon)-\(bounds.maxLon))")
        
        // Set status to fetching
        do {
            try await updateStatus(campaignId: campaignId, status: .fetching)
        } catch {
            print("⚠️ [CampaignRoadService] Failed to mark roads as fetching: \(error)")
        }
        
        do {
            // Fetch from Mapbox, clipped to polygon when available
            let roads = try await mapboxProvider.fetchRoads(in: bounds, polygon: polygon)
            print("🛣️ [CampaignRoadService] Fetched \(roads.count) roads from Mapbox")
            
            guard !roads.isEmpty else {
                print("⚠️ [CampaignRoadService] No roads found in bounds")
                try await updateStatus(campaignId: campaignId, status: .failed, error: "No roads found in campaign area")
                return []
            }
            
            // Store in Supabase
            let result = try await storeRoadsInSupabase(
                campaignId: campaignId,
                roads: roads,
                bounds: bounds
            )
            
            print("✅ [CampaignRoadService] Stored \(result.roadCount) roads in Supabase (cache_version: \(result.cacheVersion))")
            
            // Also mirror to local cache for offline use
            await CampaignRoadDeviceCache.shared.store(roads: roads, campaignId: campaignId, version: result.cacheVersion)
            
            return roads
            
        } catch {
            print("❌ [CampaignRoadService] Failed to prepare roads: \(error)")
            do {
                try await updateStatus(campaignId: campaignId, status: .failed, error: String(describing: error))
            } catch {
                print("⚠️ [CampaignRoadService] Failed to mark roads as failed: \(error)")
            }
            throw error
        }
    }
    
    /// Refresh campaign roads (force re-fetch from Mapbox)
    func refreshCampaignRoads(
        campaignId: String,
        bounds: BoundingBox,
        polygon: [CLLocationCoordinate2D]? = nil
    ) async throws -> [StreetCorridor] {
        print("🛣️ [CampaignRoadService] Refreshing roads for campaign \(campaignId)")
        return try await prepareCampaignRoads(campaignId: campaignId, bounds: bounds, polygon: polygon)
    }
    
    /// Fetch campaign roads from Supabase (canonical source)
    func fetchCampaignRoadsFromSupabase(campaignId: String) async throws -> [StreetCorridor] {
        print("🛣️ [CampaignRoadService] Fetching roads from Supabase for campaign \(campaignId)")
        
        guard let campaignUUID = UUID(uuidString: campaignId) else {
            throw CampaignRoadError.invalidCampaignId
        }
        
        let data = try await supabase.callRPCData(
            "rpc_get_campaign_roads_v2",
            params: ["p_campaign_id": campaignUUID.uuidString]
        )
        
        let featureCollection = try JSONDecoder().decode(RoadFeatureCollection.self, from: data)
        
        // Convert to StreetCorridors
        let corridors = StreetCorridor.from(roadFeatures: featureCollection.features)
        
        print("✅ [CampaignRoadService] Loaded \(corridors.count) corridors from Supabase")
        return corridors
    }
    
    /// Get campaign road metadata
    func fetchCampaignRoadMetadata(campaignId: String) async throws -> CampaignRoadMetadata {
        guard let campaignUUID = UUID(uuidString: campaignId) else {
            throw CampaignRoadError.invalidCampaignId
        }
        
        let data = try await supabase.callRPCData(
            "rpc_get_campaign_road_metadata",
            params: ["p_campaign_id": campaignUUID.uuidString]
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CampaignRoadMetadata.self, from: data)
    }
    
    /// Check if roads are ready for a campaign
    func areRoadsReady(campaignId: String) async -> Bool {
        if let cached = await CampaignRoadDeviceCache.shared.load(campaignId: campaignId), !cached.isEmpty {
            return true
        }

        do {
            let metadata = try await fetchCampaignRoadMetadata(campaignId: campaignId)
            if metadata.status == .ready && metadata.roadCount > 0 {
                return true
            }
            if metadata.status == .failed && metadata.roadCount == 0 {
                return false
            }
        } catch {
            print("⚠️ [CampaignRoadService] Failed to read road metadata for readiness check: \(error)")
        }

        let corridors = await getRoadsForSession(campaignId: campaignId)
        return !corridors.isEmpty
    }
    
    /// Get roads for session (checks local cache first, falls back to Supabase)
    func getRoadsForSession(campaignId: String) async -> [StreetCorridor] {
        if let existingTask = inFlightSessionRoadFetches[campaignId] {
            return await existingTask.value
        }

        let task = Task<[StreetCorridor], Never> { [weak self] in
            guard let self else { return [] }
            // Check local cache first (fastest, works offline)
            if let cached = await CampaignRoadDeviceCache.shared.load(campaignId: campaignId) {
                let metadata = await CampaignRoadDeviceCache.shared.loadMetadata(campaignId: campaignId)
                print("✅ [CampaignRoadService] Loaded \(cached.count) roads from local cache (version: \(metadata?.cacheVersion ?? 0))")
                return cached
            }
            
            // Fall back to Supabase
            do {
                let corridors = try await self.fetchCampaignRoadsFromSupabase(campaignId: campaignId)
                
                // Mirror to local cache for next time
                if !corridors.isEmpty {
                    let metadata = try? await self.fetchCampaignRoadMetadata(campaignId: campaignId)
                    await CampaignRoadDeviceCache.shared.store(
                        corridors: corridors,
                        campaignId: campaignId,
                        version: metadata?.cacheVersion ?? 1
                    )
                }
                
                return corridors
            } catch {
                print("❌ [CampaignRoadService] Failed to load roads: \(error)")
                return []
            }
        }
        inFlightSessionRoadFetches[campaignId] = task
        let result = await task.value
        inFlightSessionRoadFetches[campaignId] = nil
        return result
    }
    
    /// Ensure roads are cached locally for offline use
    func ensureLocalCache(campaignId: String) async {
        // Check if already cached
        if let cached = await CampaignRoadDeviceCache.shared.load(campaignId: campaignId), !cached.isEmpty {
            return
        }
        
        // Fetch from Supabase and cache locally
        do {
            let corridors = try await fetchCampaignRoadsFromSupabase(campaignId: campaignId)
            let metadata = try? await fetchCampaignRoadMetadata(campaignId: campaignId)
            await CampaignRoadDeviceCache.shared.store(
                corridors: corridors,
                campaignId: campaignId,
                version: metadata?.cacheVersion ?? 1
            )
            print("✅ [CampaignRoadService] Mirrored \(corridors.count) roads to local cache")
        } catch {
            print("⚠️ [CampaignRoadService] Failed to mirror roads locally: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func storeRoadsInSupabase(
        campaignId: String,
        roads: [StreetCorridor],
        bounds: BoundingBox
    ) async throws -> (roadCount: Int, cacheVersion: Int) {
        guard let campaignUUID = UUID(uuidString: campaignId) else {
            throw CampaignRoadError.invalidCampaignId
        }

        // Deduplicate by geometry hash to avoid exact duplicates from overlapping tile edges.
        // We deliberately do NOT deduplicate by road_id here: when a road spans two adjacent
        // Mapbox tiles, both halves share the same feature ID but have different coordinate
        // arrays. Deduplicating by road_id would silently drop one half of those roads.
        // Instead we make the stored road_id unique per segment by appending a suffix.
        var seenGeometries = Set<String>()
        var roadIdCounts = [String: Int]()

        let dedupedRoads: [(corridor: StreetCorridor, uniqueId: String)] = roads.compactMap { corridor in
            let geoKey = corridor.polyline.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")
            guard seenGeometries.insert(geoKey).inserted else { return nil }

            let baseId = corridor.id ?? UUID().uuidString
            let count = roadIdCounts[baseId, default: 0]
            roadIdCounts[baseId] = count + 1
            // Suffix segments after the first so each row has a unique road_id in Supabase.
            let uniqueId = count == 0 ? baseId : "\(baseId)-\(count)"
            return (corridor, uniqueId)
        }

        if dedupedRoads.count < roads.count {
            print("🛣️ [CampaignRoadService] Removed \(roads.count - dedupedRoads.count) exact geometry duplicates before upsert")
        }

        let roadsPayload = dedupedRoads.map { item -> RoadUpsertItem in
            let corridor = item.corridor
            let bbox = Self.boundingBox(from: corridor.polyline)
            return RoadUpsertItem(
                road_id: item.uniqueId,
                road_name: corridor.roadName ?? "",
                road_class: corridor.roadClass ?? "residential",
                geom: RoadUpsertItem.Geom(
                    type: "LineString",
                    coordinates: corridor.polyline.map { [$0.longitude, $0.latitude] }
                ),
                bbox_min_lat: bbox.minLat,
                bbox_min_lon: bbox.minLon,
                bbox_max_lat: bbox.maxLat,
                bbox_max_lon: bbox.maxLon,
                source: "mapbox",
                source_version: "v1"
            )
        }

        let metadataPayload = RoadUpsertMetadata(
            bounds: RoadUpsertMetadata.Bounds(
                min_lat: bounds.minLat,
                min_lon: bounds.minLon,
                max_lat: bounds.maxLat,
                max_lon: bounds.maxLon
            ),
            corridor_build_version: 1
        )

        let params = RoadUpsertParams(
            p_campaign_id: campaignUUID.uuidString,
            p_roads: roadsPayload,
            p_metadata: metadataPayload
        )

        let response = try await supabase.client
            .rpc("rpc_upsert_campaign_roads", params: params)
            .execute()

        let decoded = try JSONDecoder().decode(UpsertResponse.self, from: response.data)
        return (decoded.roadCount, decoded.cacheVersion)
    }
    
    private func updateStatus(campaignId: String, status: CampaignRoadStatus, error: String? = nil) async throws {
        guard let campaignUUID = UUID(uuidString: campaignId) else {
            throw CampaignRoadError.invalidCampaignId
        }
        
        _ = try await supabase.callRPCData(
            "rpc_update_road_preparation_status",
            params: [
                "p_campaign_id": campaignUUID.uuidString,
                "p_status": status.rawValue,
                "p_error_message": error as Any
            ]
        )
    }
    
    private static func boundingBox(from coordinates: [CLLocationCoordinate2D]) -> (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double) {
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        return (
            minLat: lats.min() ?? 0,
            minLon: lons.min() ?? 0,
            maxLat: lats.max() ?? 0,
            maxLon: lons.max() ?? 0
        )
    }
}

// MARK: - RPC Param Types (Encodable structs to avoid AnyCodable nested-dict issues)

private struct RoadUpsertItem: Encodable {
    struct Geom: Encodable {
        let type: String
        let coordinates: [[Double]]
    }
    let road_id: String
    let road_name: String
    let road_class: String
    let geom: Geom
    let bbox_min_lat: Double
    let bbox_min_lon: Double
    let bbox_max_lat: Double
    let bbox_max_lon: Double
    let source: String
    let source_version: String
}

private struct RoadUpsertMetadata: Encodable {
    struct Bounds: Encodable {
        let min_lat: Double
        let min_lon: Double
        let max_lat: Double
        let max_lon: Double
    }
    let bounds: Bounds
    let corridor_build_version: Int
}

private struct RoadUpsertParams: Encodable {
    let p_campaign_id: String
    let p_roads: [RoadUpsertItem]
    let p_metadata: RoadUpsertMetadata
}

// MARK: - Response Types

private struct UpsertResponse: Codable {
    let success: Bool
    let roadCount: Int
    let cacheVersion: Int
    
    enum CodingKeys: String, CodingKey {
        case success
        case roadCount = "road_count"
        case cacheVersion = "cache_version"
    }
}

// MARK: - Errors

enum CampaignRoadError: Error {
    case invalidCampaignId
    case serializationError
    case mapboxError(String)
    case supabaseError(String)
}

// MARK: - Road Geometry Provider Protocol

protocol RoadGeometryProvider {
    func fetchRoads(in bounds: BoundingBox, polygon: [CLLocationCoordinate2D]?) async throws -> [StreetCorridor]
}

// MARK: - Edge Function Road Geometry Provider (MVT tiles → full LineStrings)

/// Fetches roads via Supabase Edge Function using only the drawn campaign polygon.
/// The edge function derives tile extent and clipping from the polygon (no bbox).
struct EdgeFunctionRoadGeometryProvider: RoadGeometryProvider {
    func fetchRoads(in bounds: BoundingBox, polygon: [CLLocationCoordinate2D]? = nil) async throws -> [StreetCorridor] {
        guard let baseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !baseURL.isEmpty,
              let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !anonKey.isEmpty else {
            throw CampaignRoadError.supabaseError("Missing Supabase URL or anon key")
        }
        guard let polygon = polygon, polygon.count >= 3 else {
            throw CampaignRoadError.supabaseError("Campaign polygon is required (at least 3 points)")
        }
        let url = URL(string: "\(baseURL.trimmingCharacters(in: .whitespacesAndNewlines))/functions/v1/tiledecode_roads")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let session = try await SupabaseManager.shared.client.auth.session
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        // Send bbox + polygon. The edge function uses bbox to determine tile coverage
        // and uses the polygon for precise clipping within those tiles.
        let body: [String: Any] = [
            "minLat": bounds.minLat,
            "minLon": bounds.minLon,
            "maxLat": bounds.maxLat,
            "maxLon": bounds.maxLon,
            "polygon": polygon.map { [$0.longitude, $0.latitude] },
            "zoom": 17
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw CampaignRoadError.supabaseError("Invalid response")
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CampaignRoadError.supabaseError(message)
        }
        let response = try JSONDecoder().decode(TiledecodeRoadsResponse.self, from: data)
        let corridors = StreetCorridor.from(roadFeatures: response.features)
        print("✅ [EdgeFunctionRoads] Fetched \(corridors.count) roads from MVT (from drawn polygon)")
        return corridors
    }
}

private struct TiledecodeRoadsResponse: Codable {
    let features: [RoadFeature]
}
