import Foundation
import Combine
import Supabase

// MARK: - Use Campaigns V2 Hook

@MainActor
final class UseCampaignsV2: ObservableObject {
    @Published var items: [CampaignV2] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let api: CampaignsV2APIType
    
    init(api: CampaignsV2APIType? = nil) {
        // Use real Supabase API by default instead of mock
        self.api = api ?? sharedV2API
    }
    
    func load(store: CampaignV2Store) {
        Task {
            await loadCampaigns(store: store)
        }
    }
    
    private func loadCampaigns(store: CampaignV2Store) async {
        isLoading = true
        error = nil
        let workspaceId = WorkspaceContext.shared.workspaceId
        do {
            let campaigns = try await api.fetchCampaigns(workspaceId: workspaceId)
            store.set(campaigns)
            items = campaigns
        } catch {
            if (error as NSError).code == NSURLErrorCancelled {
                isLoading = false
                return
            }
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Use Create Campaign V2 Hook

@MainActor
final class UseCreateCampaignV2: ObservableObject {
    @Published var isCreating = false
    @Published var error: String?
    
    private let api: CampaignsV2APIType
    
    init(api: CampaignsV2APIType? = nil) {
        // Use real Supabase API by default instead of mock
        self.api = api ?? sharedV2API
    }
    
    func create(draft: CampaignV2Draft, store: CampaignV2Store) async -> CampaignV2? {
        isCreating = true
        error = nil
        defer { isCreating = false }
        let workspaceId = WorkspaceContext.shared.workspaceId
        do {
            let campaign = try await api.createCampaign(draft, workspaceId: workspaceId)
            store.append(campaign)
            return campaign
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Use Campaign V2 Hook

@MainActor
final class UseCampaignV2: ObservableObject {
    @Published var item: CampaignV2?
    @Published var isLoading = false
    @Published var error: String?
    
    private let api: CampaignsV2APIType
    
    init(api: CampaignsV2APIType? = nil) {
        // Use real Supabase API by default instead of mock
        self.api = api ?? sharedV2API
    }
    
    func load(id: UUID, store: CampaignV2Store? = nil) {
        print("🎣 [HOOK DEBUG] UseCampaignV2.load called for ID: \(id)")
        Task {
            await loadCampaign(id: id, store: store)
        }
    }
    
    private func loadCampaign(id: UUID, store: CampaignV2Store? = nil) async {
        print("🎣 [HOOK DEBUG] Loading campaign with ID: \(id)")
        isLoading = true
        error = nil
        let isOnline = await MainActor.run { NetworkMonitor.shared.isOnline }
        
        // First check if campaign exists in the store with addresses loaded
        if let store = store, var campaign = store.campaign(id: id) {
            print("🎣 [HOOK DEBUG] Campaign found in store: '\(campaign.name)'")

            let needsRefresh =
                campaign.addresses.isEmpty ||
                campaign.dataConfidence == nil ||
                campaign.provisionStatus == nil ||
                campaign.provisionPhase == nil ||
                campaign.mapMode == nil ||
                campaign.buildingLinkConfidence == nil ||
                campaign.hasParcels == nil

            // Refresh from API if key derived data has not landed in memory yet.
            if needsRefresh && isOnline {
                let missingReasons = [
                    campaign.addresses.isEmpty ? "addresses" : nil,
                    campaign.dataConfidence == nil ? "data confidence" : nil,
                    campaign.provisionStatus == nil ? "provision status" : nil,
                    campaign.provisionPhase == nil ? "provision phase" : nil,
                    campaign.mapMode == nil ? "map mode" : nil,
                    campaign.buildingLinkConfidence == nil ? "building link confidence" : nil,
                    campaign.hasParcels == nil ? "parcel availability" : nil
                ]
                .compactMap { $0 }
                .joined(separator: " + ")

                print("🎣 [HOOK DEBUG] Campaign missing \(missingReasons), fetching fresh campaign...")
                do {
                    let fullCampaign = try await api.fetchCampaign(id: id)
                    campaign.addresses = fullCampaign.addresses
                    campaign.totalFlyers = fullCampaign.totalFlyers
                    campaign.dataConfidence = fullCampaign.dataConfidence
                    campaign.addressSource = fullCampaign.addressSource
                    campaign.type = fullCampaign.type
                    campaign.status = fullCampaign.status
                    campaign.seedQuery = fullCampaign.seedQuery
                    campaign.scans = fullCampaign.scans
                    campaign.conversions = fullCampaign.conversions
                    campaign.provisionStatus = fullCampaign.provisionStatus
                    campaign.provisionSource = fullCampaign.provisionSource
                    campaign.provisionPhase = fullCampaign.provisionPhase
                    campaign.addressesReadyAt = fullCampaign.addressesReadyAt
                    campaign.mapReadyAt = fullCampaign.mapReadyAt
                    campaign.optimizedAt = fullCampaign.optimizedAt
                    campaign.hasParcels = fullCampaign.hasParcels
                    campaign.buildingLinkConfidence = fullCampaign.buildingLinkConfidence
                    campaign.mapMode = fullCampaign.mapMode

                    // Update store with the refreshed campaign data
                    store.update(campaign)
                    item = campaign
                    print("🎣 [HOOK DEBUG] Refreshed campaign: \(campaign.addresses.count) addresses, confidence present: \(campaign.dataConfidence != nil)")
                } catch {
                    print("⚠️ [HOOK DEBUG] Failed to refresh campaign: \(error.localizedDescription)")
                    // Still show the store version if refresh fails.
                    item = campaign
                }
            } else {
                if needsRefresh && !isOnline {
                    print("📴 [HOOK DEBUG] Offline - using store campaign without refresh")
                }
                item = campaign
            }
            
            isLoading = false
            return
        }

        if !isOnline {
            print("📴 [HOOK DEBUG] Offline with no cached campaign in store")
            error = "Campaign details are unavailable offline until this campaign has been opened online."
            isLoading = false
            return
        }
        
        // Campaign not in store, fetch full campaign with addresses
        do {
            print("🎣 [HOOK DEBUG] Campaign not in store, calling API to fetch campaign...")
            let campaign = try await api.fetchCampaign(id: id)
            print("🎣 [HOOK DEBUG] Campaign fetched successfully: '\(campaign.name)' with \(campaign.addresses.count) addresses")
            
            // Update store if provided
            if let store = store {
                store.update(campaign)
            }
            
            item = campaign
        } catch {
            print("❌ [HOOK DEBUG] Failed to load campaign: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
        
        isLoading = false
        print("🎣 [HOOK DEBUG] Campaign loading completed")
    }
    
    func bumpProgress(store: CampaignV2Store, id: UUID, by step: Int = 1) {
        print("🎣 [HOOK DEBUG] Bumping scans for campaign \(id) by \(step)")
        
        guard var currentCampaign = store.campaign(id: id) else { 
            print("❌ [HOOK DEBUG] Campaign not found in store")
            return 
        }
        
        let oldScans = currentCampaign.scans
        let newScans = min(currentCampaign.totalFlyers, currentCampaign.scans + step)
        print("🎣 [HOOK DEBUG] Scans: \(oldScans) → \(newScans) (out of \(currentCampaign.totalFlyers))")
        
        currentCampaign.scans = newScans
        store.update(currentCampaign)
        
        // Update local item
        if var updatedItem = item, updatedItem.id == id {
            updatedItem.scans = newScans
            item = updatedItem
            print("🎣 [HOOK DEBUG] Local item updated with new scans")
        }
        
        // Optionally sync to DB in background
        Task {
            do {
                let shim = SupabaseClientShim()
                
                struct UpdateScan: Encodable {
                    let scans: Int
                }
                
                _ = try await shim.client
                    .from("campaigns")
                    .update(UpdateScan(scans: newScans))
                    .eq("id", value: id.uuidString)
                    .execute()
                print("✅ [HOOK DEBUG] Scans synced to DB")
            } catch {
                print("⚠️ [HOOK DEBUG] Failed to sync scans to DB: \(error)")
            }
        }
        
        print("✅ [HOOK DEBUG] Progress bump completed")
    }
}
