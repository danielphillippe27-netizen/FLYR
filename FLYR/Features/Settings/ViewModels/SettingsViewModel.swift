import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: UserSettings?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    
    private let settingsService = SettingsService.shared
    
    func loadSettings(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            settings = try await settingsService.fetchUserSettings(userID: userID)
        } catch {
            errorMessage = "Failed to load settings: \(error.localizedDescription)"
            print("❌ Error loading settings: \(error)")
        }
    }
    
    func updateSetting(userID: UUID, key: String, value: Any) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            try await settingsService.updateSetting(userID: userID, key: key, value: value)
            // Reload settings to get updated values
            await loadSettings(for: userID)
        } catch {
            errorMessage = "Failed to update setting: \(error.localizedDescription)"
            print("❌ Update failed: \(error)")
        }
    }
    
    func saveSettings(userID: UUID) async {
        guard var currentSettings = settings else { return }
        
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        
        do {
            try await settingsService.upsertUserSettings(currentSettings)
            await loadSettings(for: userID)
        } catch {
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
            print("❌ Save failed: \(error)")
        }
    }
}

