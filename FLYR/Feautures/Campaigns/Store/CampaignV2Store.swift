import Foundation
import Combine

/// In-memory store for CampaignV2 data
@MainActor
final class CampaignV2Store: ObservableObject {
    @Published private(set) var campaigns: [CampaignV2] = []
    
    var routeToV2Detail: ((UUID) -> Void)?
    
    private init() {
        // Start with empty campaigns - real data will be loaded from API
        campaigns = []
    }
    
    static let shared = CampaignV2Store()
    
    /// Replace all campaigns
    func set(_ items: [CampaignV2]) {
        print("📦 [STORE DEBUG] Setting \(items.count) campaigns in store")
        for (index, campaign) in items.enumerated() {
            print("📦 [STORE DEBUG] Campaign \(index + 1): '\(campaign.name)' (ID: \(campaign.id))")
        }
        campaigns = items
    }
    
    /// Add a new campaign
    func append(_ campaign: CampaignV2) {
        print("📦 [STORE DEBUG] Appending campaign: '\(campaign.name)' (ID: \(campaign.id))")
        print("📦 [STORE DEBUG] Campaign type: \(campaign.type.rawValue)")
        print("📦 [STORE DEBUG] Address count: \(campaign.addresses.count)")
        print("📦 [STORE DEBUG] Progress: \(Int(campaign.progress * 100))%")
        campaigns.append(campaign)
        print("📦 [STORE DEBUG] Store now contains \(campaigns.count) campaigns")
    }
    
    /// Update progress by setting scans count
    func updateProgress(id: UUID, scans: Int) {
        print("📦 [STORE DEBUG] Updating scans for campaign \(id)")
        print("📦 [STORE DEBUG] New scans: \(scans)")
        
        if let index = campaigns.firstIndex(where: { $0.id == id }) {
            let oldScans = campaigns[index].scans
            campaigns[index].scans = max(0, min(campaigns[index].totalFlyers, scans))
            print("📦 [STORE DEBUG] Scans updated from \(oldScans) to \(campaigns[index].scans)")
            print("📦 [STORE DEBUG] Progress is now \(campaigns[index].progressPct)%")
        } else {
            print("❌ [STORE DEBUG] Campaign with ID \(id) not found in store")
        }
    }
    
    /// Update a campaign (for general updates)
    func update(_ campaign: CampaignV2) {
        if let index = campaigns.firstIndex(where: { $0.id == campaign.id }) {
            campaigns[index] = campaign
            print("📦 [STORE DEBUG] Updated campaign '\(campaign.name)'")
        }
    }

    /// Mark campaign as archived (updates in-memory only; call API separately to persist).
    func setStatus(id: UUID, status: CampaignStatus) {
        guard let index = campaigns.firstIndex(where: { $0.id == id }) else { return }
        campaigns[index].status = status
        print("📦 [STORE DEBUG] Campaign \(id) status set to \(status.rawValue)")
    }

    func setStatus(ids: Set<UUID>, status: CampaignStatus) {
        guard !ids.isEmpty else { return }
        for index in campaigns.indices where ids.contains(campaigns[index].id) {
            campaigns[index].status = status
        }
        print("📦 [STORE DEBUG] Updated \(ids.count) campaign(s) to status \(status.rawValue)")
    }
    
    /// Get campaign by ID
    func campaign(id: UUID) -> CampaignV2? {
        print("📦 [STORE DEBUG] Looking up campaign with ID: \(id)")
        let found = campaigns.first { $0.id == id }
        if let campaign = found {
            print("📦 [STORE DEBUG] Found campaign: '\(campaign.name)'")
        } else {
            print("❌ [STORE DEBUG] Campaign with ID \(id) not found")
        }
        return found
    }
    
    /// Remove campaign by ID
    func remove(id: UUID) {
        print("📦 [STORE DEBUG] Removing campaign with ID: \(id)")
        let beforeCount = campaigns.count
        campaigns.removeAll { $0.id == id }
        let afterCount = campaigns.count
        print("📦 [STORE DEBUG] Removed \(beforeCount - afterCount) campaign(s). Store now has \(afterCount) campaigns")
    }

    func remove(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        print("📦 [STORE DEBUG] Removing \(ids.count) campaign(s)")
        let beforeCount = campaigns.count
        campaigns.removeAll { ids.contains($0.id) }
        let afterCount = campaigns.count
        print("📦 [STORE DEBUG] Removed \(beforeCount - afterCount) campaign(s). Store now has \(afterCount) campaigns")
    }
    
    /// Clear all campaigns
    func clear() {
        print("📦 [STORE DEBUG] Clearing all campaigns from store")
        let count = campaigns.count
        campaigns.removeAll()
        print("📦 [STORE DEBUG] Cleared \(count) campaigns")
    }
    
    /// Clear mock data and start fresh
    func clearMockData() {
        print("📦 [STORE DEBUG] Clearing mock data and starting fresh")
        campaigns.removeAll()
    }
}
