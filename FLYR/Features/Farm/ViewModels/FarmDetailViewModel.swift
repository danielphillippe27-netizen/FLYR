import SwiftUI
import Combine

@MainActor
final class FarmDetailViewModel: ObservableObject {
    @Published var farm: Farm?
    @Published var touches: [FarmTouch] = []
    @Published var cycles: [FarmCycle] = []
    @Published var leads: [FarmLead] = []
    @Published var addresses: [CampaignAddressViewRow] = []
    @Published var upcomingTouches: [FarmTouch] = []
    @Published var recommendations: [FarmRecommendation] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let farmService = FarmService.shared
    private let touchService = FarmTouchService.shared
    private let cycleService = FarmCycleService.shared
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
        async let cyclesTask: Void = loadCycles()
        async let leadsTask: Void = loadLeads()
        async let addressesTask: Void = loadAddresses()

        _ = await (touchesTask, cyclesTask, leadsTask, addressesTask)
        
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
    
    private func loadCycles() async {
        do {
            cycles = try await cycleService.fetchCycles(farmId: farmId)
        } catch {
            errorMessage = "Failed to load cycles: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error loading cycles: \(error)")
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
        guard let polygonGeoJSON = farm?.polygon, !polygonGeoJSON.isEmpty else {
            addresses = []
            return
        }

        do {
            addresses = try await AddressesAPI.shared.fetchAddressesInPolygon(
                polygonGeoJSON: polygonGeoJSON,
                campaignId: nil
            )
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
        await loadCycles()
        await loadLeads()
        calculateUpcomingTouches()
        generateRecommendations()
    }

    // MARK: - Generate Cycles

    func generateCycles() async {
        guard let farm = farm else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            cycles = try await cycleService.calculateCycles(farm: farm)
        } catch {
            errorMessage = "Failed to generate cycles: \(error.localizedDescription)"
            print("❌ [FarmDetailViewModel] Error generating cycles: \(error)")
        }
    }
}

// MARK: - Farm Recommendation

struct FarmRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

