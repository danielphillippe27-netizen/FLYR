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
        print("🏢 [HOOK] Starting building fetch for campaign \(campaignId)")
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        let sem = AsyncSemaphore(limit: 6)
        
        await withTaskGroup(of: Void.self) { group in
            for address in addresses where address.needsBuilding {
                group.addTask {
                    await sem.wait()
                    
                    defer {
                        Task {
                            await sem.signal()
                        }
                    }
                    
                    guard let coord = address.coordinate else {
                        print("⚠️ [HOOK] No coordinate for address: \(address.address)")
                        return
                    }
                    
                    do {
                        if let (buildingId, geometry) = try await MapboxBuildingsAPI.shared.fetchBestBuildingPolygon(
                            coord: coord,
                            token: self.token
                        ) {
                            try await AddressesAPI.shared.upsertAddressBuilding(
                                formatted: address.address,
                                postal: nil, // CampaignAddress doesn't have postalCode
                                buildingId: buildingId,
                                geojson: geometry
                            )
                            print("✅ [HOOK] Cached building for \(address.address)")
                        } else {
                            print("ℹ️ [HOOK] No building found for \(address.address)")
                        }
                    } catch {
                        print("⚠️ [HOOK] Failed to fetch building for \(address.address): \(error)")
                        // Continue with other addresses - don't fail the entire operation
                    }
                }
            }
        }
        
        // Fetch complete FeatureCollection after all updates
        do {
            print("🏢 [HOOK] Loading complete FeatureCollection")
            let rawCollection = try await AddressesAPI.shared.fetchCampaignBuildingsGeoJSON(
                campaignId: campaignId
            )
            
            // Filter to only polygon geometries to prevent FillBucket errors
            let polygonFeatures = rawCollection.features.filter { feature in
                feature.geometry.type == "Polygon" || feature.geometry.type == "MultiPolygon"
            }
            
            self.featureCollection = GeoJSONFeatureCollection(features: polygonFeatures)
            print("✅ [HOOK] Loaded \(featureCollection?.features.count ?? 0) building polygons (filtered from \(rawCollection.features.count) total features)")
        } catch {
            print("❌ [HOOK] Failed to load FeatureCollection: \(error)")
            self.error = "Failed to load buildings: \(error.localizedDescription)"
        }
    }
    
    /// Refresh building polygons (re-fetch from cache)
    func refreshBuildings() async {
        print("🏢 [HOOK] Refreshing building polygons")
        do {
            self.featureCollection = try await AddressesAPI.shared.fetchCampaignBuildingsGeoJSON(
                campaignId: campaignId
            )
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
            let addressIds = addresses.map { $0.id }
            let rawCollection = try await AddressesAPI.shared.fetchBuildingPolygons(addressIds: addressIds)
            
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
