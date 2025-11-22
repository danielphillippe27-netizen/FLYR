import Foundation
import SwiftUI
import Combine

@MainActor
final class CampaignStore: ObservableObject {
    @Published var campaigns: [Campaign] = []
    @Published var campaignsV2: [CampaignV2] = []
    @Published var isLoading = false
    @Published var error: String?
    
    // Navigation callback for V2 detail
    var routeToV2Detail: ((UUID) -> Void)?
    
    init() {
        // Initialize with empty arrays
    }
    
    // MARK: - V1 Campaigns
    
    func loadCampaigns() async {
        isLoading = true
        error = nil
        
        do {
            campaigns = try await CampaignsAPI.shared.fetchCampaigns()
        } catch {
            self.error = "Failed to load campaigns: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - V2 Campaigns
    
    func appendV2(_ campaign: CampaignV2) {
        campaignsV2.append(campaign)
    }
    
    func loadCampaignsV2() async {
        isLoading = true
        error = nil
        
        do {
            campaignsV2 = try await CampaignsAPI.shared.fetchCampaignsV2()
        } catch {
            self.error = "Failed to load V2 campaigns: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func getCampaignV2(id: UUID) -> CampaignV2? {
        campaignsV2.first { $0.id == id }
    }
}
