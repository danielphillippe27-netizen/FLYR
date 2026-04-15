import Foundation
import Supabase

actor FarmCycleService {
    static let shared = FarmCycleService()

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private init() {}

    func calculateCycles(farm: Farm) async throws -> [FarmCycle] {
        let calendar = Calendar.current
        let startDate = farm.startDate
        let endDate = farm.endDate
        let duration = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 0

        var cycles: [FarmCycle] = []

        if duration <= 2 {
            cycles.append(FarmCycle(
                farmId: farm.id,
                cycleName: "Cycle 1",
                startDate: startDate,
                endDate: endDate
            ))
        } else if duration <= 4 {
            if let cycle1End = calendar.date(byAdding: .month, value: 2, to: startDate) {
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 1",
                    startDate: startDate,
                    endDate: cycle1End
                ))
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 2",
                    startDate: cycle1End,
                    endDate: endDate
                ))
            }
        } else if duration <= 6 {
            if let cycle1End = calendar.date(byAdding: .month, value: 2, to: startDate),
               let cycle2End = calendar.date(byAdding: .month, value: 4, to: startDate) {
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 1",
                    startDate: startDate,
                    endDate: cycle1End
                ))
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 2",
                    startDate: cycle1End,
                    endDate: cycle2End
                ))
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 3",
                    startDate: cycle2End,
                    endDate: endDate
                ))
            }
        } else {
            if let cycle1End = calendar.date(byAdding: .month, value: 2, to: startDate),
               let cycle2End = calendar.date(byAdding: .month, value: 4, to: startDate),
               let cycle3End = calendar.date(byAdding: .month, value: 6, to: startDate) {
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 1",
                    startDate: startDate,
                    endDate: cycle1End
                ))
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 2",
                    startDate: cycle1End,
                    endDate: cycle2End
                ))
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 3",
                    startDate: cycle2End,
                    endDate: cycle3End
                ))
                cycles.append(FarmCycle(
                    farmId: farm.id,
                    cycleName: "Cycle 4",
                    startDate: cycle3End,
                    endDate: endDate
                ))
            }
        }

        return try await createCycles(cycles)
    }

    func fetchCycles(farmId: UUID) async throws -> [FarmCycle] {
        try await client
            .from("farm_phases")
            .select()
            .eq("farm_id", value: farmId)
            .order("start_date", ascending: true)
            .execute()
            .value
    }

    func updateCycleResults(cycleId: UUID, results: [String: AnyCodable]) async throws -> FarmCycle {
        let updateData: [String: AnyCodable] = [
            "results": AnyCodable(results)
        ]

        let response: [FarmCycle] = try await client
            .from("farm_phases")
            .update(updateData)
            .eq("id", value: cycleId)
            .select()
            .execute()
            .value

        guard let updated = response.first else {
            throw NSError(domain: "FarmCycleService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update cycle"])
        }

        return updated
    }

    func deleteCycle(id: UUID) async throws {
        try await client
            .from("farm_phases")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    private func createCycles(_ cycles: [FarmCycle]) async throws -> [FarmCycle] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let insertData: [[String: AnyCodable]] = cycles.map { cycle in
            var data: [String: AnyCodable] = [
                "farm_id": AnyCodable(cycle.farmId.uuidString),
                "phase_name": AnyCodable(cycle.cycleName),
                "start_date": AnyCodable(dateFormatter.string(from: cycle.startDate)),
                "end_date": AnyCodable(dateFormatter.string(from: cycle.endDate)),
                "results": AnyCodable(cycle.results ?? [:])
            ]

            if let campaignId = cycle.campaignId {
                data["campaign_id"] = AnyCodable(campaignId.uuidString)
            }

            return data
        }

        return try await client
            .from("farm_phases")
            .insert(insertData)
            .select()
            .execute()
            .value
    }
}
