import Foundation

/// Engine for generating farm recommendations
enum RecommendationsEngine {
    /// Generate recommendations based on farm data
    static func generateRecommendations(
        farm: Farm,
        touches: [FarmTouch],
        phases: [FarmPhase],
        leads: [FarmLead]
    ) -> [FarmRecommendation] {
        var recommendations: [FarmRecommendation] = []
        
        // Analyze touch completion rate
        let totalTouches = touches.count
        let completedTouches = touches.filter { $0.completed }.count
        let completionRate = totalTouches > 0 ? Double(completedTouches) / Double(totalTouches) : 0.0
        
        if completionRate < 0.5 && totalTouches > 5 {
            recommendations.append(FarmRecommendation(
                title: "Low Completion Rate",
                detail: "Only \(Int(completionRate * 100))% of touches are completed. Consider adjusting your schedule or reducing frequency."
            ))
        }
        
        // Analyze touch types
        let touchTypeCounts = Dictionary(grouping: touches, by: { $0.type })
        let flyerCount = touchTypeCounts[.flyer]?.count ?? 0
        let doorKnockCount = touchTypeCounts[.doorKnock]?.count ?? 0
        
        if flyerCount > doorKnockCount * 3 && flyerCount > 5 {
            recommendations.append(FarmRecommendation(
                title: "Balance Touch Types",
                detail: "You have many more flyers than door knocks. Consider adding more personal touches for better engagement."
            ))
        }
        
        // Analyze leads
        if leads.isEmpty && touches.count > 5 {
            recommendations.append(FarmRecommendation(
                title: "No Leads Yet",
                detail: "You have \(touches.count) touches but no leads. Consider adding QR codes or door knock conversations."
            ))
        }
        
        // Phase analysis
        if phases.isEmpty && touches.count > 10 {
            recommendations.append(FarmRecommendation(
                title: "Generate Phases",
                detail: "Phases help track progress through your farm lifecycle. Generate phases to get started."
            ))
        }
        
        // Frequency analysis
        if farm.frequency < 2 && touches.count > 10 {
            recommendations.append(FarmRecommendation(
                title: "Consider Increasing Frequency",
                detail: "You're doing \(farm.frequency) touch per month. Consider increasing to 2-3 for better results."
            ))
        }
        
        // Best months analysis (simplified)
        let touchesByMonth = Dictionary(grouping: touches) { touch in
            Calendar.current.component(.month, from: touch.date)
        }
        
        if let bestMonth = touchesByMonth.max(by: { $0.value.count < $1.value.count }) {
            let monthName = Calendar.current.monthSymbols[bestMonth.key - 1]
            recommendations.append(FarmRecommendation(
                title: "Best Performing Month",
                detail: "\(monthName) has the most touches. Consider maintaining this pattern."
            ))
        }
        
        return recommendations
    }
}



