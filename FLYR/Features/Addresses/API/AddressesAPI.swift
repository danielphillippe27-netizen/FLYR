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
    
    /// Fetch building polygons for specific campaign address IDs
    /// - Parameter addressIds: Array of campaign_addresses.id UUIDs
    /// - Returns: GeoJSON FeatureCollection with building polygons
    func fetchBuildingPolygons(addressIds: [UUID]) async throws -> GeoJSONFeatureCollection {
        guard !addressIds.isEmpty else {
            return GeoJSONFeatureCollection(features: [])
        }
        
        print("🏠 [ADDRESSES] Fetching building polygons for \(addressIds.count) address IDs")
        
        let idStrings = addressIds.map { $0.uuidString }
        let res = try await client
            .rpc("get_buildings_by_address_ids", params: ["p_address_ids": idStrings])
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
    ///   - p_polygon_geojson (jsonb): The polygon geometry as GeoJSON
    ///   - p_campaign_id (uuid, optional): Campaign ID to filter results
    ///   And return rows from campaign_addresses_v view with PostGIS ST_Within/ST_Contains query
    func fetchAddressesInPolygon(polygonGeoJSON: String, campaignId: UUID?) async throws -> [CampaignAddressViewRow] {
        print("🔍 [ADDRESSES] Fetching addresses in polygon (campaignId: \(campaignId?.uuidString ?? "none"))")
        
        // Parse GeoJSON to validate format
        guard let geoJSONData = polygonGeoJSON.data(using: .utf8),
              let geoJSONDict = try? JSONSerialization.jsonObject(with: geoJSONData) as? [String: Any],
              geoJSONDict["type"] as? String == "Polygon" else {
            throw NSError(
                domain: "AddressesAPI",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Invalid GeoJSON Polygon format"]
            )
        }
        
        // Build RPC parameters
        var params: [String: AnyCodable] = [
            "p_polygon_geojson": AnyCodable(geoJSONDict)
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
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let addresses = try decoder.decode([CampaignAddressViewRow].self, from: res.data)
            print("✅ [ADDRESSES] Found \(addresses.count) addresses in polygon")
            return addresses
            
        } catch {
            // If RPC doesn't exist, provide helpful error message
            if let error = error as? NSError,
               let errorDescription = error.userInfo[NSLocalizedDescriptionKey] as? String,
               errorDescription.contains("function") || errorDescription.contains("does not exist") {
                print("⚠️ [ADDRESSES] RPC '\(rpcName)' not found in Supabase. Please create the RPC function.")
                print("⚠️ [ADDRESSES] Expected RPC signature:")
                print("⚠️ [ADDRESSES]   - p_polygon_geojson (jsonb)")
                if campaignId != nil {
                    print("⚠️ [ADDRESSES]   - p_campaign_id (uuid)")
                }
                print("⚠️ [ADDRESSES] Should return rows from campaign_addresses_v view")
                throw NSError(
                    domain: "AddressesAPI",
                    code: 404,
                    userInfo: [NSLocalizedDescriptionKey: "RPC '\(rpcName)' not found. Please create the Supabase RPC function to query addresses within a polygon using PostGIS ST_Within or ST_Contains."]
                )
            }
            
            print("❌ [ADDRESSES] Error fetching addresses in polygon: \(error)")
            throw error
        }
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
