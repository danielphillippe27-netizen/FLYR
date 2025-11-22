import SwiftUI
import Combine

@MainActor
final class FarmTouchPlannerViewModel: ObservableObject {
    @Published var touches: [FarmTouch] = []
    @Published var touchesByMonth: [String: [FarmTouch]] = [:]
    @Published var selectedMonth: String?
    @Published var isEditing = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let touchService = FarmTouchService.shared
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
    }
    
    // MARK: - Load Touches
    
    func loadTouches() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            touches = try await touchService.fetchTouches(farmId: farmId)
            groupTouchesByMonth()
        } catch {
            errorMessage = "Failed to load touches: \(error.localizedDescription)"
            print("❌ [FarmTouchPlannerViewModel] Error loading touches: \(error)")
        }
    }
    
    // MARK: - Group Touches by Month
    
    private func groupTouchesByMonth() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        
        touchesByMonth = Dictionary(grouping: touches) { touch in
            formatter.string(from: touch.date)
        }
        
        // Sort months
        let sortedMonths = touchesByMonth.keys.sorted()
        if selectedMonth == nil, let firstMonth = sortedMonths.first {
            selectedMonth = firstMonth
        }
    }
    
    // MARK: - Add Touch
    
    func addTouch(
        date: Date,
        type: FarmTouchType,
        title: String,
        notes: String? = nil,
        orderIndex: Int? = nil
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        let touch = FarmTouch(
            farmId: farmId,
            date: date,
            type: type,
            title: title,
            notes: notes,
            orderIndex: orderIndex ?? touches.count
        )
        
        do {
            let created = try await touchService.createTouch(touch)
            touches.append(created)
            groupTouchesByMonth()
        } catch {
            errorMessage = "Failed to add touch: \(error.localizedDescription)"
            print("❌ [FarmTouchPlannerViewModel] Error adding touch: \(error)")
        }
    }
    
    // MARK: - Update Touch
    
    func updateTouch(_ touch: FarmTouch) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let updated = try await touchService.updateTouch(touch)
            
            if let index = touches.firstIndex(where: { $0.id == touch.id }) {
                touches[index] = updated
            }
            
            groupTouchesByMonth()
        } catch {
            errorMessage = "Failed to update touch: \(error.localizedDescription)"
            print("❌ [FarmTouchPlannerViewModel] Error updating touch: \(error)")
        }
    }
    
    // MARK: - Delete Touch
    
    func deleteTouch(_ touch: FarmTouch) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            try await touchService.deleteTouch(id: touch.id)
            touches.removeAll { $0.id == touch.id }
            groupTouchesByMonth()
        } catch {
            errorMessage = "Failed to delete touch: \(error.localizedDescription)"
            print("❌ [FarmTouchPlannerViewModel] Error deleting touch: \(error)")
        }
    }
    
    // MARK: - Reorder Touches
    
    func reorderTouches(from source: IndexSet, to destination: Int, in month: String) {
        guard var monthTouches = touchesByMonth[month] else { return }
        
        monthTouches.move(fromOffsets: source, toOffset: destination)
        
        // Update order indices
        for (index, touch) in monthTouches.enumerated() {
            let updated = FarmTouch(
                id: touch.id,
                farmId: touch.farmId,
                date: touch.date,
                type: touch.type,
                title: touch.title,
                notes: touch.notes,
                orderIndex: index,
                completed: touch.completed,
                campaignId: touch.campaignId,
                batchId: touch.batchId,
                createdAt: touch.createdAt
            )
            
            // Update in main array
            if let mainIndex = touches.firstIndex(where: { $0.id == touch.id }) {
                touches[mainIndex] = updated
            }
        }
        
        groupTouchesByMonth()
        
        // Save updated order indices
        Task {
            for touch in monthTouches {
                await updateTouch(touch)
            }
        }
    }
    
    // MARK: - Attach Campaign
    
    func attachCampaign(to touch: FarmTouch, campaignId: UUID) async {
        let updated = FarmTouch(
            id: touch.id,
            farmId: touch.farmId,
            date: touch.date,
            type: touch.type,
            title: touch.title,
            notes: touch.notes,
            orderIndex: touch.orderIndex,
            completed: touch.completed,
            campaignId: campaignId,
            batchId: touch.batchId,
            createdAt: touch.createdAt
        )
        
        await updateTouch(updated)
    }
    
    // MARK: - Attach Batch
    
    func attachBatch(to touch: FarmTouch, batchId: UUID) async {
        let updated = FarmTouch(
            id: touch.id,
            farmId: touch.farmId,
            date: touch.date,
            type: touch.type,
            title: touch.title,
            notes: touch.notes,
            orderIndex: touch.orderIndex,
            completed: touch.completed,
            campaignId: touch.campaignId,
            batchId: batchId,
            createdAt: touch.createdAt
        )
        
        await updateTouch(updated)
    }
    
    // MARK: - Mark Complete
    
    func markComplete(_ touch: FarmTouch, completed: Bool) async {
        do {
            let updated = try await touchService.markComplete(touchId: touch.id, completed: completed)
            
            if let index = touches.firstIndex(where: { $0.id == touch.id }) {
                touches[index] = updated
            }
            
            groupTouchesByMonth()
        } catch {
            errorMessage = "Failed to update touch: \(error.localizedDescription)"
            print("❌ [FarmTouchPlannerViewModel] Error marking touch complete: \(error)")
        }
    }
    
    // MARK: - Get Touches for Month
    
    func touchesForMonth(_ month: String) -> [FarmTouch] {
        return touchesByMonth[month]?.sorted { $0.date < $1.date } ?? []
    }
    
    // MARK: - Get Sorted Months
    
    var sortedMonths: [String] {
        touchesByMonth.keys.sorted()
    }
}

