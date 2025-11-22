import Foundation
import SwiftUI
import Combine

@MainActor
class LandingPageMainViewModel: ObservableObject {
    @Published var campaigns: [CampaignListItem] = []
    @Published var selectedCampaignId: UUID?
    @Published var landingPage: CampaignLandingPage?
    @Published var isLoading = false
    @Published var isLoadingCampaigns = false
    @Published var error: String?
    
    private let landingPageService = SupabaseLandingPageService.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        error = nil
        defer { isLoadingCampaigns = false }
        
        do {
            let dbRows = try await campaignsAPI.fetchCampaignsMetadata()
            campaigns = dbRows.map { CampaignListItem(id: $0.id, name: $0.title, addressCount: nil) }
        } catch let err {
            self.error = "Failed to load campaigns: \(err.localizedDescription)"
            print("❌ [LandingPageMainViewModel] Error loading campaigns: \(err)")
        }
    }
    
    func loadLandingPage(campaignId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            landingPage = try await landingPageService.fetchLandingPage(campaignId: campaignId)
            selectedCampaignId = campaignId
        } catch let err {
            self.error = "Failed to load landing page: \(err.localizedDescription)"
            print("❌ [LandingPageMainViewModel] Error loading landing page: \(err)")
        }
    }
}

