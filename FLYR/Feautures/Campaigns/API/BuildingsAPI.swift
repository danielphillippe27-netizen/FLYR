import Foundation
import CoreLocation
import Supabase

// MARK: - Buildings API Errors

enum BuildingsAPIError: Error {
    case missingToken
    case badURL
    case requestFailed
    case decodeFailed
    case noFeatures
    case notAuthenticated
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .missingToken:
            return "Mapbox access token not found"
        case .badURL:
            return "Invalid URL for Mapbox Tilequery API"
        case .requestFailed:
            return "Request to Mapbox Tilequery API failed"
        case .decodeFailed:
            return "Failed to decode response from Mapbox Tilequery API"
        case .noFeatures:
            return "No building features found for the given location"
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Edge Function Vector Tiles Decode Models

struct AddressPayload: Codable {
    let id: String
    let lat: Double
    let lon: Double
    let formatted: String?  // Add for fallback FK resolution
}

struct EnsureRequest: Codable {
    let addresses: [AddressPayload]
    let zoom: Int?          // optional, default 16
    let searchRadiusM: Int? // optional, default 50
    let retryRadiusM: Int?  // optional, default 75
    let maxTilesPerAddr: Int? // optional, default 5
}

struct PerAddressResult: Codable {
    let id: String
    let status: String  // "matched" | "proxy"
    let reason: String? // optional
}

struct EnsureResponse: Codable {
    let matched: Int
    let proxies: Int
    let created: Int
    let updated: Int
    let addresses: Int
    let total_ms: Int
    let per_addr_ms: Int
    let zoom: Int
    let searchRadiusM: Int
    let retryRadiusM: Int
    let maxTilesPerAddr: Int?
    let style_used: Bool?
    let results: [PerAddressResult]? // optional for backward compat
    let features: [GeoJSONFeature]? // optional: features for immediate rendering
}

// MARK: - RPC Response Decoders

/// RPC row returned by get_buildings_by_address_ids
struct RpcRow: Decodable {
    let address_id: UUID
    let geom_geom: String? // PostGIS geometry (may be null or serialized)
    let geom: GeoJSONFeatureOrCollection? // JSONB GeoJSON Feature or FeatureCollection (optional in case of decode issues)
}

/// Flexible decoder for GeoJSON that can be a Feature, FeatureCollection, or raw JSON
enum GeoJSONFeatureOrCollection: Decodable {
    case featureCollection(GeoJSONFeatureCollection)
    case feature(GeoJSONFeature)
    case raw(AnyCodable)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Strategy 1: Try direct decode as FeatureCollection first
        if let collection = try? container.decode(GeoJSONFeatureCollection.self) {
            self = .featureCollection(collection)
            return
        }
        
        // Strategy 2: Try direct decode as Feature
        if let feature = try? container.decode(GeoJSONFeature.self) {
            self = .feature(feature)
            return
        }
        
        // Strategy 3: Decode as raw JSON object (Postgres JSONB)
        // Use JSONSerialization to handle nested structures properly
        do {
            // Try to get the raw JSON object
            if let jsonObject = try? container.decode(AnyCodable.self) {
                // If it's a dictionary, try to convert it
                if let dict = jsonObject.value as? [String: Any] {
                    // Convert to JSON data
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else {
                        self = .raw(jsonObject)
                        return
                    }
                    
                    // Try to decode as Feature or FeatureCollection
                    let jsonDecoder = JSONDecoder()
                    
                    // Check type field
                    if let typeValue = dict["type"] as? String {
                        if typeValue == "FeatureCollection" {
                            if let collection = try? jsonDecoder.decode(GeoJSONFeatureCollection.self, from: jsonData) {
                                self = .featureCollection(collection)
                                return
                            }
                        } else if typeValue == "Feature" {
                            if let feature = try? jsonDecoder.decode(GeoJSONFeature.self, from: jsonData) {
                                self = .feature(feature)
                                return
                            }
                        }
                    }
                    
                    // Couldn't decode, store as raw
                    self = .raw(jsonObject)
                    return
                }
                
                // Not a dictionary, store as raw
                self = .raw(jsonObject)
                return
            }
        }
        
        // Strategy 4: Try decoding as dictionary with AnyCodable values
        if let dict = try? container.decode([String: AnyCodable].self) {
            // Convert to regular dictionary
            let jsonDict = dict.mapValues { $0.value }
            
            // Convert to JSON data
            guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict) else {
                self = .raw(AnyCodable(jsonDict))
                return
            }
            
            let jsonDecoder = JSONDecoder()
            
            // Check type field
            if let typeValue = dict["type"]?.value as? String {
                if typeValue == "FeatureCollection" {
                    if let collection = try? jsonDecoder.decode(GeoJSONFeatureCollection.self, from: jsonData) {
                        self = .featureCollection(collection)
                        return
                    }
                } else if typeValue == "Feature" {
                    if let feature = try? jsonDecoder.decode(GeoJSONFeature.self, from: jsonData) {
                        self = .feature(feature)
                        return
                    }
                }
            }
            
            // Couldn't decode, store as raw
            self = .raw(AnyCodable(jsonDict))
            return
        }
        
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unable to decode GeoJSON - not a Feature, FeatureCollection, or valid JSON object"
        )
    }
}

/// Wrapper for RPC responses that may be wrapped in { data: [...] }
struct RpcRowsWrapper<T: Decodable>: Decodable {
    let data: T
}

/// Decode RPC rows from response data (handles both array and wrapped formats)
func decodeRpcRows(_ data: Data) throws -> [RpcRow] {
    let decoder = JSONDecoder()
    
    // Try wrapped format first { data: [...] }
    if let wrapped = try? decoder.decode(RpcRowsWrapper<[RpcRow]>.self, from: data) {
        return wrapped.data
    }
    
    // Try direct array format [...]
    return try decoder.decode([RpcRow].self, from: data)
}

// MARK: - Buildings API

final class BuildingsAPI {
    static let shared = BuildingsAPI()
    private init() {}
    
    private var token: String {
        Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
    }
    
    private var supabaseClient: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    // MARK: - Building Outline
    
    /// Fetch building polygon outline for a given address using Mapbox Tilequery API
    func buildingOutline(for address: AddressCandidate, radiusMeters: Int = 25) async throws -> [[CLLocationCoordinate2D]]? {
        guard !token.isEmpty else { throw BuildingsAPIError.missingToken }
        
        let urlString = "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/\(address.coordinate.longitude),\(address.coordinate.latitude).json?radius=\(radiusMeters)&layers=building&access_token=\(token)"
        
        guard let url = URL(string: urlString) else { throw BuildingsAPIError.badURL }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BuildingsAPIError.requestFailed
        }
        
        struct TilequeryResponse: Decodable {
            struct Feature: Decodable {
                let id: String?
                let properties: [String: FeatureValue]
                let geometry: Geometry
                
                enum FeatureValue: Decodable {
                    case string(String)
                    case number(Double)
                    case boolean(Bool)
                    case null
                    
                    init(from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        if let stringValue = try? container.decode(String.self) {
                            self = .string(stringValue)
                        } else if let numberValue = try? container.decode(Double.self) {
                            self = .number(numberValue)
                        } else if let boolValue = try? container.decode(Bool.self) {
                            self = .boolean(boolValue)
                        } else {
                            self = .null
                        }
                    }
                }
                
                struct Geometry: Decodable {
                    let type: String
                    let coordinates: [[[Double]]] // Polygon coordinates
                }
            }
            let features: [Feature]
        }
        
        do {
            let decoded = try JSONDecoder().decode(TilequeryResponse.self, from: data)
            
            // Find the first polygon feature
            guard let polygonFeature = decoded.features.first(where: { $0.geometry.type == "Polygon" }) else {
                return nil // No building polygon found
            }
            
            // Convert coordinates to CLLocationCoordinate2D
            let rings = polygonFeature.geometry.coordinates.map { ring in
                ring.map { coord in
                    CLLocationCoordinate2D(
                        latitude: coord[1],
                        longitude: coord[0]
                    )
                }
            }
            
            return rings
        } catch {
            throw BuildingsAPIError.decodeFailed
        }
    }
    
    // MARK: - Pro Mode Vector Tiles Decode
    
    /// Ensure building polygons are cached for given addresses via Edge Function
    /// - Parameter addresses: Array of CampaignAddressRow with id, lat, lon
    /// - Returns: EnsureResponse with statistics and timing info
    func ensureBuildingPolygons(addresses: [CampaignAddressRow]) async throws -> EnsureResponse {
        guard !addresses.isEmpty else {
            // Return empty response with defaults
            return EnsureResponse(
                matched: 0, proxies: 0, created: 0, updated: 0,
                addresses: 0, total_ms: 0, per_addr_ms: 0,
                zoom: 16, searchRadiusM: 50, retryRadiusM: 75, maxTilesPerAddr: 5,
                style_used: nil, results: nil, features: nil
            )
        }
        
        // Verify authentication
        do {
            _ = try await supabaseClient.auth.session
        } catch {
            throw BuildingsAPIError.notAuthenticated
        }
        
        // Chunk addresses to 40 per call (keep existing chunking logic)
        let chunkSize = 40
        var totalCreated = 0
        var totalUpdated = 0
        var totalProxies = 0
        var totalMatched = 0
        var totalTimeMs = 0
        
        for chunkIndex in stride(from: 0, to: addresses.count, by: chunkSize) {
            let chunk = Array(addresses[chunkIndex..<min(chunkIndex + chunkSize, addresses.count)])
            
            // Prepare request payload
            let addrPayloads = chunk.map { addr in
                AddressPayload(id: addr.id.uuidString, lat: addr.lat, lon: addr.lon, formatted: addr.formatted)
            }
            let req = EnsureRequest(
                addresses: addrPayloads,
                zoom: 15,
                searchRadiusM: 50,
                retryRadiusM: 75,
                maxTilesPerAddr: 4
            )
            
            print("🏗️ [BUILDINGS] Ensuring polygons for chunk \(chunkIndex / chunkSize + 1), \(chunk.count) addresses")
            
            do {
                // Call Edge Function - use URLSession with authenticated request
                let supabaseURLString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as! String
                let supabaseKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as! String
                let url = URL(string: "\(supabaseURLString)/functions/v1/tiledecode_buildings")!
                
                print("🔗 [BUILDINGS] Calling MVT decode endpoint: \(url.absoluteString)")
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // Get auth token
                let session = try await supabaseClient.auth.session
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(supabaseKey, forHTTPHeaderField: "apikey")
                
                // Encode request body
                request.httpBody = try JSONEncoder().encode(req)
                
                // Log request payload for debugging
                if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                    print("📤 [BUILDINGS] Request payload: \(bodyString.prefix(200))...")
                }
                
                // Make request
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ [BUILDINGS] Invalid response type")
                    throw BuildingsAPIError.requestFailed
                }
                
                print("📥 [BUILDINGS] Response status: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    if let errorString = String(data: data, encoding: .utf8) {
                        print("❌ [BUILDINGS] Edge Function error response: \(errorString)")
                    }
                    throw BuildingsAPIError.requestFailed
                }
                
                let decoder = JSONDecoder()
                let result = try decoder.decode(EnsureResponse.self, from: data)
                
                // Debug: Log features received
                print("📦 [FEATURES DEBUG] Received features count: \(result.features?.count ?? 0)")
                if let firstFeature = result.features?.first {
                    print("📦 [FEATURES DEBUG] First geometry type: \(firstFeature.geometry.type)")
                    if let addressId = firstFeature.properties["address_id"]?.value as? String {
                        print("📦 [FEATURES DEBUG] First feature address_id: \(addressId)")
                    }
                }
                
                totalCreated += result.created
                totalUpdated += result.updated
                totalProxies += result.proxies
                totalMatched += result.matched
                totalTimeMs += result.total_ms
                
                print("✅ [BUILDINGS] Chunk processed: \(result.matched)/\(result.addresses) matched, \(result.proxies) proxies, \(result.total_ms)ms total (\(result.per_addr_ms)ms/addr)")
                
            } catch {
                print("❌ [BUILDINGS] Error processing chunk: \(error)")
                // Count chunk as proxies (no polygons found)
                totalProxies += chunk.count
            }
        }
        
        // Return aggregated response
        let avgTimePerAddr = addresses.count > 0 ? totalTimeMs / addresses.count : 0
        return EnsureResponse(
            matched: totalMatched,
            proxies: totalProxies,
            created: totalCreated,
            updated: totalUpdated,
            addresses: addresses.count,
            total_ms: totalTimeMs,
            per_addr_ms: avgTimePerAddr,
            zoom: 16,
            searchRadiusM: 50,
            retryRadiusM: 75,
            maxTilesPerAddr: 5,
            style_used: nil, // Aggregated from chunks - could be enhanced to track
            results: nil, // Aggregated from chunks - could be enhanced to track
            features: nil // Aggregated from chunks - could be enhanced to track
        )
    }
    
    /// Fetch building polygons from database for given address IDs
    /// - Parameter addressIds: Array of campaign_addresses.id UUIDs
    /// - Returns: GeoJSON FeatureCollection with building polygons
    func fetchBuildingPolygons(addressIds: [UUID]) async throws -> GeoJSONFeatureCollection {
        guard !addressIds.isEmpty else {
            return GeoJSONFeatureCollection(features: [])
        }
        
        print("🏠 [BUILDINGS] Fetching building polygons for \(addressIds.count) address IDs")
        
        // Use Supabase client directly - pass UUIDs directly (SDK handles uuid[] conversion)
        let ids: [UUID] = addressIds
        let response = try await supabaseClient.rpc(
            "get_buildings_by_address_ids",
            params: ["p_address_ids": ids]
        ).execute()
        
        // Log raw response for debugging
        if let text = String(data: response.data, encoding: .utf8) {
            print("🔎 [RPC RAW] \(text.prefix(500))")
        }
        
        // Decode RPC table response (array of rows with address_id, geom_geom, geom)
        let rows = try decodeRpcRows(response.data)
        print("📦 [FEATURES DEBUG] rows: \(rows.count)")
        
        // Convert rows to GeoJSONFeatureCollection
        var features: [GeoJSONFeature] = []
        for row in rows {
            guard let geom = row.geom else {
                print("⚠️ [BUILDINGS] Skipping row with null geom for address_id=\(row.address_id)")
                continue
            }
            
            switch geom {
            case .feature(let feature):
                // Add address_id to properties if not already present
                var props = feature.properties
                props["address_id"] = AnyCodable(row.address_id.uuidString)
                let enhancedFeature = GeoJSONFeature(
                    id: feature.id,
                    geometry: feature.geometry,
                    properties: props
                )
                features.append(enhancedFeature)
            case .featureCollection(let collection):
                // Extract features from collection and add address_id
                for feature in collection.features {
                    var props = feature.properties
                    props["address_id"] = AnyCodable(row.address_id.uuidString)
                    let enhancedFeature = GeoJSONFeature(
                        id: feature.id,
                        geometry: feature.geometry,
                        properties: props
                    )
                    features.append(enhancedFeature)
                }
            case .raw:
                // Skip raw JSON that we can't decode
                print("⚠️ [BUILDINGS] Skipping raw JSON for address_id=\(row.address_id)")
            }
        }
        
        let polygonCount = features.filter { feature in
            feature.geometry.type == "Polygon" || feature.geometry.type == "MultiPolygon"
        }.count
        print("✅ [BUILDINGS] Loaded \(features.count) features (\(polygonCount) polygons)")
        
        return GeoJSONFeatureCollection(features: features)
    }
}
