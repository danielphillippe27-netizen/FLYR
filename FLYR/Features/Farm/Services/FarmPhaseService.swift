import Foundation
import Supabase

actor FarmPhaseService {
    static let shared = FarmPhaseService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Calculate Phases
    
    /// Auto-generate phases based on farm timeframe
    func calculatePhases(farm: Farm) async throws -> [FarmPhase] {
        let calendar = Calendar.current
        let startDate = farm.startDate
        let endDate = farm.endDate
        let duration = calendar.dateComponents([.month], from: startDate, to: endDate).month ?? 0
        
        var phases: [FarmPhase] = []
        
        if duration <= 2 {
            // Short farm: Single phase
            phases.append(FarmPhase(
                farmId: farm.id,
                phaseName: "Awareness",
                startDate: startDate,
                endDate: endDate
            ))
        } else if duration <= 4 {
            // Medium farm: 2 phases
            if let phase1End = calendar.date(byAdding: .month, value: 2, to: startDate) {
                phases.append(FarmPhase(
                    farmId: farm.id,
                    phaseName: "Awareness",
                    startDate: startDate,
                    endDate: phase1End
                ))
                phases.append(FarmPhase(
                    farmId: farm.id,
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
                    farmId: farm.id,
                    phaseName: "Awareness",
                    startDate: startDate,
                    endDate: phase1End
                ))
                phases.append(FarmPhase(
                    farmId: farm.id,
                    phaseName: "Relationship Building",
                    startDate: phase1End,
                    endDate: phase2End
                ))
                phases.append(FarmPhase(
                    farmId: farm.id,
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
                    farmId: farm.id,
                    phaseName: "Awareness",
                    startDate: startDate,
                    endDate: phase1End
                ))
                phases.append(FarmPhase(
                    farmId: farm.id,
                    phaseName: "Relationship Building",
                    startDate: phase1End,
                    endDate: phase2End
                ))
                phases.append(FarmPhase(
                    farmId: farm.id,
                    phaseName: "Lead Harvesting",
                    startDate: phase2End,
                    endDate: phase3End
                ))
                phases.append(FarmPhase(
                    farmId: farm.id,
                    phaseName: "Conversion",
                    startDate: phase3End,
                    endDate: endDate
                ))
            }
        }
        
        // Create phases in database
        return try await createPhases(phases)
    }
    
    // MARK: - Fetch Phases
    
    func fetchPhases(farmId: UUID) async throws -> [FarmPhase] {
        let response: [FarmPhase] = try await client
            .from("farm_phases")
            .select()
            .eq("farm_id", value: farmId)
            .order("start_date", ascending: true)
            .execute()
            .value
        
        return response
    }
    
    func fetchPhase(id: UUID) async throws -> FarmPhase? {
        let response: [FarmPhase] = try await client
            .from("farm_phases")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Create Phases
    
    private func createPhases(_ phases: [FarmPhase]) async throws -> [FarmPhase] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        let insertData: [[String: AnyCodable]] = phases.map { phase in
            var data: [String: AnyCodable] = [
                "farm_id": AnyCodable(phase.farmId.uuidString),
                "phase_name": AnyCodable(phase.phaseName),
                "start_date": AnyCodable(dateFormatter.string(from: phase.startDate)),
                "end_date": AnyCodable(dateFormatter.string(from: phase.endDate)),
                "results": AnyCodable(phase.results ?? [:])
            ]
            
            if let campaignId = phase.campaignId {
                data["campaign_id"] = AnyCodable(campaignId.uuidString)
            }
            
            return data
        }
        
        let response: [FarmPhase] = try await client
            .from("farm_phases")
            .insert(insertData)
            .select()
            .execute()
            .value
        
        return response
    }
    
    // MARK: - Update Phase Results
    
    func updatePhaseResults(phaseId: UUID, results: [String: AnyCodable]) async throws -> FarmPhase {
        let updateData: [String: AnyCodable] = [
            "results": AnyCodable(results)
        ]
        
        let response: [FarmPhase] = try await client
            .from("farm_phases")
            .update(updateData)
            .eq("id", value: phaseId)
            .select()
            .execute()
            .value
        
        guard let updated = response.first else {
            throw NSError(domain: "FarmPhaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update phase"])
        }
        
        return updated
    }
    
    // MARK: - Delete Phase
    
    func deletePhase(id: UUID) async throws {
        try await client
            .from("farm_phases")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}



