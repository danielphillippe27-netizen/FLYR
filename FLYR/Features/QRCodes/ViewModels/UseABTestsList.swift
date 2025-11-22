import Foundation
import SwiftUI
import Combine

/// ViewModel for A/B Tests list view
/// Handles loading and managing experiments
@MainActor
class UseABTestsList: ObservableObject {
    @Published var experiments: [Experiment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let experimentsAPI = ExperimentsAPI.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    private var campaignCache: [UUID: Campaign] = [:]
    
    // MARK: - Load Experiments
    
    func loadExperiments() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            experiments = try await experimentsAPI.fetchExperiments()
            
            // Load campaign names for all experiments
            await loadCampaignNames()
        } catch {
            errorMessage = "Failed to load experiments: \(error.localizedDescription)"
            print("❌ [AB Tests List] Error loading experiments: \(error)")
        }
    }
    
    // MARK: - Load Campaign Names
    
    private func loadCampaignNames() async {
        let campaignIds = Set(experiments.map { $0.campaignId })
        
        for campaignId in campaignIds {
            if campaignCache[campaignId] == nil {
                do {
                    let campaign = try await campaignsAPI.fetchCampaign(id: campaignId)
                    campaignCache[campaignId] = campaign
                } catch {
                    print("⚠️ [AB Tests List] Failed to load campaign \(campaignId): \(error)")
                }
            }
        }
    }
    
    // MARK: - Delete Experiment
    
    func deleteExperiment(id: UUID) async {
        errorMessage = nil
        
        do {
            try await experimentsAPI.deleteExperiment(id: id)
            // Remove from local array
            experiments.removeAll { $0.id == id }
        } catch {
            errorMessage = "Failed to delete experiment: \(error.localizedDescription)"
            print("❌ [AB Tests List] Error deleting experiment: \(error)")
        }
    }
    
    // MARK: - Get Campaign Name
    
    /// Get campaign name for an experiment
    func getCampaignName(for experiment: Experiment) -> String {
        return campaignCache[experiment.campaignId]?.title ?? "Campaign"
    }
}

