import Foundation
import SwiftUI
import Combine

// MARK: - Campaign Buildings Hook

/// Hook for fetching and managing building polygons for campaign addresses
@MainActor
class UseCampaignBuildings: ObservableObject {
    @Published var featureCollection: GeoJSONFeatureCollection?
    @Published var isLoading = false
    @Published var error: String?
    
    private let campaignId: UUID
    private let addresses: [CampaignAddress]
    private let token: String
    
    init(campaignId: UUID, addresses: [CampaignAddress], token: String) {
        self.campaignId = campaignId
        self.addresses = addresses
        self.token = token
    }
    
    /// Fetch missing building polygons for all addresses
    func fetchMissingBuildings() async {
        print("🏢 [HOOK] Starting snapshot-based building fetch for campaign \(campaignId)")
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let rawCollection = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignId)
            let polygonFeatures = rawCollection.features.filter { feature in
                feature.geometry.type == "Polygon" || feature.geometry.type == "MultiPolygon"
            }
            self.featureCollection = GeoJSONFeatureCollection(features: polygonFeatures)
            print("✅ [HOOK] Loaded \(featureCollection?.features.count ?? 0) snapshot polygons (filtered from \(rawCollection.features.count) features)")
        } catch {
            print("❌ [HOOK] Failed to load snapshot buildings: \(error)")
            self.error = "Failed to load campaign buildings: \(error.localizedDescription)"
        }
    }
    
    /// Refresh building polygons (re-fetch from cache)
    func refreshBuildings() async {
        print("🏢 [HOOK] Refreshing building polygons")
        do {
            let rawCollection = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignId)
            self.featureCollection = GeoJSONFeatureCollection(features: rawCollection.features.filter {
                $0.geometry.type == "Polygon" || $0.geometry.type == "MultiPolygon"
            })
            print("✅ [HOOK] Refreshed \(featureCollection?.features.count ?? 0) building polygons")
        } catch {
            print("❌ [HOOK] Failed to refresh buildings: \(error)")
            self.error = "Failed to refresh buildings: \(error.localizedDescription)"
        }
    }
    
    /// Refresh building polygons for a specific set of addresses
    /// - Parameter addresses: Array of CampaignAddress to fetch polygons for
    func refreshBuildings(for addresses: [CampaignAddress]) async {
        print("🏢 [HOOK] Refreshing building polygons for \(addresses.count) addresses")
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            let rawCollection = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignId)
            
            // Filter to only polygon geometries to prevent FillBucket errors
            let polygonFeatures = rawCollection.features.filter { feature in
                feature.geometry.type == "Polygon" || feature.geometry.type == "MultiPolygon"
            }
            
            self.featureCollection = GeoJSONFeatureCollection(features: polygonFeatures)
            print("✅ [HOOK] Refreshed \(featureCollection?.features.count ?? 0) building polygons (filtered from \(rawCollection.features.count) total features)")
        } catch {
            print("❌ [HOOK] Failed to refresh buildings: \(error)")
            self.error = "Failed to refresh buildings: \(error.localizedDescription)"
        }
    }
    
    /// Clear all building data
    func clearBuildings() {
        featureCollection = nil
        error = nil
    }
}
