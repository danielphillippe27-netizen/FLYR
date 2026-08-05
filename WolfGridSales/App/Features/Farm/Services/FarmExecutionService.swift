import Foundation

actor FarmExecutionService {
    static let shared = FarmExecutionService()

    private let farmService = FarmService.shared
    private let touchService = FarmTouchService.shared

    private init() {}

    func executionContext(for touch: FarmTouch) async throws -> FarmExecutionContext? {
        guard let campaignId = touch.campaignId else {
            return nil
        }

        guard let farm = try await farmService.fetchFarm(id: touch.farmId) else {
            return nil
        }

        let allTouches = try await touchService.fetchTouches(farmId: touch.farmId)
        let cycleNumber = FarmCycleResolver.resolveCycleNumber(
            for: touch,
            among: allTouches,
            touchesPerInterval: max(1, farm.touchesPerInterval ?? farm.frequency)
        )

        return FarmExecutionContext(
            farmId: farm.id,
            farmName: farm.name,
            touchId: touch.id,
            touchTitle: touch.title,
            touchDate: touch.date,
            touchType: touch.type,
            campaignId: campaignId,
            cycleNumber: cycleNumber,
            cycleName: "Cycle \(cycleNumber)"
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
            cycleNumber: context.cycleNumber,
            sessionId: sessionId,
            completedByUserId: userId,
            completedAt: completedAt,
            metrics: metrics
        )
    }

    func refreshCycleResults(for farmId: UUID) async throws {
        _ = farmId
    }
}
