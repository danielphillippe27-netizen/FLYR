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

    // MARK: - Apple Health
    @Published var syncSteps: Bool {
        didSet { UserDefaults.standard.set(syncSteps, forKey: Keys.syncSteps) }
    }
    @Published var todaySteps: Int?
    @Published var healthError: String?
    @Published var isLoadingSteps = false

    private enum Keys {
        static let syncSteps = "settings.syncSteps"
    }

    private let settingsService = SettingsService.shared
    private let supabase = SupabaseManager.shared.client

    init() {
        self.syncSteps = UserDefaults.standard.bool(forKey: Keys.syncSteps)
    }

    func loadSettings(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            settings = try await settingsService.fetchUserSettings(userID: userID)
            await loadProfile(userID: userID)
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
            profile = result
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

    // MARK: - Apple Health

    func toggleHealthSync(_ enabled: Bool) {
        healthError = nil
        if enabled {
            Task { await enableHealthSync() }
        } else {
            todaySteps = nil
        }
    }

    func refreshStepsIfEnabled() {
        guard syncSteps else { return }
        Task { await loadSteps() }
    }

    private func enableHealthSync() async {
        do {
            try await HealthKitManager.shared.requestStepReadAuthorization()
            await loadSteps()
        } catch {
            syncSteps = false
            todaySteps = nil
            healthError = error.localizedDescription
        }
    }

    private func loadSteps() async {
        isLoadingSteps = true
        defer { isLoadingSteps = false }
        do {
            let steps = try await HealthKitManager.shared.fetchTodaySteps()
            todaySteps = steps
        } catch {
            todaySteps = nil
            healthError = error.localizedDescription
        }
    }
}

