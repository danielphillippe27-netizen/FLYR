import Foundation

/// Legacy phase helpers retained for compatibility while farm analytics migrate to cycles.
enum PhaseCalculator {
    static func calculatePhases(
        startDate: Date,
        endDate: Date,
        farmId: UUID
    ) -> [FarmPhase] {
        [
            FarmPhase(
                farmId: farmId,
                phaseName: "Cycle 1",
                startDate: startDate,
                endDate: endDate
            )
        ]
    }

    static func groupTouchesIntoPhases(
        touches: [FarmTouch],
        phases: [FarmPhase]
    ) -> [UUID: [FarmTouch]] {
        var phaseTouches: [UUID: [FarmTouch]] = [:]

        for phase in phases {
            phaseTouches[phase.id] = touches.filter { touch in
                touch.date >= phase.startDate && touch.date <= phase.endDate
            }
        }

        return phaseTouches
    }

    static func calculatePhaseMetrics(
        phase: FarmPhase,
        touches: [FarmTouch],
        leads: [FarmLead]
    ) -> [String: AnyCodable] {
        let phaseTouches = touches.filter { touch in
            touch.date >= phase.startDate && touch.date <= phase.endDate
        }

        let phaseLeads = leads.filter { lead in
            guard let touchId = lead.touchId,
                  let touch = touches.first(where: { $0.id == touchId }) else {
                return false
            }
            return touch.date >= phase.startDate && touch.date <= phase.endDate
        }

        let flyers = phaseTouches.filter { $0.type == .flyer }.count
        let knocks = phaseTouches.filter { $0.type == .doorKnock }.count
        let completed = phaseTouches.filter(\.completed).count

        return [
            "flyers_delivered": AnyCodable(flyers),
            "knocks": AnyCodable(knocks),
            "scans": AnyCodable(0),
            "leads": AnyCodable(phaseLeads.count),
            "conversions": AnyCodable(0),
            "spend": AnyCodable(Double(flyers) * 0.50),
            "roi": AnyCodable(0.0),
            "completed_touches": AnyCodable(completed),
            "total_touches": AnyCodable(phaseTouches.count)
        ]
    }
}
