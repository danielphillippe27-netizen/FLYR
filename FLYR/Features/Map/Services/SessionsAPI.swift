import Foundation
import Supabase

/// API service for fetching user sessions
final class SessionsAPI {
    static let shared = SessionsAPI()
    private let client = SupabaseManager.shared.client
    
    private init() {}
    
    /// Fetch user sessions ordered by start time (most recent first)
    /// - Parameters:
    ///   - userId: The user ID to fetch sessions for
    ///   - limit: Maximum number of sessions to return (default: 20)
    /// - Returns: Array of session records
    func fetchUserSessions(userId: UUID, limit: Int = 20) async throws -> [SessionRecord] {
        let response = try await client
            .from("sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("start_time", ascending: false)
            .limit(limit)
            .execute()
        
        // Decode with proper date handling
        let decoder = JSONDecoder.supabaseDates
        let sessions = try decoder.decode([SessionRecord].self, from: response.data)
        
        return sessions
    }
}

