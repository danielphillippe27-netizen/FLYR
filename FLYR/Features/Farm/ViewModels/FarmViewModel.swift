import SwiftUI
import Combine
import CoreLocation

@MainActor
final class FarmViewModel: ObservableObject {
    @Published var farms: [Farm] = []
    @Published var selectedFarm: Farm?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let farmService = FarmService.shared
    
    // MARK: - Load Farms
    
    func loadFarms(userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            farms = try await farmService.fetchFarms(userID: userId)
        } catch {
            errorMessage = "Failed to load farms: \(error.localizedDescription)"
            print("❌ [FarmViewModel] Error loading farms: \(error)")
        }
    }
    
    // MARK: - Create Farm
    
    func createFarm(
        name: String,
        userId: UUID,
        startDate: Date,
        endDate: Date,
        frequency: Int,
        polygon: [CLLocationCoordinate2D]?,
        areaLabel: String? = nil
    ) async throws -> Farm {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let farm = try await farmService.createFarm(
                name: name,
                userId: userId,
                startDate: startDate,
                endDate: endDate,
                frequency: frequency,
                polygon: polygon,
                areaLabel: areaLabel
            )
            
            // Reload farms
            await loadFarms(userId: userId)
            
            return farm
        } catch {
            errorMessage = "Failed to create farm: \(error.localizedDescription)"
            print("❌ [FarmViewModel] Error creating farm: \(error)")
            throw error
        }
    }
    
    // MARK: - Delete Farm
    
    func deleteFarm(_ farm: Farm, userId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await farmService.deleteFarm(id: farm.id)
            
            // Remove from local array
            farms.removeAll { $0.id == farm.id }
            
            // Clear selection if deleted
            if selectedFarm?.id == farm.id {
                selectedFarm = nil
            }
        } catch {
            errorMessage = "Failed to delete farm: \(error.localizedDescription)"
            print("❌ [FarmViewModel] Error deleting farm: \(error)")
        }
    }
    
    // MARK: - Update Farm
    
    func updateFarm(_ farm: Farm) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let updated = try await farmService.updateFarm(farm)
            
            // Update in local array
            if let index = farms.firstIndex(where: { $0.id == farm.id }) {
                farms[index] = updated
            }
            
            // Update selection if needed
            if selectedFarm?.id == farm.id {
                selectedFarm = updated
            }
        } catch {
            errorMessage = "Failed to update farm: \(error.localizedDescription)"
            print("❌ [FarmViewModel] Error updating farm: \(error)")
        }
    }
    
    // MARK: - Refresh
    
    func refresh(userId: UUID) async {
        await loadFarms(userId: userId)
    }
}

