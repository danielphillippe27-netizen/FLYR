import SwiftUI
import Combine
import Supabase

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: UserSettings?
    @Published var profile: UserProfile?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let settingsService = SettingsService.shared
    private let supabase = SupabaseManager.shared.client

    func loadSettings(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            settings = try await settingsService.fetchUserSettings(userID: userID)
            guard !Task.isCancelled else { return }
            await loadProfile(userID: userID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
            print("❌ Error loading settings: \(error)")
        }
    }

    func loadProfile(userID: UUID) async {
        do {
            let result: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            guard !Task.isCancelled else { return }
            profile = result
        } catch is CancellationError {
            return
        } catch {
            profile = nil
        }
    }
    
    func updateSetting(userID: UUID, key: String, value: Any) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            try await settingsService.updateSetting(userID: userID, key: key, value: value)
            guard !Task.isCancelled else { return }
            // Reload settings to get updated values
            await loadSettings(for: userID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Failed to update setting: \(error.localizedDescription)"
            print("❌ Update failed: \(error)")
        }
    }
    
    func saveSettings(userID: UUID) async {
        guard let currentSettings = settings else { return }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            try await settingsService.upsertUserSettings(currentSettings)
            guard !Task.isCancelled else { return }
            await loadSettings(for: userID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
            print("❌ Save failed: \(error)")
        }
    }
}
