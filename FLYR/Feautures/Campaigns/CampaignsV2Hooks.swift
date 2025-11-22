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
        
        do {
            let campaigns = try await api.fetchCampaigns()
            store.set(campaigns)
            items = campaigns
        } catch {
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
        
        do {
            let campaign = try await api.createCampaign(draft)
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
        
        // First check if campaign exists in the store with addresses loaded
        if let store = store, var campaign = store.campaign(id: id) {
            print("🎣 [HOOK DEBUG] Campaign found in store: '\(campaign.name)'")
            
            // If addresses are empty, fetch them (lazy loading)
            if campaign.addresses.isEmpty {
                print("🎣 [HOOK DEBUG] Campaign has no addresses, fetching them...")
                do {
                    let fullCampaign = try await api.fetchCampaign(id: id)
                    campaign.addresses = fullCampaign.addresses
                    campaign.totalFlyers = fullCampaign.totalFlyers
                    // Update store with full campaign data
                    store.update(campaign)
                    item = campaign
                    print("🎣 [HOOK DEBUG] Addresses loaded: \(campaign.addresses.count) addresses")
                } catch {
                    print("⚠️ [HOOK DEBUG] Failed to load addresses: \(error.localizedDescription)")
                    // Still show campaign without addresses
                    item = campaign
                }
            } else {
                item = campaign
            }
            
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
