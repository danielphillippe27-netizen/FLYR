import Foundation
import Combine
import SwiftUI

@MainActor
final class AppUIState: ObservableObject {
    @Published var showTabBar: Bool = true
    @Published var colorScheme: ColorScheme? = nil // nil = system default
    /// Selected main tab: 0 Campaigns, 1 Map, 2 Record, 3 Leads, 4 Stats, 5 Settings.
    @Published var selectedTabIndex: Int = 0
    /// Campaign selected on Map tab; Record tab turns red and tapping Record opens this campaign.
    @Published var selectedMapCampaignId: UUID?
    @Published var selectedMapCampaignName: String?
    
    private let settingsService = SettingsService.shared
    
    /// Load user's appearance preference from settings
    func loadAppearancePreference(userID: UUID) async {
        do {
            if let settings = try await settingsService.fetchUserSettings(userID: userID) {
                // Apply user's preference
                colorScheme = settings.dark_mode ? .dark : .light
            } else {
                // No user preference set, detect system appearance
                detectSystemAppearance()
            }
        } catch {
            print("❌ Error loading appearance preference: \(error)")
            // Fallback to system appearance
            detectSystemAppearance()
        }
    }
    
    /// Detect and apply system appearance
    func detectSystemAppearance() {
        // Get the current system appearance from the main window if available
        // Otherwise fall back to current trait collection
        let systemAppearance: UIUserInterfaceStyle
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            systemAppearance = window.traitCollection.userInterfaceStyle
        } else {
            systemAppearance = UITraitCollection.current.userInterfaceStyle
        }
        colorScheme = systemAppearance == .dark ? .dark : .light
    }
    
    /// Update appearance preference
    func updateAppearancePreference(userID: UUID, isDarkMode: Bool) async {
        colorScheme = isDarkMode ? .dark : .light
        
        // Save to database
        do {
            try await settingsService.updateSetting(userID: userID, key: "dark_mode", value: isDarkMode)
        } catch {
            print("❌ Error saving appearance preference: \(error)")
        }
    }
}
