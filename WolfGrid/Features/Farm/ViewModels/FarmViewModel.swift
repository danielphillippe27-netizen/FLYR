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
    private let cachedLoader: (UUID, UUID?) async -> [Farm]
    private let remoteLoader: (UUID) async throws -> [Farm]
    private let countLoader: (Farm) async -> Farm
    private let workspaceProvider: () -> UUID?

    init(cachedLoader: ((UUID, UUID?) async -> [Farm])? = nil,
         remoteLoader: ((UUID) async throws -> [Farm])? = nil,
         countLoader: ((Farm) async -> Farm)? = nil,
         workspaceProvider: (() -> UUID?)? = nil) {
        self.cachedLoader = cachedLoader ?? { await FarmOfflineRepository.shared.getCachedFarms(userId: $0, workspaceId: $1) }
        self.remoteLoader = remoteLoader ?? { try await FarmService.shared.fetchFarms(userID: $0, refreshCounts: false) }
        self.countLoader = countLoader ?? { await FarmService.shared.farmWithCurrentHomeCount($0) }
        self.workspaceProvider = workspaceProvider ?? { WorkspaceContext.shared.workspaceId }
    }
    
    // MARK: - Load Farms
    
    private var loadGeneration = UUID()
    private var loadedScope: String?
    private var countRefreshTask: Task<Void, Never>?

    func loadFarms(userId: UUID) async {
        let workspaceId = workspaceProvider()
        let scope = "\(userId):\(workspaceId?.uuidString ?? "personal")"
        let generation = UUID()
        loadGeneration = generation
        countRefreshTask?.cancel()
        if loadedScope != scope { farms = []; loadedScope = scope }
        isLoading = farms.isEmpty
        errorMessage = nil
        let trace = PerfTrace.begin("farm_list", "load")
        defer {
            if loadGeneration == generation { isLoading = false }
            trace.end()
        }
        let cached = await cachedLoader(userId, workspaceId)
        guard loadGeneration == generation, !Task.isCancelled else { return }
        if !cached.isEmpty {
            farms = cached
            isLoading = false
            PerfTrace.event("farm_list", "cached_list_visible", fields: ["count": cached.count])
        }
        do {
            let fetched = try await remoteLoader(userId)
            guard loadGeneration == generation, !Task.isCancelled else { return }
            farms = fetched
            isLoading = false
            PerfTrace.event("farm_list", "fresh_list_visible", fields: ["count": fetched.count])
            // Counts are supplementary. Never put them on the navigation critical path.
            countRefreshTask = Task { [weak self] in
                for farm in fetched {
                    guard !Task.isCancelled, let self, self.loadGeneration == generation else { return }
                    let updated = await self.countLoader(farm)
                    guard !Task.isCancelled, self.loadGeneration == generation else { return }
                    if let index = self.farms.firstIndex(where: { $0.id == updated.id }),
                       self.farms[index].addressCount != updated.addressCount {
                        self.farms[index].addressCount = updated.addressCount
                    }
                }
            }
        } catch {
            guard loadGeneration == generation, !Task.isCancelled else { return }
            if farms.isEmpty { errorMessage = "Failed to load farms: \(error.localizedDescription)" }
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

