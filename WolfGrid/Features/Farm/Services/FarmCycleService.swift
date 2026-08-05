import Foundation

actor FarmCycleService {
    static let shared = FarmCycleService()

    private let farmService = FarmService.shared
    private let touchService = FarmTouchService.shared

    private init() {}

    func fetchCycles(farmId: UUID) async throws -> [FarmCycle] {
        guard let farm = try await farmService.fetchFarm(id: farmId) else {
            return []
        }

        let touches = try await touchService.fetchTouches(farmId: farmId)
        return buildCycles(farm: farm, touches: touches)
    }

    func calculateCycles(farm: Farm) async throws -> [FarmCycle] {
        let touches = try await touchService.fetchTouches(farmId: farm.id)
        return buildCycles(farm: farm, touches: touches)
    }

    func updateCycleResults(cycleId: String, results: [String: AnyCodable]) async throws -> FarmCycle {
        let components = cycleId.components(separatedBy: "-cycle-")
        guard components.count == 2,
              let farmId = UUID(uuidString: components[0]) else {
            throw NSError(domain: "FarmCycleService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid cycle id"])
        }

        let cycles = try await fetchCycles(farmId: farmId)
        guard let cycle = cycles.first(where: { $0.id == cycleId }) else {
            throw NSError(domain: "FarmCycleService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cycle not found"])
        }

        return FarmCycle(
            farmId: cycle.farmId,
            cycleNumber: cycle.cycleNumber,
            startDate: cycle.startDate,
            endDate: cycle.endDate,
            touchCount: cycle.touchCount,
            completedTouchCount: cycle.completedTouchCount,
            results: results
        )
    }

    func deleteCycle(id: String) async throws {
        _ = id
    }

    private func buildCycles(farm: Farm, touches: [FarmTouch]) -> [FarmCycle] {
        FarmCycleResolver.buildCycles(farm: farm, touches: touches)
    }
}
