import Foundation
import Combine
import CoreLocation

@MainActor
final class UseCreateCampaign: ObservableObject {
    @Published var isCreating = false
    @Published var isPreparingRoads = false
    @Published var preparationProgress: String = ""
    @Published var error: String?
    
    func createV2(payload: CampaignCreatePayloadV2, store: CampaignV2Store, polygon: [CLLocationCoordinate2D]? = nil) async -> CampaignV2? {
        print("🎣 [HOOK DEBUG] UseCreateCampaign.createV2 called")
        print("🎣 [HOOK DEBUG] Payload name: '\(payload.name)'")
        print("🎣 [HOOK DEBUG] Payload type: \(payload.type?.rawValue ?? "nil")")
        print("🎣 [HOOK DEBUG] Address count: \(payload.addressesJSON.count)")
        
        isCreating = true
        defer { 
            isCreating = false
            print("🎣 [HOOK DEBUG] UseCreateCampaign.createV2 completed")
        }
        
        do {
            print("🎣 [HOOK DEBUG] Calling CampaignsAPI.shared.createV2...")
            let created = try await CampaignsAPI.shared.createV2(payload)
            print("🎣 [HOOK DEBUG] API call successful, appending to store...")
            store.append(created)
            print("✅ [HOOK DEBUG] Campaign created and added to store successfully")
            
            // Prepare campaign roads if polygon is provided
            if let polygon = polygon, !polygon.isEmpty {
                await prepareCampaignRoads(campaignId: created.id.uuidString, polygon: polygon)
            }
            
            return created
        } catch {
            print("❌ [HOOK DEBUG] Campaign creation failed: \(error)")
            self.error = "\(error)"
            return nil
        }
    }
    
    func create(draft: CampaignDraft, store: CampaignV2Store, polygon: [CLLocationCoordinate2D]? = nil) async -> CampaignV2? {
        print("🎣 [HOOK DEBUG] UseCreateCampaign.create called (legacy)")
        print("🎣 [HOOK DEBUG] Draft name: '\(draft.name)'")
        print("🎣 [HOOK DEBUG] Draft type: \(draft.type.rawValue)")
        print("🎣 [HOOK DEBUG] Address count: \(draft.addresses.count)")
        
        isCreating = true
        defer { 
            isCreating = false
            print("🎣 [HOOK DEBUG] UseCreateCampaign.create completed")
        }
        
        do {
            print("🎣 [HOOK DEBUG] Calling CampaignsAPI.shared.createV2 with draft...")
            let created = try await CampaignsAPI.shared.createV2(draft)
            print("🎣 [HOOK DEBUG] API call successful, appending to store...")
            store.append(created)
            print("✅ [HOOK DEBUG] Legacy campaign created and added to store successfully")
            
            // Prepare campaign roads if polygon is provided
            if let polygon = polygon, !polygon.isEmpty {
                await prepareCampaignRoads(campaignId: created.id.uuidString, polygon: polygon)
            }
            
            return created
        } catch {
            print("❌ [HOOK DEBUG] Legacy campaign creation failed: \(error)")
            self.error = "\(error)"
            return nil
        }
    }
    
    // MARK: - Campaign Road Preparation
    
    private func prepareCampaignRoads(campaignId: String, polygon: [CLLocationCoordinate2D]) async {
        print("🛣️ [CampaignCreation] Preparing campaign roads for \(campaignId)")
        isPreparingRoads = true
        preparationProgress = "Fetching roads..."
        
        let bounds = BoundingBox(from: polygon)
        print("🛣️ [CampaignCreation] Fetching roads from Mapbox for bounds: lat(\(bounds.minLat)-\(bounds.maxLat)), lon(\(bounds.minLon)-\(bounds.maxLon))")
        
        do {
            let corridors = try await CampaignRoadService.shared.prepareCampaignRoads(
                campaignId: campaignId,
                bounds: bounds,
                polygon: polygon
            )
            
            preparationProgress = "Caching roads..."
            
            // Also mirror to local cache for offline use
            await CampaignRoadService.shared.ensureLocalCache(campaignId: campaignId)
            
            print("✅ [CampaignRoadService] Stored \(corridors.count) roads in Supabase for campaign \(campaignId)")
            print("✅ [CampaignCreation] Campaign ready with \(corridors.count) roads cached")
            preparationProgress = "\(corridors.count) roads ready"
            
        } catch {
            print("❌ [CampaignCreation] Failed to prepare roads: \(error)")
            preparationProgress = "Road preparation failed"
            // Don't fail campaign creation if road prep fails - it can be retried later
        }
        
        isPreparingRoads = false
    }
}
