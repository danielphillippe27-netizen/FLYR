import Foundation

actor FarmExecutionService {
    static let shared = FarmExecutionService()

    private let farmService = FarmService.shared
    private let cycleService = FarmCycleService.shared
    private let touchService = FarmTouchService.shared
    private let leadService = FarmLeadService.shared

    private init() {}

    func executionContext(for touch: FarmTouch) async throws -> FarmExecutionContext? {
        guard let campaignId = touch.campaignId else {
            return nil
        }

        guard let farm = try await farmService.fetchFarm(id: touch.farmId) else {
            return nil
        }

        let cycles = try await cycleService.fetchCycles(farmId: touch.farmId)
        let cycle = cycles.first(where: { touch.date >= $0.startDate && touch.date <= $0.endDate })

        return FarmExecutionContext(
            farmId: farm.id,
            farmName: farm.name,
            touchId: touch.id,
            touchTitle: touch.title,
            touchDate: touch.date,
            touchType: touch.type,
            campaignId: campaignId,
            phaseId: cycle?.id,
            phaseName: cycle?.cycleName
        )
    }

    func completeExecution(
        context: FarmExecutionContext,
        sessionId: UUID,
        userId: UUID,
        completedAt: Date,
        metrics: [String: AnyCodable]
    ) async throws {
        _ = try await touchService.markExecuted(
            touchId: context.touchId,
            phaseId: context.phaseId,
            sessionId: sessionId,
            completedByUserId: userId,
            completedAt: completedAt,
            metrics: metrics
        )

        try await refreshCycleResults(for: context.farmId)
    }

    func refreshCycleResults(for farmId: UUID) async throws {
        let cycles = try await cycleService.fetchCycles(farmId: farmId)
        guard !cycles.isEmpty else { return }

        let touches = try await touchService.fetchTouches(farmId: farmId)
        let leads = try await leadService.fetchLeads(farmId: farmId)

        for cycle in cycles {
            let cycleTouches = touches.filter { touch in
                if let phaseId = touch.phaseId {
                    return phaseId == cycle.id
                }
                return touch.date >= cycle.startDate && touch.date <= cycle.endDate
            }

            let touchIds = Set(cycleTouches.map(\.id))
            let cycleLeads = leads.filter { lead in
                guard let touchId = lead.touchId else { return false }
                return touchIds.contains(touchId)
            }

            let completedTouches = cycleTouches.filter(\.completed)
            let uniqueSessionCount = Set(completedTouches.compactMap(\.sessionId)).count
            let uniqueUserCount = Set(completedTouches.compactMap(\.completedByUserId)).count

            let results: [String: AnyCodable] = [
                "planned_touches": AnyCodable(cycleTouches.count),
                "completed_touches": AnyCodable(completedTouches.count),
                "flyers_delivered": AnyCodable(completedTouches.filter { $0.type == .flyer }.count),
                "knocks": AnyCodable(completedTouches.filter { $0.type == .doorKnock }.count),
                "sessions": AnyCodable(uniqueSessionCount),
                "users": AnyCodable(uniqueUserCount),
                "leads": AnyCodable(cycleLeads.count)
            ]

            _ = try await cycleService.updateCycleResults(cycleId: cycle.id, results: results)
        }
    }
}
