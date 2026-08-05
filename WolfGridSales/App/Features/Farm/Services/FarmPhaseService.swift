import Foundation

actor FarmPhaseService {
    static let shared = FarmPhaseService()

    private let cycleService = FarmCycleService.shared

    private init() {}

    func calculatePhases(farm: Farm) async throws -> [FarmPhase] {
        let cycles = try await cycleService.calculateCycles(farm: farm)
        return cycles.map { cycle in
            FarmPhase(
                farmId: cycle.farmId,
                phaseName: cycle.cycleName,
                startDate: cycle.startDate,
                endDate: cycle.endDate,
                results: cycle.results
            )
        }
    }

    func fetchPhases(farmId: UUID) async throws -> [FarmPhase] {
        let cycles = try await cycleService.fetchCycles(farmId: farmId)
        return cycles.map { cycle in
            FarmPhase(
                farmId: cycle.farmId,
                phaseName: cycle.cycleName,
                startDate: cycle.startDate,
                endDate: cycle.endDate,
                results: cycle.results
            )
        }
    }

    func fetchPhase(id: UUID) async throws -> FarmPhase? {
        _ = id
        return nil
    }

    func updatePhaseResults(phaseId: UUID, results: [String: AnyCodable]) async throws -> FarmPhase {
        _ = phaseId
        _ = results
        throw NSError(
            domain: "FarmPhaseService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Farm phases are deprecated. Update cycle results instead."]
        )
    }

    func deletePhase(id: UUID) async throws {
        _ = id
    }
}
