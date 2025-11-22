import SwiftUI
import Combine

@MainActor
final class FarmDetailViewModel: ObservableObject {
    @Published var farm: Farm?
    @Published var touches: [FarmTouch] = []
    @Published var phases: [FarmPhase] = []
    @Published var leads: [FarmLead] = []
    @Published var upcomingTouches: [FarmTouch] = []
    @Published var recommendations: [FarmRecommendation] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let farmService = FarmService.shared
    private let touchService = FarmTouchService.shared
    private let phaseService = FarmPhaseService.shared
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
        
        async let farmTask = loadFarm()
        async let touchesTask = loadTouches()
        async let phasesTask = loadPhases()
        async let leadsTask = loadLeads()
        
        _ = await (farmTask, touchesTask, phasesTask, leadsTask)
        
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
    
    private func loadPhases() async {
        do {
            phases = try await phaseService.fetchPhases(farmId: farmId)
        } catch {
            errorMessage = "Failed to load phases: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error loading phases: \(error)")
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
        if phases.isEmpty {
            recs.append(FarmRecommendation(
                title: "Generate Phases",
                detail: "Phases help track progress through your farm lifecycle. Generate phases to get started."
            ))
        }
        
        recommendations = recs
    }
    
    // MARK: - Refresh Analytics
    
    func refreshAnalytics() async {
        await loadTouches()
        await loadPhases()
        await loadLeads()
        calculateUpcomingTouches()
        generateRecommendations()
    }
    
    // MARK: - Generate Phases
    
    func generatePhases() async {
        guard let farm = farm else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            phases = try await phaseService.calculatePhases(farm: farm)
        } catch {
            errorMessage = "Failed to generate phases: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error generating phases: \(error)")
        }
    }
}

// MARK: - Farm Recommendation

struct FarmRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}



