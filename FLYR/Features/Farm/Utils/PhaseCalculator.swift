import Foundation

/// Utility for calculating and managing farm phases
enum PhaseCalculator {
    /// Calculate phases based on farm timeframe
    static func calculatePhases(
        startDate: Date,
        endDate: Date,
        farmId: UUID
    ) -> [FarmPhase] {
        let calendar = Calendar.current
        let duration = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 0
        
        var phases: [FarmPhase] = []
        
        if duration <= 2 {
            // Short farm: Single phase
            phases.append(FarmPhase(
                farmId: farmId,
                phaseName: "Awareness",
                startDate: startDate,
                endDate: endDate
            ))
        } else if duration <= 4 {
            // Medium farm: 2 phases
            if let phase1End = calendar.date(byAdding: .month, value: 2, to: startDate) {
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Awareness",
                    startDate: startDate,
                    endDate: phase1End
                ))
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Relationship Building",
                    startDate: phase1End,
                    endDate: endDate
                ))
            }
        } else if duration <= 6 {
            // Medium-long farm: 3 phases
            if let phase1End = calendar.date(byAdding: .month, value: 2, to: startDate),
               let phase2End = calendar.date(byAdding: .month, value: 4, to: startDate) {
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Awareness",
                    startDate: startDate,
                    endDate: phase1End
                ))
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Relationship Building",
                    startDate: phase1End,
                    endDate: phase2End
                ))
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Lead Harvesting",
                    startDate: phase2End,
                    endDate: endDate
                ))
            }
        } else {
            // Long farm: 4 phases
            if let phase1End = calendar.date(byAdding: .month, value: 2, to: startDate),
               let phase2End = calendar.date(byAdding: .month, value: 4, to: startDate),
               let phase3End = calendar.date(byAdding: .month, value: 6, to: startDate) {
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Awareness",
                    startDate: startDate,
                    endDate: phase1End
                ))
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Relationship Building",
                    startDate: phase1End,
                    endDate: phase2End
                ))
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Lead Harvesting",
                    startDate: phase2End,
                    endDate: phase3End
                ))
                phases.append(FarmPhase(
                    farmId: farmId,
                    phaseName: "Conversion",
                    startDate: phase3End,
                    endDate: endDate
                ))
            }
        }
        
        return phases
    }
    
    /// Group touches into phases
    static func groupTouchesIntoPhases(
        touches: [FarmTouch],
        phases: [FarmPhase]
    ) -> [UUID: [FarmTouch]] {
        var phaseTouches: [UUID: [FarmTouch]] = [:]
        
        for phase in phases {
            let phaseTouchesList = touches.filter { touch in
                touch.date >= phase.startDate && touch.date <= phase.endDate
            }
            phaseTouches[phase.id] = phaseTouchesList
        }
        
        return phaseTouches
    }
    
    /// Calculate phase metrics
    static func calculatePhaseMetrics(
        phase: FarmPhase,
        touches: [FarmTouch],
        leads: [FarmLead]
    ) -> [String: AnyCodable] {
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
        let completed = phaseTouches.filter { $0.completed }.count
        
        // Estimated spend (flyers cost $0.50 each)
        let spend = Double(flyers) * 0.50
        
        // ROI calculation (assume $1000 per conversion)
        let conversions = 0 // TODO: Integrate with conversions tracking
        let roi = conversions > 0 ? (Double(conversions) * 1000.0) / spend : 0.0
        
        return [
            "flyers_delivered": AnyCodable(flyers),
            "knocks": AnyCodable(knocks),
            "scans": AnyCodable(0), // TODO: Integrate with QR scans
            "leads": AnyCodable(phaseLeads.count),
            "conversions": AnyCodable(conversions),
            "spend": AnyCodable(spend),
            "roi": AnyCodable(roi),
            "completed_touches": AnyCodable(completed),
            "total_touches": AnyCodable(phaseTouches.count)
        ]
    }
}



