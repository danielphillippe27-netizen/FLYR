import SwiftUI
import Combine

@MainActor
final class FarmDetailViewModel: ObservableObject {
    @Published var farm: Farm?
    @Published var touches: [FarmTouch] = []
    @Published var cycles: [FarmCycle] = []
    @Published var leads: [FarmLead] = []
    @Published var addresses: [FarmAddressViewRow] = []
    @Published var upcomingTouches: [FarmTouch] = []
    @Published var recommendations: [FarmRecommendation] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let farmService = FarmService.shared
    private let touchService = FarmTouchService.shared
    private let leadService = FarmLeadService.shared
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
    }
    
    // MARK: - Load Farm Data
    
    func loadFarmData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await loadFarm()

        async let touchesTask: Void = loadTouches()
        async let leadsTask: Void = loadLeads()
        async let addressesTask: Void = loadAddresses()

        _ = await (touchesTask, leadsTask, addressesTask)

        recalculateCycles()
        
        // Calculate upcoming touches
        calculateUpcomingTouches()
        
        // Generate recommendations
        generateRecommendations()
    }
    
    private func loadFarm() async {
        do {
            farm = try await farmService.fetchFarm(id: farmId)
        } catch {
            errorMessage = "Failed to load farm: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error loading farm: \(error)")
        }
    }
    
    private func loadTouches() async {
        do {
            touches = try await touchService.fetchTouches(farmId: farmId)
        } catch {
            errorMessage = "Failed to load touches: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error loading touches: \(error)")
        }
    }
    
    private func loadLeads() async {
        do {
            leads = try await leadService.fetchLeads(farmId: farmId)
        } catch {
            errorMessage = "Failed to load leads: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error loading leads: \(error)")
        }
    }

    private func loadAddresses() async {
        guard farm != nil else {
            addresses = []
            return
        }

        do {
            addresses = try await farmService.fetchAddresses(farmId: farmId)
        } catch {
            addresses = []
            print("⚠️ [FarmDetailViewModel] Error loading addresses: \(error)")
        }
    }
    
    // MARK: - Calculate Upcoming Touches
    
    private func calculateUpcomingTouches() {
        let now = Date()
        upcomingTouches = touches
            .filter { !$0.completed && $0.date >= now }
            .sorted { $0.date < $1.date }
            .prefix(5)
            .map { $0 }
    }
    
    // MARK: - Generate Recommendations
    
    private func generateRecommendations() {
        var recs: [FarmRecommendation] = []
        
        // Analyze touch completion rate
        let totalTouches = touches.count
        let completedTouches = touches.filter { $0.completed }.count
        let completionRate = totalTouches > 0 ? Double(completedTouches) / Double(totalTouches) : 0.0
        
        if completionRate < 0.5 {
            recs.append(FarmRecommendation(
                title: "Low Completion Rate",
                detail: "Only \(Int(completionRate * 100))% of touches are completed. Consider adjusting your schedule or frequency."
            ))
        }
        
        // Analyze touch types
        let touchTypeCounts = Dictionary(grouping: touches, by: { $0.type })
        let flyerCount = touchTypeCounts[.flyer]?.count ?? 0
        let doorKnockCount = touchTypeCounts[.doorKnock]?.count ?? 0
        
        if flyerCount > doorKnockCount * 3 {
            recs.append(FarmRecommendation(
                title: "Balance Touch Types",
                detail: "You have many more flyers than door knocks. Consider adding more personal touches for better engagement."
            ))
        }
        
        // Analyze leads
        if leads.isEmpty && touches.count > 5 {
            recs.append(FarmRecommendation(
                title: "No Leads Yet",
                detail: "You have \(touches.count) touches but no leads. Consider adding QR codes or door knock conversations."
            ))
        }
        
        // Phase analysis
        if cycles.isEmpty {
            recs.append(FarmRecommendation(
                title: "Generate Cycles",
                detail: "Cycles help track progress through your farm workflow. Generate cycles to get started."
            ))
        }
        
        recommendations = recs
    }
    
    // MARK: - Refresh Analytics
    
    func refreshAnalytics() async {
        await loadTouches()
        await loadLeads()
        recalculateCycles()
        calculateUpcomingTouches()
        generateRecommendations()
    }

    private func recalculateCycles() {
        guard let farm else {
            cycles = []
            return
        }
        cycles = FarmCycleResolver.buildCycles(farm: farm, touches: touches)
    }

    private func resolvedTouches() -> [FarmCycleResolver.ResolvedTouch] {
        guard let farm else { return [] }
        return FarmCycleResolver.resolveTouches(
            touches,
            touchesPerInterval: max(1, farm.touchesPerInterval ?? farm.frequency)
        )
    }

    private func touches(for cycle: FarmCycle) -> [FarmTouch] {
        resolvedTouches()
            .filter { $0.cycleNumber == cycle.cycleNumber }
            .map(\.touch)
    }

    func preferredCampaignId(for cycle: FarmCycle, fallback: UUID?) -> UUID? {
        let cycleTouchCampaignIds = touches(for: cycle).compactMap(\.campaignId)
        let touchCounts = Dictionary(grouping: cycleTouchCampaignIds, by: { $0 })
            .mapValues(\.count)

        if let cycleCampaignId = touchCounts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.uuidString.localizedStandardCompare(rhs.key.uuidString) == .orderedAscending
            }
            return lhs.value < rhs.value
        })?.key {
            return cycleCampaignId
        }

        return fallback
    }

    private func preferredTouchType(for cycleTouches: [FarmTouch], campaignId: UUID) -> FarmTouchType {
        if let match = cycleTouches.first(where: { $0.campaignId == campaignId }) {
            return match.type
        }
        if let match = cycleTouches.first(where: { $0.campaignId == nil }) {
            return match.type
        }
        if let match = touches.first(where: { $0.campaignId == campaignId }) {
            return match.type
        }
        return cycleTouches.first?.type ?? .flyer
    }

    private func preferredTouchDate(for cycle: FarmCycle) -> Date {
        let now = Date()
        if now < cycle.startDate { return cycle.startDate }
        if now > cycle.endDate { return cycle.endDate }
        return now
    }

    private func nextOrderIndex(for cycleTouches: [FarmTouch]) -> Int {
        if let maxOrderIndex = cycleTouches.compactMap(\.orderIndex).max() {
            return maxOrderIndex + 1
        }
        return cycleTouches.count
    }

    private func replaceOrAppendTouch(_ touch: FarmTouch) {
        if let index = touches.firstIndex(where: { $0.id == touch.id }) {
            touches[index] = touch
        } else {
            touches.append(touch)
        }
        calculateUpcomingTouches()
        recalculateCycles()
        generateRecommendations()
    }

    private func executionContext(for touch: FarmTouch, farm: Farm, cycle: FarmCycle, campaignId: UUID) -> FarmExecutionContext {
        FarmExecutionContext(
            farmId: farm.id,
            farmName: farm.name,
            touchId: touch.id,
            touchTitle: touch.title,
            touchDate: touch.date,
            touchType: touch.type,
            campaignId: touch.campaignId ?? campaignId,
            cycleNumber: cycle.cycleNumber,
            cycleName: cycle.cycleName
        )
    }

    func ensureExecutionContext(for cycle: FarmCycle, campaignId: UUID) async -> FarmExecutionContext? {
        guard let farm else {
            errorMessage = "Farm details are still loading."
            return nil
        }

        let cycleTouches = touches(for: cycle)

        if let exactMatch = cycleTouches
            .sorted(by: { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.date < rhs.date
            })
            .first(where: { $0.campaignId == campaignId }) {
            return executionContext(for: exactMatch, farm: farm, cycle: cycle, campaignId: campaignId)
        }

        if let reusableTouch = cycleTouches
            .sorted(by: { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.date < rhs.date
            })
            .first(where: { $0.campaignId == nil }) {
            return executionContext(for: reusableTouch, farm: farm, cycle: cycle, campaignId: campaignId)
        }

        do {
            let persisted = try await touchService.createTouch(
                FarmTouch(
                    farmId: farm.id,
                    cycleNumber: cycle.cycleNumber,
                    date: preferredTouchDate(for: cycle),
                    type: preferredTouchType(for: cycleTouches, campaignId: campaignId),
                    title: cycle.cycleName,
                    orderIndex: nextOrderIndex(for: cycleTouches),
                    completed: false,
                    campaignId: campaignId
                )
            )
            replaceOrAppendTouch(persisted)
            return executionContext(for: persisted, farm: farm, cycle: cycle, campaignId: campaignId)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("row-level security"),
               message.localizedCaseInsensitiveContains("farm_touches") {
                errorMessage = "Failed to prepare cycle map: Supabase is blocking farm touch inserts for this farm. The live database likely still needs the workspace-aware farm_touches policy."
            } else {
                errorMessage = "Failed to prepare cycle map: \(message)"
            }
            print("❌ [FarmDetailViewModel] Error ensuring cycle touch for map: \(error)")
            return nil
        }
    }

}

// MARK: - Farm Recommendation

struct FarmRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}
