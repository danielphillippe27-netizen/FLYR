import Foundation
import SwiftUI
import Combine

/// ViewModel for A/B Test creation view
/// Handles campaign/landing page selection and experiment creation
@MainActor
class UseABTestCreate: ObservableObject {
    @Published var campaigns: [Campaign] = []
    @Published var landingPages: [LandingPage] = []
    @Published var selectedCampaignId: UUID?
    @Published var selectedLandingPageId: UUID?
    @Published var experimentName: String = ""
    @Published var isCreating = false
    @Published var isLoadingCampaigns = false
    @Published var isLoadingLandingPages = false
    @Published var errorMessage: String?
    
    private let experimentsAPI = ExperimentsAPI.shared
    private let landingPagesAPI = LandingPagesAPI.shared
    private let campaignsAPI = CampaignsAPI.shared
    
    // MARK: - Load Data
    
    func loadCampaigns() async {
        isLoadingCampaigns = true
        errorMessage = nil
        defer { isLoadingCampaigns = false }
        
        do {
            campaigns = try await campaignsAPI.fetchCampaigns()
            // Sort: active first, then draft, then completed
            campaigns.sort { campaign1, campaign2 in
                // Simple sorting - you might want to add status field to Campaign model
                campaign1.createdAt > campaign2.createdAt
            }
        } catch {
            errorMessage = "Failed to load campaigns: \(error.localizedDescription)"
            print("❌ [AB Test Create] Error loading campaigns: \(error)")
        }
    }
    
    func loadLandingPages() async {
        isLoadingLandingPages = true
        errorMessage = nil
        defer { isLoadingLandingPages = false }
        
        do {
            landingPages = try await landingPagesAPI.fetchLandingPages()
        } catch {
            errorMessage = "Failed to load landing pages: \(error.localizedDescription)"
            print("❌ [AB Test Create] Error loading landing pages: \(error)")
        }
    }
    
    // MARK: - Create Experiment
    
    /// Create a new experiment with Variant A and Variant B
    /// - Returns: The created experiment with variants
    func createExperiment() async throws -> Experiment {
        guard let campaignId = selectedCampaignId else {
            throw ABTestError.missingCampaign
        }
        
        guard let landingPageId = selectedLandingPageId else {
            throw ABTestError.missingLandingPage
        }
        
        guard !experimentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ABTestError.missingExperimentName
        }
        
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        
        do {
            // Create experiment
            var experiment = try await experimentsAPI.createExperiment(
                name: experimentName.trimmingCharacters(in: .whitespacesAndNewlines),
                campaignId: campaignId,
                landingPageId: landingPageId
            )
            
            // Auto-create Variant A and Variant B
            let variants = try await experimentsAPI.createVariants(experimentId: experiment.id)
            experiment.variants = variants
            
            print("✅ [AB Test Create] Created experiment with \(variants.count) variants")
            
            return experiment
        } catch {
            errorMessage = "Failed to create experiment: \(error.localizedDescription)"
            print("❌ [AB Test Create] Error creating experiment: \(error)")
            throw error
        }
    }
    
    // MARK: - Validation
    
    var canCreate: Bool {
        selectedCampaignId != nil &&
        selectedLandingPageId != nil &&
        !experimentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isCreating
    }
}

// MARK: - Errors

enum ABTestError: LocalizedError {
    case missingCampaign
    case missingLandingPage
    case missingExperimentName
    
    var errorDescription: String? {
        switch self {
        case .missingCampaign:
            return "Please select a campaign"
        case .missingLandingPage:
            return "Please select a landing page"
        case .missingExperimentName:
            return "Please enter an experiment name"
        }
    }
}

