import Foundation
import Combine
import SwiftUI
import CoreLocation

struct PendingLiveInviteHandoff: Identifiable, Equatable {
    let id = UUID()
    let campaignId: UUID
    let campaignName: String?
    let sourceSessionId: UUID?
}

struct PendingSalespersonLeadListSelection: Identifiable, Equatable {
    let id = UUID()
    let listId: String?
    let listTitle: String?
}

struct PendingSalespersonDiallerListSelection: Identifiable, Equatable {
    let id = UUID()
    let listId: String?
    let listTitle: String?
}

@MainActor
final class AppUIState: ObservableObject {
    @Published var showTabBar: Bool = true
    @Published private(set) var calendarTabPresentationDepth: Int = 0
    @Published var colorScheme: ColorScheme? = nil // nil = system default
    /// Selected main-tab index. Each app target maps the index to its own tab set.
    @Published var selectedTabIndex: Int = 0
    /// Campaign selected for the Session tab; the tab can show a filled icon and open this campaign.
    @Published var selectedMapCampaignId: UUID?
    @Published var selectedMapCampaignName: String?
    @Published var selectedMapCampaignBoundaryCoordinates: [CLLocationCoordinate2D] = []
    @Published var selectedRouteWorkContext: RouteWorkContext?
    @Published var plannedFarmExecution: FarmExecutionContext?
    @Published var pendingLiveInviteHandoff: PendingLiveInviteHandoff?
    @Published var pendingSalespersonLeadListSelection: PendingSalespersonLeadListSelection?
    @Published var pendingSalespersonDiallerListSelection: PendingSalespersonDiallerListSelection?
    @Published private(set) var campaignCreationPresentationDepth: Int = 0

    var isCampaignCreationFlowPresented: Bool {
        campaignCreationPresentationDepth > 0
    }

    var isCalendarTabPresented: Bool {
        calendarTabPresentationDepth > 0
    }
    
    private let settingsService = SettingsService.shared
    private let localStorage = LocalStorage.shared

    init() {
        if let persistedSelection = localStorage.loadMapSelection() {
            selectedMapCampaignId = persistedSelection.campaignId
            selectedMapCampaignName = persistedSelection.campaignName
            selectedMapCampaignBoundaryCoordinates = persistedSelection.boundaryCoordinates.map(\.clLocationCoordinate)
        }
    }
    
    /// Load user's appearance preference from settings
    func loadAppearancePreference(userID: UUID) async {
        do {
            if let settings = try await settingsService.fetchUserSettings(userID: userID) {
                guard !Task.isCancelled else { return }
                // Apply user's preference
                colorScheme = settings.dark_mode ? .dark : .light
            } else {
                guard !Task.isCancelled else { return }
                // No user preference set, detect system appearance
                detectSystemAppearance()
            }
        } catch is CancellationError {
            return
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

    func selectCampaign(
        id: UUID?,
        name: String?,
        boundaryCoordinates: [CLLocationCoordinate2D] = [],
        preservePendingLiveInviteHandoff: Bool = false
    ) {
        let previousCampaignId = selectedMapCampaignId
        let validBoundaryCoordinates = boundaryCoordinates.filter(CLLocationCoordinate2DIsValid)
        selectedMapCampaignId = id
        selectedMapCampaignName = name
        if id == nil {
            selectedMapCampaignBoundaryCoordinates = []
        } else if !validBoundaryCoordinates.isEmpty {
            selectedMapCampaignBoundaryCoordinates = validBoundaryCoordinates
        } else if previousCampaignId != id {
            selectedMapCampaignBoundaryCoordinates = []
        }
        selectedRouteWorkContext = nil
        persistMapSelection()
        if preservePendingLiveInviteHandoff,
           pendingLiveInviteHandoff?.campaignId == id {
            return
        }
        pendingLiveInviteHandoff = nil
    }

    func selectRoute(_ context: RouteWorkContext) {
        selectedMapCampaignId = context.campaignId
        selectedMapCampaignName = context.routeName
        selectedMapCampaignBoundaryCoordinates = []
        selectedRouteWorkContext = context
        persistMapSelection()
        pendingLiveInviteHandoff = nil
    }

    func clearMapSelection() {
        selectedMapCampaignId = nil
        selectedMapCampaignName = nil
        selectedMapCampaignBoundaryCoordinates = []
        selectedRouteWorkContext = nil
        localStorage.clearMapSelection()
        pendingLiveInviteHandoff = nil
    }

    func beginPlannedFarmExecution(_ context: FarmExecutionContext) {
        plannedFarmExecution = context
        selectedMapCampaignId = context.campaignId
        selectedMapCampaignName = context.touchTitle
        selectedMapCampaignBoundaryCoordinates = []
        selectedRouteWorkContext = nil
        persistMapSelection()
        pendingLiveInviteHandoff = nil
    }

    func clearPlannedFarmExecution() {
        plannedFarmExecution = nil
    }

    func beginLiveInviteHandoff(campaignId: UUID, name: String?, sourceSessionId: UUID?) {
        selectedTabIndex = 1
        selectedMapCampaignId = campaignId
        selectedMapCampaignName = name
        selectedMapCampaignBoundaryCoordinates = []
        selectedRouteWorkContext = nil
        persistMapSelection()
        pendingLiveInviteHandoff = PendingLiveInviteHandoff(
            campaignId: campaignId,
            campaignName: name,
            sourceSessionId: sourceSessionId
        )
    }

    func clearPendingLiveInviteHandoff(campaignId: UUID? = nil) {
        guard let pendingLiveInviteHandoff else { return }
        guard campaignId == nil || pendingLiveInviteHandoff.campaignId == campaignId else { return }
        self.pendingLiveInviteHandoff = nil
    }

    func openSalespersonLeadList(id: String?, title: String?) {
        let cleanId = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSalespersonLeadListSelection = PendingSalespersonLeadListSelection(
            listId: cleanId?.isEmpty == false ? cleanId : nil,
            listTitle: cleanTitle?.isEmpty == false ? cleanTitle : nil
        )
        selectedTabIndex = 5
    }

    func openSalespersonDiallerList(id: String?, title: String?) {
        let cleanId = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingSalespersonDiallerListSelection = PendingSalespersonDiallerListSelection(
            listId: cleanId?.isEmpty == false ? cleanId : nil,
            listTitle: cleanTitle?.isEmpty == false ? cleanTitle : nil
        )
        selectedTabIndex = 1
    }

    func beginCalendarTabPresentation() {
        calendarTabPresentationDepth += 1
    }

    func endCalendarTabPresentation() {
        calendarTabPresentationDepth = max(0, calendarTabPresentationDepth - 1)
    }

    func campaignCreationFlowDidAppear() {
        campaignCreationPresentationDepth += 1
    }

    func campaignCreationFlowDidDisappear() {
        campaignCreationPresentationDepth = max(0, campaignCreationPresentationDepth - 1)
    }

    func updateSelectedCampaignBoundary(campaignId: UUID, coordinates: [CLLocationCoordinate2D]) {
        guard selectedMapCampaignId == campaignId else { return }
        let validCoordinates = coordinates.filter(CLLocationCoordinate2DIsValid)
        guard !validCoordinates.isEmpty else { return }
        selectedMapCampaignBoundaryCoordinates = validCoordinates
        persistMapSelection()
    }

    private func persistMapSelection() {
        guard let selectedMapCampaignId else {
            localStorage.clearMapSelection()
            return
        }
        localStorage.saveMapSelection(
            campaignId: selectedMapCampaignId,
            campaignName: selectedMapCampaignName,
            boundaryCoordinates: selectedMapCampaignBoundaryCoordinates
        )
    }
}
