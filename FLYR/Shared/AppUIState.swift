import Foundation
import Combine
import SwiftUI

@MainActor
final class AppUIState: ObservableObject {
    @Published var showTabBar: Bool = true
    @Published var colorScheme: ColorScheme? = nil // nil = system default
    /// Selected main tab: 0 Home, 1 Session, 2 Leads, 3 Leaderboard, 4 Settings.
    @Published var selectedTabIndex: Int = 0
    /// Campaign selected for the Session tab; the tab can show a filled icon and open this campaign.
    @Published var selectedMapCampaignId: UUID?
    @Published var selectedMapCampaignName: String?
    @Published var selectedRouteWorkContext: RouteWorkContext?
    @Published var plannedFarmExecution: FarmExecutionContext?
    
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

    func selectCampaign(id: UUID?, name: String?) {
        selectedMapCampaignId = id
        selectedMapCampaignName = name
        selectedRouteWorkContext = nil
    }

    func selectRoute(_ context: RouteWorkContext) {
        selectedMapCampaignId = context.campaignId
        selectedMapCampaignName = context.routeName
        selectedRouteWorkContext = context
    }

    func clearMapSelection() {
        selectedMapCampaignId = nil
        selectedMapCampaignName = nil
        selectedRouteWorkContext = nil
    }

    func beginPlannedFarmExecution(_ context: FarmExecutionContext) {
        plannedFarmExecution = context
        selectedMapCampaignId = context.campaignId
        selectedMapCampaignName = context.touchTitle
        selectedRouteWorkContext = nil
    }

    func clearPlannedFarmExecution() {
        plannedFarmExecution = nil
    }
}
