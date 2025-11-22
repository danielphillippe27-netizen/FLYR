import SwiftUI
import Combine
import CoreLocation

@MainActor
final class FarmAnalyticsViewModel: ObservableObject {
    @Published var funnelData: FunnelData?
    @Published var touchEffectiveness: [TouchEffectiveness] = []
    @Published var phaseComparison: [PhaseComparison] = []
    @Published var heatmapData: [HeatmapPoint] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let touchService = FarmTouchService.shared
    private let phaseService = FarmPhaseService.shared
    private let leadService = FarmLeadService.shared
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
    }
    
    // MARK: - Calculate Funnel
    
    func calculateFunnel() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let touches = try await touchService.fetchTouches(farmId: farmId)
            let leads = try await leadService.fetchLeads(farmId: farmId)
            
            let totalTouches = touches.count
            let completedTouches = touches.filter { $0.completed }.count
            
            // Count scans (from QR codes linked to touches)
            // This would require integration with QR scan events
            let scans = 0 // TODO: Integrate with QR scan tracking
            
            let totalLeads = leads.count
            
            // Count appointments (from leads with status)
            // This would require integration with contacts/CRM
            let appointments = 0 // TODO: Integrate with contacts
            
            // Count listings (from conversions)
            // This would require integration with conversions tracking
            let listings = 0 // TODO: Integrate with conversions
            
            funnelData = FunnelData(
                touches: totalTouches,
                completedTouches: completedTouches,
                scans: scans,
                leads: totalLeads,
                appointments: appointments,
                listings: listings
            )
        } catch {
            errorMessage = "Failed to calculate funnel: \(error.localizedDescription)"
            print("❌ [FarmAnalyticsViewModel] Error calculating funnel: \(error)")
        }
    }
    
    // MARK: - Analyze Touch Types
    
    func analyzeTouchTypes() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let touches = try await touchService.fetchTouches(farmId: farmId)
            let leads = try await leadService.fetchLeads(farmId: farmId)
            
            var effectiveness: [TouchEffectiveness] = []
            
            for touchType in FarmTouchType.allCases {
                let typeTouches = touches.filter { $0.type == touchType }
                let typeLeads = leads.filter { $0.leadSource.rawValue == touchType.rawValue }
                
                let completionRate = typeTouches.isEmpty ? 0.0 : Double(typeTouches.filter { $0.completed }.count) / Double(typeTouches.count)
                let leadRate = typeTouches.isEmpty ? 0.0 : Double(typeLeads.count) / Double(typeTouches.count)
                
                effectiveness.append(TouchEffectiveness(
                    type: touchType,
                    totalTouches: typeTouches.count,
                    completedTouches: typeTouches.filter { $0.completed }.count,
                    leads: typeLeads.count,
                    completionRate: completionRate,
                    leadRate: leadRate
                ))
            }
            
            touchEffectiveness = effectiveness
        } catch {
            errorMessage = "Failed to analyze touch types: \(error.localizedDescription)"
            print("❌ [FarmAnalyticsViewModel] Error analyzing touch types: \(error)")
        }
    }
    
    // MARK: - Compare Phases
    
    func comparePhases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let phases = try await phaseService.fetchPhases(farmId: farmId)
            let touches = try await touchService.fetchTouches(farmId: farmId)
            let leads = try await leadService.fetchLeads(farmId: farmId)
            
            var comparisons: [PhaseComparison] = []
            
            for phase in phases {
                let phaseTouches = touches.filter { touch in
                    touch.date >= phase.startDate && touch.date <= phase.endDate
                }
                
                let phaseLeads = leads.filter { lead in
                    if let touchId = lead.touchId,
                       let touch = touches.first(where: { $0.id == touchId }) {
                        return touch.date >= phase.startDate && touch.date <= phase.endDate
                    }
                    return false
                }
                
                let flyers = phaseTouches.filter { $0.type == .flyer }.count
                let knocks = phaseTouches.filter { $0.type == .doorKnock }.count
                let scans = 0 // TODO: Integrate with QR scans
                let conversions = 0 // TODO: Integrate with conversions
                
                // Calculate spend (estimated)
                let estimatedSpend = Double(flyers) * 0.50 + Double(knocks) * 0.0 // Flyers cost $0.50 each
                let roi = conversions > 0 ? (Double(conversions) * 1000.0) / estimatedSpend : 0.0 // Assume $1000 per conversion
                
                comparisons.append(PhaseComparison(
                    phaseName: phase.phaseName,
                    startDate: phase.startDate,
                    endDate: phase.endDate,
                    touches: phaseTouches.count,
                    flyers: flyers,
                    knocks: knocks,
                    scans: scans,
                    leads: phaseLeads.count,
                    conversions: conversions,
                    spend: estimatedSpend,
                    roi: roi
                ))
            }
            
            phaseComparison = comparisons
        } catch {
            errorMessage = "Failed to compare phases: \(error.localizedDescription)"
            print("❌ [FarmAnalyticsViewModel] Error comparing phases: \(error)")
        }
    }
    
    // MARK: - Generate Heatmap
    
    func generateHeatmap() async {
        // This would require address-level data with scan/lead counts
        // For now, return empty array
        heatmapData = []
    }
}

// MARK: - Analytics Models

struct FunnelData {
    let touches: Int
    let completedTouches: Int
    let scans: Int
    let leads: Int
    let appointments: Int
    let listings: Int
}

struct TouchEffectiveness {
    let type: FarmTouchType
    let totalTouches: Int
    let completedTouches: Int
    let leads: Int
    let completionRate: Double
    let leadRate: Double
}

struct PhaseComparison {
    let phaseName: String
    let startDate: Date
    let endDate: Date
    let touches: Int
    let flyers: Int
    let knocks: Int
    let scans: Int
    let leads: Int
    let conversions: Int
    let spend: Double
    let roi: Double
}

struct HeatmapPoint {
    let coordinate: CLLocationCoordinate2D
    let intensity: Double // 0.0 - 1.0
    let address: String
}

