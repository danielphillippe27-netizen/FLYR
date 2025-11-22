import Foundation
import Supabase

actor StatsService {
    static let shared = StatsService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch User Stats
    
    func fetchUserStats(userID: UUID) async throws -> UserStats? {
        let response: [UserStats] = try await client
            .from("user_stats")
            .select()
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Upsert User Stats
    
    func upsertUserStats(_ stats: UserStats) async throws {
        try await client
            .from("user_stats")
            .upsert(stats, onConflict: "user_id")
            .execute()
    }
    
    // MARK: - Update Specific Stat Field
    
    func updateStat(userID: UUID, field: String, value: Any) async throws {
        // Use AnyCodable for proper encoding
        let updateValue: AnyCodable = AnyCodable(value)
        
        try await client
            .from("user_stats")
            .update([field: updateValue])
            .eq("user_id", value: userID)
            .execute()
    }
}

