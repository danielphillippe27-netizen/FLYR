import Foundation

/// Utility for calculating farm analytics
enum FarmAnalyticsCalculator {
    /// Calculate funnel metrics
    static func calculateFunnel(
        touches: [FarmTouch],
        leads: [FarmLead],
        scans: Int = 0,
        appointments: Int = 0,
        listings: Int = 0
    ) -> FunnelData {
        let totalTouches = touches.count
        let completedTouches = touches.filter { $0.completed }.count
        
        return FunnelData(
            touches: totalTouches,
            completedTouches: completedTouches,
            scans: scans,
            leads: leads.count,
            appointments: appointments,
            listings: listings
        )
    }
    
    /// Analyze touch effectiveness by type
    static func analyzeTouchTypes(
        touches: [FarmTouch],
        leads: [FarmLead]
    ) -> [TouchEffectiveness] {
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
        
        return effectiveness
    }
    
    /// Compare cycles
    static func compareCycles(
        cycles: [FarmCycle],
        touches: [FarmTouch],
        leads: [FarmLead]
    ) -> [PhaseComparison] {
        var comparisons: [PhaseComparison] = []
        
        for cycle in cycles {
            let cycleTouches = touches.filter { touch in
                touch.date >= cycle.startDate && touch.date <= cycle.endDate
            }
            
            let cycleLeads = leads.filter { lead in
                if let touchId = lead.touchId,
                   let touch = touches.first(where: { $0.id == touchId }) {
                    return touch.date >= cycle.startDate && touch.date <= cycle.endDate
                }
                return false
            }
            
            let flyers = cycleTouches.filter { $0.type == .flyer }.count
            let knocks = cycleTouches.filter { $0.type == .doorKnock }.count
            let scans = 0 // TODO: Integrate with QR scans
            let conversions = 0 // TODO: Integrate with conversions
            
            // Estimated spend
            let estimatedSpend = Double(flyers) * 0.50
            let roi = 0.0
            
            comparisons.append(PhaseComparison(
                cycleName: cycle.cycleName,
                startDate: cycle.startDate,
                endDate: cycle.endDate,
                touches: cycleTouches.count,
                flyers: flyers,
                knocks: knocks,
                scans: scans,
                leads: cycleLeads.count,
                conversions: conversions,
                spend: estimatedSpend,
                roi: roi
            ))
        }
        
        return comparisons
    }

    static func comparePhases(
        phases: [FarmPhase],
        touches: [FarmTouch],
        leads: [FarmLead]
    ) -> [PhaseComparison] {
        let cycles = phases.enumerated().map { index, phase in
            let phaseTouches = touches.filter { touch in
                touch.date >= phase.startDate && touch.date <= phase.endDate
            }
            return FarmCycle(
                farmId: phase.farmId,
                cycleNumber: index + 1,
                startDate: phase.startDate,
                endDate: phase.endDate,
                touchCount: phaseTouches.count,
                completedTouchCount: phaseTouches.filter(\.completed).count,
                results: phase.results
            )
        }

        return compareCycles(cycles: cycles, touches: touches, leads: leads)
    }
}
