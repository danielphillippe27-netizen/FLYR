import Foundation
import SwiftUI
import Combine

/// ViewModel for A/B Test detail view
/// Handles loading experiment details, stats, and managing experiment state
@MainActor
class UseABTestDetail: ObservableObject {
    @Published var experiment: Experiment?
    @Published var variants: [ExperimentVariant] = []
    @Published var stats: ExperimentScanStats?
    @Published var isLoading = false
    @Published var isLoadingStats = false
    @Published var errorMessage: String?
    
    private let experimentsAPI = ExperimentsAPI.shared
    private let experimentId: UUID
    
    init(experimentId: UUID) {
        self.experimentId = experimentId
    }
    
    // MARK: - Load Data
    
    func loadExperiment() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            experiment = try await experimentsAPI.fetchExperiment(id: experimentId)
            variants = try await experimentsAPI.fetchVariants(experimentId: experimentId)
            experiment?.variants = variants
        } catch {
            errorMessage = "Failed to load experiment: \(error.localizedDescription)"
            print("❌ [AB Test Detail] Error loading experiment: \(error)")
        }
    }
    
    func loadStats() async {
        isLoadingStats = true
        errorMessage = nil
        defer { isLoadingStats = false }
        
        do {
            stats = try await experimentsAPI.fetchScanStats(experimentId: experimentId)
        } catch {
            errorMessage = "Failed to load stats: \(error.localizedDescription)"
            print("❌ [AB Test Detail] Error loading stats: \(error)")
        }
    }
    
    // MARK: - Update Status
    
    /// Update experiment status
    /// - Parameter status: New status ("draft", "running", "completed")
    func updateStatus(_ status: String) async {
        errorMessage = nil
        
        do {
            try await experimentsAPI.updateExperimentStatus(experimentId: experimentId, status: status)
            // Reload experiment to get updated status
            await loadExperiment()
        } catch {
            errorMessage = "Failed to update status: \(error.localizedDescription)"
            print("❌ [AB Test Detail] Error updating status: \(error)")
        }
    }
    
    // MARK: - Mark Winner
    
    /// Mark a variant as the winner and complete the experiment
    /// - Parameter variantId: ID of the winning variant
    func markWinner(variantId: UUID) async {
        errorMessage = nil
        
        do {
            try await experimentsAPI.markExperimentWinner(experimentId: experimentId, winnerVariantId: variantId)
            // Reload experiment and stats
            await loadExperiment()
            await loadStats()
        } catch {
            errorMessage = "Failed to mark winner: \(error.localizedDescription)"
            print("❌ [AB Test Detail] Error marking winner: \(error)")
        }
    }
    
    // MARK: - Computed Properties
    
    /// Get variant A
    var variantA: ExperimentVariant? {
        variants.first { $0.key == "A" }
    }
    
    /// Get variant B
    var variantB: ExperimentVariant? {
        variants.first { $0.key == "B" }
    }
    
    /// Get winner variant ID from stats
    var winnerVariantId: UUID? {
        guard let stats = stats,
              let winner = stats.winner else {
            return nil
        }
        
        if winner == "A" {
            return variantA?.id
        } else if winner == "B" {
            return variantB?.id
        }
        
        return nil
    }
}

