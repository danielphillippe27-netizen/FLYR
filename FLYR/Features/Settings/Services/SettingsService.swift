import Foundation
import Supabase

actor SettingsService {
    static let shared = SettingsService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch User Settings
    
    func fetchUserSettings(userID: UUID) async throws -> UserSettings? {
        let response: [UserSettings] = try await client
            .from("user_settings")
            .select()
            .eq("user_id", value: userID)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    // MARK: - Upsert User Settings
    
    func upsertUserSettings(_ settings: UserSettings) async throws {
        try await client
            .from("user_settings")
            .upsert(settings, onConflict: "user_id")
            .execute()
    }
    
    // MARK: - Update Specific Setting
    
    func updateSetting(userID: UUID, key: String, value: Any) async throws {
        // Supabase Swift SDK handles encoding automatically
        // For null values, we pass NSNull which will be converted to null in JSON
        let updateValue: AnyCodable = AnyCodable(value)
        
        try await client
            .from("user_settings")
            .update([key: updateValue])
            .eq("user_id", value: userID)
            .execute()
    }
    
    // MARK: - Default Website
    
    /// Fetch user's default website URL
    func fetchDefaultWebsite(userID: UUID) async throws -> String? {
        let settings = try await fetchUserSettings(userID: userID)
        return settings?.default_website
    }
    
    /// Update user's default website URL
    func updateDefaultWebsite(userID: UUID, website: String?) async throws {
        try await updateSetting(userID: userID, key: "default_website", value: website ?? NSNull())
    }
}

