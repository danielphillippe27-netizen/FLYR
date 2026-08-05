import Foundation
import Supabase

// MARK: - Addresses API for Building Cache Management

/// API for managing building polygon cache via Supabase
final class AddressesAPI {
    static let shared = AddressesAPI()
    private init() {}
    
    private let client = SupabaseManager.shared.client
    
    /// Cache building polygon by formatted address + postal code
    /// - Parameters:
    ///   - formatted: Formatted address string
    ///   - postal: Postal code (optional)
    ///   - buildingId: Mapbox building ID
    ///   - geojson: Building geometry as dictionary
    func upsertAddressBuilding(
        formatted: String,
        postal: String?,
        buildingId: String,
        geojson: [String: Any]
    ) async throws {
        print("💾 [DB] upsert_address_building_by_formatted '\(formatted)' | '\(postal ?? "")' id=\(buildingId)")
        
        let params: [String: AnyCodable] = [
            "p_formatted": AnyCodable(formatted),
            "p_postal": AnyCodable(postal ?? ""),
            "p_building_id": AnyCodable(buildingId),
            "p_building_source": AnyCodable("mapbox.buildings"),
            "p_geojson": AnyCodable([
                "type": "Feature",
                "geometry": geojson,
                "properties": [:] as [String: String]
            ])
        ]
        
        do {
            _ = try await client.rpc("upsert_address_building_by_formatted", params: params).execute()
            print("✅ [ADDRESSES] Building cached successfully for \(formatted)")
        } catch {
            print("❌ [ADDRESSES] Failed to cache building for \(formatted): \(error)")
            throw error
        }
    }
    
    /// Fetch complete FeatureCollection of buildings for a campaign
    /// - Parameter campaignId: Campaign UUID
    /// - Returns: GeoJSON FeatureCollection with building polygons
    func fetchCampaignBuildingsGeoJSON(campaignId: UUID) async throws -> GeoJSONFeatureCollection {
        print("🏠 [ADDRESSES] Fetching building polygons for campaign \(campaignId)")
        
        let res = try await client
            .rpc("get_campaign_buildings_geojson", params: ["p_campaign_id": campaignId.uuidString])
            .execute()
        
        do {
            let featureCollection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: res.data)
            print("✅ [ADDRESSES] Loaded \(featureCollection.features.count) building polygons")
            return featureCollection
        } catch {
            print("❌ [ADDRESSES] Failed to decode FeatureCollection: \(error)")
            throw error
        }
    }
    
    /// Fetch building polygons for specific campaign address IDs or campaign
    /// - Parameters:
    ///   - campaignId: Campaign UUID (preferred - queries buildings table)
    ///   - addressIds: Array of campaign_addresses.id UUIDs (fallback)
    /// - Returns: GeoJSON FeatureCollection with building polygons
    func fetchBuildingPolygons(campaignId: UUID? = nil, addressIds: [UUID] = []) async throws -> GeoJSONFeatureCollection {
        // Delegate to BuildingsAPI which has the updated logic
        return try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignId, addressIds: addressIds)
    }
    
    /// Check if an address already has a cached building polygon
    /// - Parameters:
    ///   - formatted: Formatted address string
    ///   - postal: Postal code (optional)
    /// - Returns: True if building exists in cache
    func hasCachedBuilding(formatted: String, postal: String?) async throws -> Bool {
        // This could be implemented as a separate RPC if needed
        // For now, we'll use the optimistic approach (always try to fetch)
        return false
    }
    
    /// Fetch addresses within a polygon using PostGIS spatial query
    /// - Parameters:
    ///   - polygonGeoJSON: GeoJSON Polygon string (e.g., {"type": "Polygon", "coordinates": [[[lon, lat], ...]]})
    ///   - campaignId: Optional campaign ID to filter addresses (if nil, queries all addresses)
    /// - Returns: Array of CampaignAddressViewRow matching addresses
    /// - Note: Requires Supabase RPC function `get_addresses_in_polygon` or `get_campaign_addresses_in_polygon`
    ///   The RPC should accept:
    ///   - p_polygon_geojson (text): The polygon geometry as GeoJSON
    ///   - p_campaign_id (uuid, optional): Campaign ID to filter results
    ///   And return rows matching CampaignAddressViewRow with a geom_json column.
    func fetchAddressesInPolygon(polygonGeoJSON: String, campaignId: UUID?) async throws -> [CampaignAddressViewRow] {
        print("🔍 [ADDRESSES] Fetching addresses in polygon (campaignId: \(campaignId?.uuidString ?? "none"))")
        
        // Accept either a raw Polygon geometry or a Feature wrapping a Polygon geometry.
        // Pass the original string through to the RPC because wrapping a raw `[String: Any]`
        // inside `AnyCodable` fails to encode nested Foundation arrays.
        guard let normalizedPolygonGeoJSON = Self.normalizedPolygonGeoJSON(from: polygonGeoJSON) else {
            throw NSError(
                domain: "AddressesAPI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON Polygon format"]
            )
        }
        
        // Build RPC parameters
        var params: [String: AnyCodable] = [
            "p_polygon_geojson": AnyCodable(normalizedPolygonGeoJSON)
        ]
        
        // Add campaign ID if provided
        if let campaignId = campaignId {
            params["p_campaign_id"] = AnyCodable(campaignId.uuidString)
        }
        
        // Determine RPC name based on whether campaign ID is provided
        let rpcName = campaignId != nil ? "get_campaign_addresses_in_polygon" : "get_addresses_in_polygon"
        
        do {
            let res = try await client.rpc(rpcName, params: params).execute()
            
            // Decode response as array of CampaignAddressViewRow
            let decoder = JSONDecoder.supabaseDates
            let addresses = try decoder.decode([CampaignAddressViewRow].self, from: res.data)
            print("✅ [ADDRESSES] Found \(addresses.count) addresses in polygon")
            return addresses
            
        } catch {
            // If RPC doesn't exist, provide helpful error message
            let error = error as NSError
            if let errorDescription = error.userInfo[NSLocalizedDescriptionKey] as? String,
               errorDescription.contains("function") || errorDescription.contains("does not exist") {
                print("⚠️ [ADDRESSES] RPC '\(rpcName)' not found in Supabase. Please create the RPC function.")
                print("⚠️ [ADDRESSES] Expected RPC signature:")
                print("⚠️ [ADDRESSES]   - p_polygon_geojson (text)")
                if campaignId != nil {
                    print("⚠️ [ADDRESSES]   - p_campaign_id (uuid)")
                }
                print("⚠️ [ADDRESSES] Should return rows matching CampaignAddressViewRow")
                throw NSError(
                    domain: "AddressesAPI",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "RPC '\(rpcName)' not found. Please create the Supabase RPC function to query addresses within a polygon using PostGIS ST_Covers or ST_Contains."]
                )
            }
            
            print("❌ [ADDRESSES] Error fetching addresses in polygon: \(error)")
            throw error
        }
    }

    private static func normalizedPolygonGeoJSON(from polygonGeoJSON: String) -> String? {
        guard let geoJSONData = polygonGeoJSON.data(using: .utf8),
              let geoJSONDict = try? JSONSerialization.jsonObject(with: geoJSONData) as? [String: Any] else {
            return nil
        }

        if geoJSONDict["type"] as? String == "Polygon" {
            return polygonGeoJSON
        }

        if geoJSONDict["type"] as? String == "Feature",
           let geometry = geoJSONDict["geometry"] as? [String: Any],
           geometry["type"] as? String == "Polygon" {
            guard let geometryData = try? JSONSerialization.data(withJSONObject: geometry),
                  let geometryString = String(data: geometryData, encoding: .utf8) else {
                return nil
            }
            return geometryString
        }

        return nil
    }
}

// MARK: - Campaign Address Extensions

extension CampaignAddress {
    /// Whether this address needs a building polygon fetched
    /// Using optimistic approach - always try (idempotent upsert)
    var needsBuilding: Bool {
        return true
    }
}
