import SwiftUI
import UIKit
import MapboxMaps
import Combine
import CoreLocation
import EventKit
import Lottie

// MARK: - Display Mode
/// Controls what's visible on the campaign map (cubes only or pins only — never both)
enum DisplayMode: String, CaseIterable, Identifiable {
    case buildings = "Buildings"
    case addresses = "Addresses"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .buildings: return "building.2"
        case .addresses: return "mappin"
        }
    }
    
    var description: String {
        switch self {
        case .buildings: return "3D building footprints"
        case .addresses: return "Address pin locations"
        }
    }
}

// MARK: - Display Mode Toggle (legacy segmented)
struct DisplayModeToggle: View {
    @Binding var mode: DisplayMode
    var compact: Bool = false
    var onChange: ((DisplayMode) -> Void)?
    
    var body: some View {
        VStack(spacing: compact ? 0 : 4) {
            Picker("Display Mode", selection: $mode) {
                ForEach(DisplayMode.allCases) { displayMode in
                    Label(displayMode.rawValue, systemImage: displayMode.icon)
                        .tag(displayMode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { oldMode, newMode in
                onChange?(newMode)
            }
            
            if !compact {
                Text(mode.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, compact ? 8 : 16)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Map layer toggle: Buildings or Pins only (never both); icons only, no labels
struct BuildingCircleToggle: View {
    @Binding var mode: DisplayMode
    var onChange: ((DisplayMode) -> Void)?
    
    private func option(_ displayMode: DisplayMode, icon: String) -> some View {
        let isSelected = mode == displayMode
        return Button {
            HapticManager.light()
            mode = displayMode
            onChange?(displayMode)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isSelected ? .black : .gray)
                .frame(width: 44, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.red : Color.black)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            option(.buildings, icon: "cube.fill")
            option(.addresses, icon: "circle.fill")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

// MARK: - Session Progress Pill (black bg, red text; tap for minimal dropdown)
struct SessionProgressPill: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isExpanded: Bool
    
    var body: some View {
        Button {
            HapticManager.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        } label: {
            Text("Progress")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Minimal Progress Dropdown (time / distance / doors + progress bar only)
struct SessionProgressDropdown: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(sessionManager.formattedElapsedTime)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text(sessionManager.formattedDistance)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    Text("\(sessionManager.completedCount)/\(sessionManager.targetCount) doors")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.25))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: max(0, geometry.size.width * sessionManager.progressPercentage))
                    }
                }
                .frame(height: 6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
            .padding(.horizontal, 8)
        }
        .padding(.top, 4)
    }
}

// MARK: - Flyer Mode Overlay (Segment + next address only)
struct FlyerModeOverlay: View {
    @ObservedObject var flyerModeManager: FlyerModeManager
    var automaticStatusForAddress: (UUID) -> AddressStatus
    var onAddressCompleted: (UUID, AddressStatus) -> Void

    var body: some View {
        if let addr = flyerModeManager.currentAddress {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next: \(addr.formatted.isEmpty ? "Address" : addr.formatted)")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 100)
            }
            .onAppear {
                flyerModeManager.automaticStatusForAddress = automaticStatusForAddress
                flyerModeManager.onAddressCompleted = onAddressCompleted
            }
            // Informational overlay only; allow top session controls and map gestures to remain interactive.
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Background access pill + info sheet (campaign map)
private struct BackgroundGPSMapPill: View {
    private let buttonSize: CGFloat = 36
    private let iconSize: CGFloat = 16

    var preSession: Bool
    var hasPersistentBackgroundLocationAccess: Bool
    var onTap: () -> Void

    private var accessibilityLabelText: String {
        if preSession {
            return "Background location information"
        }
        if hasPersistentBackgroundLocationAccess {
            return "Background location active while locked or in background"
        }
        return "Session running without background location"
    }

    var body: some View {
        Button {
            HapticManager.light()
            onTap()
        } label: {
            Image(systemName: hasPersistentBackgroundLocationAccess ? "location.fill" : "location")
                .font(.system(size: iconSize, weight: .bold))
                .foregroundColor(.green)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.88))
                )
                .overlay(
                    Circle()
                        .stroke(Color.green.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint("Shows details about location access during active sessions")
    }
}

private struct BeaconMapPill: View {
    private let buttonSize: CGFloat = 36

    var isPrepared: Bool
    var onTap: () -> Void

    private var tint: Color {
        isPrepared ? .green : .white
    }

    var body: some View {
        Button {
            HapticManager.light()
            onTap()
        } label: {
            ZStack {
                Image(systemName: "person.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tint)
                    .offset(x: -4, y: 2)

                Image(systemName: "dot.radiowaves.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                    .offset(x: 5, y: -1)
            }
            .frame(width: buttonSize, height: buttonSize)
            .background(
                Circle()
                    .fill(Color.black.opacity(0.88))
            )
            .overlay(
                Circle()
                    .stroke(tint.opacity(isPrepared ? 0.28 : 0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPrepared ? "Beacon ready for session start" : "Beacon setup")
        .accessibilityHint("Configure your safety beacon and session share link")
    }
}

/// Same chrome as `SessionProgressPill` (black rounded rect, red label) so the session top bar reads as one control family.
private struct SessionActiveInfoMapButton: View {
    var onTap: () -> Void

    var body: some View {
        Button {
            HapticManager.light()
            onTap()
        } label: {
            Text("Info")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.red)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Session map information")
        .accessibilityHint("Homes, location access, and map gestures")
    }
}

private struct BackgroundGPSInfoSheetView: View {
    enum InfoContext {
        case preSession
        case active(backgroundOn: Bool)
    }

    let context: InfoContext
    var primaryActionTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch context {
        case .preSession:
            return "Location Access"
        case .active(true):
            return "Background access active"
        case .active(false):
            return "Background access limited"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.flyrTitle2)
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                switch context {
                case .preSession:
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Location is used only during active sessions", systemImage: "location.fill.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                        Text("FLYR uses your location to track route progress, distance, and nearby targets while an active canvassing or delivery session is running.")
                            .font(.system(size: 15))
                    }
                case .active(true):
                    Text("FLYR continues route logging, distance tracking, and session progress while your device is locked or the app is in the background until you end the session.")
                        .font(.system(size: 15))
                case .active(false):
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This session is currently using location only while the app is open. Tracking and progress updates may pause when the app is locked or in the background.")
                            .font(.system(size: 15))
                        Text("You can continue to review background access for this active session, or update it later in Settings.")
                            .font(.system(size: 15))
                    }
                }
            }
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let primaryActionTitle {
                Button(primaryActionTitle) {
                    dismiss()
                    primaryAction?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .presentationDetents([.height(primaryActionTitle == nil ? 380 : 430)])
        .presentationDragIndicator(.visible)
    }
}

fileprivate enum MapEditToolMode: String, Equatable {
    case addHouse

    var title: String {
        switch self {
        case .addHouse:
            return "Add House"
        }
    }

    var instructions: String {
        switch self {
        case .addHouse:
            return "Tap to place the cylinder, tap again to move it, then continue to save the house."
        }
    }
}

enum LocationCardToolsAction {
    case addHouse
    case addVisit
    case resetHome
    case deleteManualShape
}

fileprivate struct ManualShapeContext {
    let buildingId: String?
    let addressId: UUID?
    let addressSource: String?
    let seedCoordinate: CLLocationCoordinate2D?
    let addressText: String?
}

fileprivate struct PendingManualAddressDraft: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let linkedBuildingId: String?
    let prefilledAddressText: String?
}

fileprivate struct PendingManualAddressConfirmation {
    let addressId: UUID
    let coordinate: CLLocationCoordinate2D
}

/// Campaign Map View with 3D buildings, roads, and addresses
/// Mirrors FLYR-PRO's CampaignDetailMapView.tsx functionality
struct CampaignMapView: View {
    private static let manualAddressConfirmationRetryCount = 5
    private static let manualAddressConfirmationRetryDelayNs: UInt64 = 750_000_000

    private struct PendingFlyerStart {
        let campaignId: UUID
        let mode: SessionMode
        let goalAmount: Int
        let farmExecutionContext: FarmExecutionContext?
    }

    let campaignId: String
    let routeWorkContext: RouteWorkContext?
    let quickStartEnabled: Bool
    let showPreSessionStartButton: Bool
    let demoLaunchConfiguration: DemoSessionLaunchConfiguration?
    /// When set (e.g. Map tab / fullscreen preview), shows the white dismiss control top-trailing beside the GPS pill.
    let onDismissFromMap: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var uiState: AppUIState

    /// Default center when no campaign data yet (Toronto)
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)

    /// Avoid passing non-finite sizes into Mapbox (prevents 64×64 fallback / `contentScaleFactor` nan warnings).
    private static func sanitizedMapContainerSize(_ size: CGSize) -> CGSize {
        let w = size.width
        let h = size.height
        guard w.isFinite, h.isFinite, w > 0, h > 0 else {
            return CGSize(width: 320, height: 260)
        }
        return size
    }

    @StateObject private var featuresService = MapFeaturesService.shared
    @State private var mapView: MapView?
    @State private var layerManager: MapLayerManager?
    @State private var selectedBuilding: BuildingProperties?
    @State private var selectedAddress: MapLayerManager.AddressTapResult?
    /// When the location card shows multiple addresses, the user can pick one; this tracks the selected unit (nil = show list)
    @State private var selectedAddressIdForCard: UUID?
    @State private var showLocationCard = false
    @State private var showLeadCaptureSheet = false
    @State private var hasFlownToCampaign = false
    @State private var statsSubscriber: BuildingStatsSubscriber?
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var showTargetsSheet = false
    @State private var statsExpanded = false
    @State private var dragOffset: CGFloat = 0
    @State private var focusBuildingId: String?
    @StateObject private var demoSessionSimulator = DemoSessionSimulator()
    @State private var hasStartedDemoLaunch = false
    @State private var demoPulseTick = 0

    // Status filters
    @State private var showQrScanned = true
    @State private var showConversations = true
    @State private var showTouched = true
    @State private var showUntouched = true
    // Display mode: Buildings only or Pins only (never both)
    @State private var displayMode: DisplayMode = .buildings
    @State private var showEndSessionConfirmation = false
    @State private var pendingFlyerStart: PendingFlyerStart?
    @State private var keyboardHeight: CGFloat = 0
    /// Per-address visit statuses (populated from VisitsAPI and updated live via onStatusUpdated)
    @State private var addressStatuses: [UUID: AddressStatus] = [:]
    @State private var statusRefreshTask: Task<Void, Never>?
    @State private var lastStatusRefreshKey: String?
    /// Coalesces rapid `updateMapData` churn; any `scheduleLoadedStatusesRefresh(forceRefresh: true)` in the window wins.
    @State private var pendingStatusRefreshWantsForce = false
    @State private var lastLayerVisibilitySignature: String?
    /// Maps building gersId → ordered address UUIDs (used for townhouse list order and split-status overlays)
    @State private var buildingAddressMap: [String: [UUID]] = [:]
    @StateObject private var flyerModeManager = FlyerModeManager()
    @StateObject private var beaconService = SessionSafetyBeaconService.shared
    @State private var quickStartStartingMode: SessionMode?
    @State private var preSessionSelectedMode: SessionMode = .doorKnocking
    @State private var preSessionGoalAmount: Int?
    @State private var showSessionStartGateAlert = false
    @State private var sessionStartGateMessage = ""
    @State private var showLocationPermissionAlert = false
    @State private var locationPermissionAlertMessage = ""
    @State private var showBackgroundGPSSheet = false
    @State private var showBeaconSheet = false
    @State private var showGoalSheet = false
    @State private var showActiveSessionInfoSheet = false
    @State private var lastLoadedDataKey: String?
    @State private var subscribedRealtimeCampaignId: UUID?
    @State private var activeMapEditTool: MapEditToolMode?
    @State private var manualShapeContext: ManualShapeContext?
    @State private var manualAddressPlacement: CLLocationCoordinate2D?
    @State private var pendingManualAddressDraft: PendingManualAddressDraft?
    @State private var pendingManualAddressConfirmation: PendingManualAddressConfirmation?
    @State private var manualAddressConfirmationTask: Task<Void, Never>?
    @State private var manualShapeMessage: String?

    init(
        campaignId: String,
        routeWorkContext: RouteWorkContext? = nil,
        quickStartEnabled: Bool = false,
        showPreSessionStartButton: Bool = true,
        demoLaunchConfiguration: DemoSessionLaunchConfiguration? = nil,
        onDismissFromMap: (() -> Void)? = nil
    ) {
        self.campaignId = campaignId
        self.routeWorkContext = routeWorkContext
        self.quickStartEnabled = quickStartEnabled
        self.showPreSessionStartButton = showPreSessionStartButton
        self.demoLaunchConfiguration = demoLaunchConfiguration
        self.onDismissFromMap = onDismissFromMap
        // Match default campaign map: buildings first; `startPreSessionWorkflow` switches to addresses when needed.
        _displayMode = State(initialValue: .buildings)
    }

    var body: some View {
        campaignMapContent
    }

    private var activeRouteWorkContext: RouteWorkContext? {
        guard let routeWorkContext,
              routeWorkContext.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame else {
            return nil
        }
        return routeWorkContext
    }

    private var matchingPlannedFarmExecution: FarmExecutionContext? {
        guard let planned = uiState.plannedFarmExecution else { return nil }
        guard planned.campaignId.uuidString.caseInsensitiveCompare(campaignId) == .orderedSame else {
            return nil
        }
        return planned
    }

    private var currentMapLoadKey: String {
        if let scope = activeRouteWorkContext {
            return "\(campaignId.lowercased())|route|\(scope.assignmentId.uuidString.lowercased())"
        }
        return "\(campaignId.lowercased())|campaign"
    }

    private var visibleBuildingFeatures: [BuildingFeature] {
        let allBuildings = featuresService.buildings?.features ?? []
        guard let activeRouteWorkContext else { return allBuildings }

        let addressIds = activeRouteWorkContext.normalizedAddressIdSet
        let buildingIds = activeRouteWorkContext.normalizedBuildingIdentifierSet

        let filtered = allBuildings.filter { feature in
            if let addressId = RouteWorkContext.normalizedIdentifier(feature.properties.addressId),
               addressIds.contains(addressId) {
                return true
            }

            let candidateIds = feature.properties.buildingIdentifierCandidates
                .compactMap(RouteWorkContext.normalizedIdentifier)
            return candidateIds.contains { buildingIds.contains($0) }
        }

        return filtered.sortedByRouteScope(activeRouteWorkContext)
    }

    private var visibleAddressFeatures: [AddressFeature] {
        let allAddresses = featuresService.addresses?.features ?? []
        guard let activeRouteWorkContext else { return allAddresses }

        let addressIds = activeRouteWorkContext.normalizedAddressIdSet
        let buildingOnlyIds = activeRouteWorkContext.normalizedBuildingOnlyIdentifierSet

        let filtered = allAddresses.filter { feature in
            if let addressId = RouteWorkContext.normalizedIdentifier(feature.properties.id ?? feature.id),
               addressIds.contains(addressId) {
                return true
            }

            let buildingCandidates = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap(RouteWorkContext.normalizedIdentifier)
            return buildingCandidates.contains { buildingOnlyIds.contains($0) }
        }

        return filtered.sortedByRouteScope(activeRouteWorkContext)
    }

    private var buildingSessionTargets: [ResolvedCampaignTarget] {
        if let activeRouteWorkContext {
            return routeScopedSessionTargets(for: activeRouteWorkContext)
        }

        return CampaignTargetResolver.buildingTargets(from: visibleBuildingFeatures)
    }

    private var preferredSessionTargets: [ResolvedCampaignTarget] {
        if let activeRouteWorkContext {
            return routeScopedSessionTargets(for: activeRouteWorkContext)
        }

        return CampaignTargetResolver.preferredSessionTargets(
            buildings: visibleBuildingFeatures,
            addresses: visibleAddressFeatures
        )
    }

    private var flyerSessionTargets: [ResolvedCampaignTarget] {
        if let activeRouteWorkContext {
            return routeScopedSessionTargets(for: activeRouteWorkContext)
        }

        return CampaignTargetResolver.flyerTargets(
            buildings: visibleBuildingFeatures,
            addresses: visibleAddressFeatures
        )
    }

    private var campaignMapContent: some View {
        campaignMapWithAlertsAndObservers
            .sheet(isPresented: $showTargetsSheet) { nextTargetsSheetContent }
            .sheet(isPresented: $showLeadCaptureSheet, onDismiss: { selectedBuilding = nil }) {
                leadCaptureSheetContent
            }
            .sheet(isPresented: $showBackgroundGPSSheet) {
                BackgroundGPSInfoSheetView(
                    context: backgroundGPSInfoSheetContext,
                    primaryActionTitle: backgroundGPSSheetActionTitle,
                    primaryAction: backgroundGPSSheetActionTitle == nil ? nil : { handleBackgroundGPSSheetPrimaryAction() }
                )
            }
            .sheet(isPresented: $showBeaconSheet) {
                BeaconControlSheet(
                    beaconService: beaconService,
                    sessionLocation: sessionManager.currentLocation
                )
            }
            .sheet(isPresented: $showGoalSheet) {
                PreSessionGoalSheet(
                    goalAmount: Binding(
                        get: { effectivePreSessionGoalAmount },
                        set: { preSessionGoalAmount = min(max(1, $0), preSessionGoalCap) }
                    ),
                    maxGoal: preSessionGoalCap
                )
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showActiveSessionInfoSheet) {
                ActiveSessionMapInfoSheet(
                    hasPersistentBackgroundLocationAccess: sessionManager.hasPersistentBackgroundLocationAccess,
                    primaryActionTitle: backgroundGPSSheetActionTitle,
                    onPrimaryAction: backgroundGPSSheetActionTitle == nil ? nil : { handleBackgroundGPSSheetPrimaryAction() }
                )
            }
            .sheet(item: $pendingManualAddressDraft, onDismiss: {
                activeMapEditTool = nil
                manualShapeContext = nil
                manualAddressPlacement = nil
                syncManualAddressPreview()
            }) { draft in
                ManualAddressCreationSheet(
                    campaignId: campaignId,
                    draft: draft,
                    onSaved: { response, coordinate in
                        handleManualAddressSaved(response: response, coordinate: coordinate)
                        pendingManualAddressDraft = nil
                        manualShapeContext = nil
                        manualAddressPlacement = nil
                        syncManualAddressPreview()
                    },
                    onCancelled: {
                        pendingManualAddressDraft = nil
                        manualShapeContext = nil
                        manualAddressPlacement = nil
                        layerManager?.clearManualAddressPreview()
                    }
                )
            }
            .alert("Map Tools", isPresented: .init(get: { manualShapeMessage != nil }, set: { if !$0 { manualShapeMessage = nil } })) {
                Button("OK", role: .cancel) { manualShapeMessage = nil }
            } message: {
                if let manualShapeMessage { Text(manualShapeMessage) }
            }
    }

    private var shouldShowBackgroundGPSPill: Bool {
        if sessionManager.sessionId != nil { return true }
        return showPreSessionStartButton
            && sessionManager.sessionId == nil
            && !preferredSessionTargets.isEmpty
            && UUID(uuidString: campaignId) != nil
    }

    private var backgroundGPSInfoSheetContext: BackgroundGPSInfoSheetView.InfoContext {
        if sessionManager.sessionId == nil {
            return .preSession
        }
        return .active(backgroundOn: sessionManager.hasPersistentBackgroundLocationAccess)
    }

    private var backgroundGPSSheetActionTitle: String? {
        guard sessionManager.sessionId != nil,
              !sessionManager.hasPersistentBackgroundLocationAccess else {
            return nil
        }

        switch sessionManager.locationAuthorizationStatus {
        case .authorizedWhenInUse:
            return "Continue"
        case .denied, .restricted:
            return "Open Settings"
        default:
            return nil
        }
    }

    private var campaignMapWithObservers: some View {
        let baseView = campaignMapGeometry
            .alert("Are you sure?", isPresented: $showEndSessionConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("End", role: .destructive) { SessionManager.shared.stop() }
            } message: {
                Text("This will end your session. You’ll see your summary and can share the transparent card.")
            }
            .alert(
                "Couldn't end session",
                isPresented: .init(
                    get: { sessionManager.sessionEndError != nil },
                    set: { if !$0 { sessionManager.sessionEndError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { sessionManager.sessionEndError = nil }
            } message: {
                Text(sessionManager.sessionEndError ?? "Please try again.")
            }
            .alert("Allow Location Access", isPresented: $showLocationPermissionAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Open Settings") {
                    openLocationSettings()
                }
            } message: {
                Text(locationPermissionAlertMessage)
            }
            .alert(
                "Keep Tracking in Background?",
                isPresented: .init(
                    get: { sessionManager.showBackgroundLocationUpgradePrompt },
                    set: {
                        if !$0 {
                            sessionManager.dismissBackgroundLocationUpgradePrompt()
                        }
                    }
                )
            ) {
                Button("Continue") {
                    sessionManager.requestBackgroundLocationAuthorization()
                }
                Button("Not Now", role: .cancel) {
                    sessionManager.dismissBackgroundLocationUpgradePrompt()
                }
            } message: {
                Text("FLYR uses location only during an active session. Continue if you want route tracking and session progress to keep running while the app is locked or in the background.")
            }
            .alert("Session still running", isPresented: $sessionManager.showLongSessionPrompt) {
                Button("Keep Running", role: .cancel) {}
                Button("End Session", role: .destructive) {
                    SessionManager.shared.stop()
                }
            } message: {
                Text("This session has been running for a long time. End it now to save progress and prevent accidental all-day tracking.")
            }
            .onAppear {
                loadCampaignData(force: false)
                setupRealTimeSubscription()
            }
            .onChange(of: campaignId) { _, _ in
                hasFlownToCampaign = false
                lastLoadedDataKey = nil
                subscribedRealtimeCampaignId = nil
                pendingFlyerStart = nil
                lastStatusRefreshKey = nil
                pendingStatusRefreshWantsForce = false
                statusRefreshTask?.cancel()
                loadCampaignData(force: true)
                setupRealTimeSubscription()
            }
            .onChange(of: activeRouteWorkContext?.assignmentId) { _, _ in
                hasFlownToCampaign = false
                lastLoadedDataKey = nil
                lastStatusRefreshKey = nil
                statusRefreshTask?.cancel()
                loadCampaignData(force: true)
            }
            .onDisappear {
                statusRefreshTask?.cancel()
                Task { await statsSubscriber?.unsubscribe() }
                subscribedRealtimeCampaignId = nil
            }
        return applyFeatureAndSessionObservers(to: baseView)
    }

    private func applyFeatureAndSessionObservers<V: View>(to view: V) -> some View {
        view
            .onChange(of: featuresService.isLoading) { _, isLoading in
                if !isLoading {
                    updateMapData()
                    rehydrateSessionVisitInferenceIfNeeded()
                    maybeStartDemoSession()
                }
            }
            .onChange(of: buildingsRenderSignature) { _, _ in
                updateMapData()
                rehydrateSessionVisitInferenceIfNeeded()
                maybeStartDemoSession()
            }
            .onChange(of: featuresService.addresses?.features.count ?? 0) { _, _ in updateMapData() }
            .onChange(of: sessionManager.locationAuthorizationStatus) { _, newStatus in
                handleLocationAuthorizationChange(newStatus)
            }
            .onChange(of: sessionManager.pathCoordinates.count) { _, _ in updateSessionPathOnMap() }
            .onChange(of: sessionManager.isDemoSession) { _, _ in updateSessionPathOnMap() }
            .onChange(of: sessionManager.sessionId) { _, new in
                updateSessionPathOnMap()
                if new == nil {
                    // Ensure any map-local modal UI is dismissed before global end-session cover presents.
                    showTargetsSheet = false
                    showLeadCaptureSheet = false
                    showEndSessionConfirmation = false
                    selectedBuilding = nil
                    flyerModeManager.reset()
                    quickStartStartingMode = nil
                    pendingFlyerStart = nil
                    showLocationPermissionAlert = false
                    showBackgroundGPSSheet = false
                    demoSessionSimulator.stop(notify: false)
                    updateDemoTargetPulseOnMap()
                } else if sessionManager.sessionMode == .flyer {
                    flyerModeManager.startObservingLocation()
                } else {
                    flyerModeManager.stopObservingLocation()
                }
                if new == nil {
                    activeMapEditTool = nil
                    manualAddressPlacement = nil
                    cancelPendingManualAddressConfirmation(clearPreview: true)
                    layerManager?.clearManualAddressPreview()
                }
            }
            .onChange(of: sessionManager.sessionMode) { _, mode in
                guard sessionManager.sessionId != nil else { return }
                if mode == .flyer {
                    flyerModeManager.startObservingLocation()
                } else {
                    flyerModeManager.stopObservingLocation()
                }
            }
            .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
                guard sessionManager.sessionId != nil else { return }
                updateSessionPathOnMap()
            }
            .onChange(of: sessionManager.visitOverlayRevision) { _, _ in
                applySessionVisitOverlayStates()
            }
            .onChange(of: demoSessionSimulator.currentTarget?.id) { _, _ in
                focusDemoTargetIfNeeded()
                updateDemoTargetPulseOnMap()
            }
            .onReceive(Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()) { _ in
                guard sessionManager.isDemoSession, demoSessionSimulator.currentTarget != nil else { return }
                demoPulseTick += 1
                updateDemoTargetPulseOnMap()
            }
    }

    private var buildingsRenderSignature: String {
        let features = visibleBuildingFeatures
        guard !features.isEmpty else { return "none" }
        let polygonCount = features.reduce(into: 0) { partial, feature in
            let type = feature.geometry.type.lowercased()
            if type == "polygon" || type == "multipolygon" {
                partial += 1
            }
        }
        return "\(features.count)-\(polygonCount)"
    }

    private var campaignMapWithAlertsAndObservers: some View {
        campaignMapWithObservers
            .alert("Cannot start session", isPresented: $showSessionStartGateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sessionStartGateMessage)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = frame.height }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            }
    }

    private var campaignMapGeometry: some View {
        GeometryReader { geometry in
            campaignMapStack(geometry: geometry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(sessionManager.sessionId != nil ? .all : [])
        .ignoresSafeArea(.keyboard)
        .navigationBarBackButtonHidden(sessionManager.sessionId != nil)
    }

    private var nextTargetsSheetContent: some View {
        NextTargetsSheet(
            sessionManager: sessionManager,
            buildingCentroids: sessionManager.buildingCentroids,
            targetBuildings: sessionManager.targetBuildings,
            addressLabels: addressLabelsForTargets(),
            onBuildingTapped: { buildingId in
                HapticManager.light()
                focusBuildingId = buildingId
                showTargetsSheet = false
            },
            onCompleteTapped: { buildingId in
                HapticManager.soft()
                Task {
                    do {
                        try await markSessionTargetDelivered(targetId: buildingId)
                    } catch {
                        print("⚠️ [CampaignMap] Failed to complete target \(buildingId): \(error)")
                    }
                }
            },
            onUndoTapped: { buildingId in
                HapticManager.light()
                Task { try? await sessionManager.undoCompletion(buildingId) }
            }
        )
    }

    @ViewBuilder
    private var leadCaptureSheetContent: some View {
        if let building = selectedBuilding,
           let campId = UUID(uuidString: campaignId) {
            let gersIdString = building.canonicalBuildingIdentifier ?? building.id
            LeadCaptureSheet(
                addressDisplay: building.addressText ?? "Address",
                campaignId: campId,
                sessionId: sessionManager.sessionId,
                gersIdString: gersIdString,
                onSave: { lead in
                    let leadOutcome = try await FieldLeadsService.shared.addLeadDetailed(
                        lead,
                        workspaceId: WorkspaceContext.shared.workspaceId
                    )
                    // Count every lead save as a conversation (any status = had contact at door)
                    await MainActor.run { sessionManager.recordConversation(addressId: selectedAddress?.addressId) }
                    if leadOutcome.createdNew {
                        await MainActor.run { sessionManager.recordLeadCreated() }
                    }
                    let resolvedAddressId = selectedAddress?.addressId ?? building.addressId.flatMap(UUID.init(uuidString:))
                    let completionTargetId = resolvedAddressId.flatMap(sessionTargetIdForAddress)
                    if let addressId = resolvedAddressId {
                        let addressStatus = mapFieldLeadStatusToAddressStatus(leadOutcome.lead.status)
                        try? await VisitsAPI.shared.updateStatus(
                            addressId: addressId,
                            campaignId: campId,
                            status: addressStatus,
                            notes: leadOutcome.lead.notes,
                            sessionId: completionTargetId == nil ? nil : sessionManager.sessionId,
                            sessionTargetId: completionTargetId,
                            sessionEventType: completionTargetId == nil ? nil : SessionEventType.recordedVisitEventType(for: addressStatus),
                            location: completionTargetId == nil ? nil : sessionManager.currentLocation
                        )
                        await MainActor.run {
                            lastStatusRefreshKey = nil
                        }
                        scheduleLoadedStatusesRefresh(forceRefresh: true)
                    }
                    if let completionTargetId {
                        await sessionManager.markCompletionLocallyAfterPersistedOutcome(completionTargetId)
                    }
                    NotificationCenter.default.post(name: .leadSavedFromSession, object: nil)
                    await MainActor.run { HapticManager.success() }
                },
                onJustMark: {
                    HapticManager.soft()
                    do {
                        try await markSessionTargetDelivered(targetId: gersIdString)
                    } catch {
                        print("⚠️ [CampaignMap] Failed to mark building delivered (\(gersIdString)): \(error)")
                    }
                },
                onDismiss: {
                    showLeadCaptureSheet = false
                    selectedBuilding = nil
                }
            )
        }
    }

    @ViewBuilder
    private func campaignMapStack(geometry: GeometryProxy) -> some View {
        let keyboardInset = locationCardBottomInset(for: geometry)
        ZStack {
            mapLayer(geometry: geometry)
            sessionStatsOverlay
            proGPSDebugOverlay
            overlayUI
            mapEditToolOverlay
            flyerModeOverlay
            locationCardOverlay(bottomInset: keyboardInset)
            loadingOverlay
                .animation(.easeInOut(duration: 0.28), value: featuresService.isLoading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if sessionManager.sessionId != nil {
                BottomActionBar(
                    sessionManager: sessionManager,
                    showingTargets: $showTargetsSheet,
                    statsExpanded: $statsExpanded
                )
            }
        }
    }

    private func locationCardBottomInset(for geometry: GeometryProxy) -> CGFloat {
        let keyboardOverlap = max(0, keyboardHeight - geometry.safeAreaInsets.bottom)
        let baseBottomPadding: CGFloat = sessionManager.sessionId != nil ? 14 : 18
        // Lift the building card fully above the keyboard when editing notes/contact fields
        // (a small fraction was not enough — the keyboard covered Save and voice controls).
        guard showLocationCard, keyboardOverlap > 0 else { return baseBottomPadding }
        return baseBottomPadding + keyboardOverlap
    }

    // MARK: - Body subviews (split for type-checker)

    @ViewBuilder
    private func mapLayer(geometry: GeometryProxy) -> some View {
        let raw = geometry.size
        let size = Self.sanitizedMapContainerSize(raw)
        let hasValidSize = size.width > 0 && size.height > 0
        if hasValidSize {
            CampaignMapboxMapViewRepresentable(
                preferredSize: size,
                useDarkStyle: colorScheme == .dark,
                sessionLocation: sessionManager.sessionId != nil ? sessionManager.currentLocation : nil,
                sessionHeadingState: sessionManager.sessionId != nil ? sessionManager.headingState : .unavailable,
                showSessionPuck: sessionManager.sessionId != nil && !sessionManager.isDemoSession,
                onMapReady: { map in
                    self.mapView = map
                    LiveCampaignMapSnapshotStore.shared.setMapView(map)
                    setupMap(map)
                    syncManualAddressPreview()
                },
                onTap: { point in
                    handleTap(at: point)
                },
                onLongPress: { point in
                    handleMapLongPress(at: point)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var flyerModeOverlay: some View {
        if sessionManager.sessionId != nil, sessionManager.sessionMode == .flyer {
            FlyerModeOverlay(
                flyerModeManager: flyerModeManager,
                automaticStatusForAddress: automaticCompletionStatusForAddress,
                onAddressCompleted: flyerAddressCompleted
            )
            .id(layerManager != nil)
        }
    }

    private func automaticCompletionStatusForAddress(_ addressId: UUID) -> AddressStatus {
        AddressStatus.automaticDeliveredStatus(preserving: addressStatuses[addressId])
    }

    private func flyerAddressCompleted(addressId: UUID, status: AddressStatus) {
        addressStatuses[addressId] = status
        layerManager?.updateAddressState(
            addressId: addressId.uuidString,
            status: featureStateStatus(for: status),
            scansTotal: 0
        )
        if let gersId = gersIdForAddress(addressId: addressId) {
            let addrIds = addressIdsForBuilding(gersId: gersId)
            let buildingStatus = addrIds.isEmpty
                ? buildingFeatureStateStatus(for: status)
                : computeBuildingLayerStatus(gersId: gersId, addressIds: addrIds)
            layerManager?.updateBuildingState(gersId: gersId, status: buildingStatus, scansTotal: 0)
        }
        refreshTownhomeStatusOverlay()
        if let targetId = sessionTargetIdForAddress(addressId: addressId) {
            Task {
                await sessionManager.markCompletionLocallyAfterPersistedOutcome(targetId)
            }
        }
        if status == .delivered {
            SessionManager.shared.recordAddressDelivered()
        }
        HapticManager.success()
    }

    @ViewBuilder
    private var sessionStatsOverlay: some View {
        if sessionManager.sessionId != nil, statsExpanded {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        statsExpanded = false
                    }
                }
                .overlay(alignment: .topTrailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        SessionProgressDropdown(sessionManager: sessionManager, isExpanded: $statsExpanded)
                            .frame(maxWidth: 320, alignment: .trailing)
                        Spacer()
                    }
                    .padding(.top, 56 + 44)
                    .padding(.trailing, 8)
                }
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var proGPSDebugOverlay: some View {
        if sessionManager.sessionId != nil, sessionManager.isProGPSDebugOverlayEnabled {
            VStack {
                Spacer()
                HStack {
                    Text("Pro GPS: raw \(sessionManager.proGPSDebugRawPointCount) norm \(sessionManager.proGPSDebugNormalizedPointCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.bottom, 120)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var overlayUI: some View {
        VStack {
            if sessionManager.sessionId != nil {
                // Session: building/circle toggle, Progress pill, End button top right
                VStack(alignment: .leading, spacing: 8) {
                    if sessionManager.isDemoSession {
                        HStack(spacing: 8) {
                            Text("DEMO MODE")
                                .font(.flyrCaption.weight(.semibold))
                                .foregroundColor(.red)
                            if let currentTarget = demoSessionSimulator.currentTarget {
                                Text(currentTarget.label)
                                    .font(.flyrCaption)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.86))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        BuildingCircleToggle(mode: $displayMode) { _ in
                            updateMapData()
                        }
                        Spacer(minLength: 8)
                        SessionProgressPill(sessionManager: sessionManager, isExpanded: $statsExpanded)
                        Button {
                            HapticManager.light()
                            if sessionManager.isDemoSession {
                                Task { await stopDemoSessionAndDismiss() }
                            } else {
                                showEndSessionConfirmation = true
                            }
                        } label: {
                            Text(sessionManager.isDemoSession ? "Stop" : "End")
                                .font(.flyrSubheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .safeAreaPadding(.top, 48)
                .safeAreaPadding(.leading, 4)
                .safeAreaPadding(.trailing, 4)
            } else {
                // Pre-session: toggle top-left; GPS (+ optional map dismiss) top-right
                HStack(alignment: .top, spacing: 0) {
                    BuildingCircleToggle(mode: $displayMode) { _ in
                        updateMapData()
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        if shouldShowBackgroundGPSPill {
                            BackgroundGPSMapPill(
                                preSession: true,
                                hasPersistentBackgroundLocationAccess: sessionManager.hasPersistentBackgroundLocationAccess,
                                onTap: { showBackgroundGPSSheet = true }
                            )
                        }
                        if showPreSessionStartButton {
                            BeaconMapPill(isPrepared: beaconService.hasPreparedSetup) {
                                showBeaconSheet = true
                            }
                        }
                        if let onDismissFromMap {
                            Button {
                                HapticManager.light()
                                onDismissFromMap()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.black.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .safeAreaPadding(.top, 48)
                .safeAreaPadding(.leading, 4)
                .safeAreaPadding(.trailing, 4)
            }

            if let activeRouteWorkContext, sessionManager.sessionId == nil, !sessionManager.isActive {
                routeScopeBanner(activeRouteWorkContext)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if let planned = matchingPlannedFarmExecution,
               sessionManager.sessionId == nil,
               !sessionManager.isActive {
                plannedFarmExecutionBanner(planned, campaignId: campIdFromString)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            
            Spacer()
            
            if showPreSessionStartButton,
               sessionManager.sessionId == nil,
               !preferredSessionTargets.isEmpty,
               let campId = UUID(uuidString: campaignId) {
                VStack(spacing: 10) {
                    preSessionStartButtons(campaignId: campId)
                }
            }
        }
    }

    private var campIdFromString: UUID? {
        UUID(uuidString: campaignId)
    }

    private func routeScopeBanner(_ scope: RouteWorkContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Assigned Route")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    Text("\(scope.routeName) • \(scope.stopCount) houses")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()
            }

            if let onDismissFromMap {
                Button {
                    HapticManager.light()
                    onDismissFromMap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Return")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func plannedFarmExecutionBanner(_ context: FarmExecutionContext, campaignId: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: context.sessionMode == .flyer ? "paperplane.fill" : "door.left.hand.closed")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.farmName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                    Text(context.touchTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if let phaseName = context.phaseName {
                        Text(phaseName)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.76))
                    }
                }

                Spacer(minLength: 8)
            }

            if let campaignId {
                Button {
                    startPlannedFarmSession(campaignId: campaignId, context: context)
                } label: {
                    HStack {
                        Text(context.sessionMode == .flyer ? "Start Planned Flyer Session" : "Start Planned Door Knock Session")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(quickStartStartingMode != nil || pendingFlyerStart != nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var mapEditToolOverlay: some View {
        if let activeTool = activeMapEditTool {
            VStack {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeTool.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(activeTool.instructions)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if activeTool == .addHouse {
                        Button("Continue") {
                            guard let manualAddressPlacement else { return }
                            pendingManualAddressDraft = PendingManualAddressDraft(
                                coordinate: manualAddressPlacement,
                                linkedBuildingId: manualShapeContext?.buildingId,
                                prefilledAddressText: manualShapeContext?.addressText
                            )
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(manualAddressPlacement == nil ? Color.gray.opacity(0.35) : Color.white)
                        .clipShape(Capsule())
                        .disabled(manualAddressPlacement == nil)
                    }
                    Button("Cancel") {
                        self.activeMapEditTool = nil
                        self.manualAddressPlacement = nil
                        self.cancelPendingManualAddressConfirmation(clearPreview: true)
                        self.layerManager?.clearManualAddressPreview()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 12)
                .padding(.top, sessionManager.sessionId != nil ? 118 : 92)
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func preSessionStartButtons(campaignId: UUID) -> some View {
        let isStartingDoor = quickStartStartingMode == .doorKnocking
        let isStartingFlyers = quickStartStartingMode == .flyer
        let isBusy = quickStartStartingMode != nil || pendingFlyerStart != nil
        let selectedMode = preSessionSelectedMode
        let hasTargets = !sessionTargets(for: selectedMode).isEmpty
        let isStartingSelected = quickStartStartingMode == selectedMode

        HStack(spacing: 12) {
            preSessionModeButton(isBusy: isBusy, isStartingDoor: isStartingDoor, isStartingFlyers: isStartingFlyers)

            Button {
                guard !isBusy, hasTargets else { return }
                HapticManager.light()
                startFromPreSessionBar(
                    campaignId: campaignId,
                    mode: selectedMode,
                    goalAmount: effectivePreSessionGoalAmount
                )
            } label: {
                HStack(spacing: 8) {
                    if isStartingSelected {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("Start")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(hasTargets ? Color.flyrPrimary : Color.red.opacity(0.45))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !hasTargets)

            preSessionGoalButton(isBusy: isBusy)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "1A1A1A").opacity(0.96))
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, quickStartEnabled ? 12 : 8)
        .padding(.bottom, quickStartEnabled ? 20 : 78)
    }

    private var preSessionGoalCap: Int {
        max(
            visibleAddressFeatures.count,
            sessionTargets(for: .flyer).count,
            sessionTargets(for: .doorKnocking).count
        )
    }

    private func preSessionModeButton(isBusy: Bool, isStartingDoor: Bool, isStartingFlyers: Bool) -> some View {
        let currentMode = preSessionSelectedMode
        let isStartingCurrentMode = currentMode == .doorKnocking ? isStartingDoor : isStartingFlyers
        let iconName = currentMode == .doorKnocking ? "hand.raised.fill" : "newspaper.fill"
        let label = currentMode == .doorKnocking ? "Doorknock" : "Flyers"

        return Button {
            guard !isBusy else { return }
            HapticManager.light()
            preSessionSelectedMode = currentMode == .doorKnocking ? .flyer : .doorKnocking
        } label: {
            HStack(spacing: 6) {
                if isStartingCurrentMode {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 17)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func preSessionGoalButton(isBusy: Bool) -> some View {
        return Button {
            guard !isBusy, preSessionGoalCap > 0 else { return }
            HapticManager.light()
            showGoalSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .semibold))
                Text("Goal \(effectivePreSessionGoalAmount)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 17)
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || preSessionGoalCap == 0)
    }

    private var effectivePreSessionGoalAmount: Int {
        let cap = preSessionGoalCap
        guard cap > 0 else { return 0 }
        return min(max(1, preSessionGoalAmount ?? cap), cap)
    }

    private func startFromPreSessionBar(campaignId: UUID, mode: SessionMode, goalAmount: Int) {
        guard quickStartStartingMode == nil else { return }
        guard !sessionTargets(for: mode).isEmpty else { return }

        switch sessionManager.locationAuthorizationStatus {
        case .notDetermined:
            pendingFlyerStart = PendingFlyerStart(
                campaignId: campaignId,
                mode: mode,
                goalAmount: goalAmount,
                farmExecutionContext: nil
            )
            sessionManager.requestForegroundLocationAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startPreSessionWorkflow(campaignId: campaignId, mode: mode, goalAmount: goalAmount)
        case .denied, .restricted:
            locationPermissionAlertMessage = locationPermissionMessage(for: mode)
            showLocationPermissionAlert = true
        @unknown default:
            locationPermissionAlertMessage = locationPermissionMessage(for: mode)
            showLocationPermissionAlert = true
        }
    }

    private func startPreSessionWorkflow(campaignId: UUID, mode: SessionMode, goalAmount: Int) {
        guard quickStartStartingMode == nil else { return }
        let targets = sessionTargets(for: mode)
        guard !targets.isEmpty else { return }
        HapticManager.medium()
        quickStartStartingMode = mode

        switch mode {
        case .doorKnocking:
            displayMode = buildingSessionTargets.isEmpty ? .addresses : .buildings
            scheduleLayerVisibilityReassert()
        case .flyer:
            displayMode = .addresses
            scheduleLayerVisibilityReassert()
        }

        Task {
            if let reason = await CampaignsAPI.shared.sessionStartBlockReason(campaignId: campaignId) {
                await MainActor.run {
                    quickStartStartingMode = nil
                    sessionStartGateMessage = reason
                    showSessionStartGateAlert = true
                }
                return
            }
                startBuildingSession(
                    campaignId: campaignId,
                    targets: targets,
                    mode: mode,
                    goalAmount: goalAmount,
                    routeAssignmentId: activeRouteWorkContext?.assignmentId,
                    farmExecutionContext: nil,
                    onFinished: { quickStartStartingMode = nil }
            )
        }
    }

    private func startPlannedFarmSession(campaignId: UUID, context: FarmExecutionContext) {
        guard quickStartStartingMode == nil else { return }
        let mode = context.sessionMode
        let targets = sessionTargets(for: mode)
        guard !targets.isEmpty else { return }

        switch sessionManager.locationAuthorizationStatus {
        case .notDetermined:
            pendingFlyerStart = PendingFlyerStart(
                campaignId: campaignId,
                mode: mode,
                goalAmount: targets.count,
                farmExecutionContext: context
            )
            sessionManager.requestForegroundLocationAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            HapticManager.medium()
            quickStartStartingMode = mode
            if mode == .flyer {
                displayMode = .addresses
            } else {
                displayMode = buildingSessionTargets.isEmpty ? .addresses : .buildings
            }
            scheduleLayerVisibilityReassert()

            Task {
                if let reason = await CampaignsAPI.shared.sessionStartBlockReason(campaignId: campaignId) {
                    await MainActor.run {
                        quickStartStartingMode = nil
                        sessionStartGateMessage = reason
                        showSessionStartGateAlert = true
                    }
                    return
                }

                startBuildingSession(
                    campaignId: campaignId,
                    targets: targets,
                    mode: mode,
                    goalAmount: targets.count,
                    routeAssignmentId: activeRouteWorkContext?.assignmentId,
                    farmExecutionContext: context,
                    onFinished: {
                        quickStartStartingMode = nil
                    }
                )
            }
        case .denied, .restricted:
            locationPermissionAlertMessage = locationPermissionMessage(for: mode)
            showLocationPermissionAlert = true
        @unknown default:
            locationPermissionAlertMessage = locationPermissionMessage(for: mode)
            showLocationPermissionAlert = true
        }
    }

    private func handleLocationAuthorizationChange(_ status: CLAuthorizationStatus) {
        guard let pendingFlyerStart else { return }

        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            self.pendingFlyerStart = nil
            if let farmExecutionContext = pendingFlyerStart.farmExecutionContext {
                startPlannedFarmSession(campaignId: pendingFlyerStart.campaignId, context: farmExecutionContext)
            } else {
                startPreSessionWorkflow(
                    campaignId: pendingFlyerStart.campaignId,
                    mode: pendingFlyerStart.mode,
                    goalAmount: pendingFlyerStart.goalAmount
                )
            }
        case .denied, .restricted:
            self.pendingFlyerStart = nil
            locationPermissionAlertMessage = locationPermissionMessage(for: pendingFlyerStart.mode)
            showLocationPermissionAlert = true
        default:
            break
        }
    }

    private func locationPermissionMessage(for mode: SessionMode) -> String {
        switch mode {
        case .doorKnocking:
            return "FLYR uses your location only during an active canvassing session. Allow location access to start the session and track your route."
        case .flyer:
            return "FLYR uses your location only during an active delivery session. Allow location access to start the session and track your route."
        }
    }

    private func handleBackgroundGPSSheetPrimaryAction() {
        switch sessionManager.locationAuthorizationStatus {
        case .authorizedWhenInUse:
            sessionManager.requestBackgroundLocationAuthorization()
        case .denied, .restricted:
            openLocationSettings()
        default:
            break
        }
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    
    /// Half the square side length (meters) for synthetic manual-home extrusions in cube mode (3× prior 2.3 m half-side).
    private static let manualHomeProxyHalfSideMeters = 2.3 * 3.0

    /// Cube mode: show building extrusions when we have real footprints and/or manual-home proxy boxes.
    private func cubeModeShouldShowBuildingExtrusions() -> Bool {
        let realBuildings = visibleBuildingFeatures.count
        let manualProxies = syntheticBuildingProxyFeaturesForBuildingsMode().count
        return realBuildings > 0 || manualProxies > 0
    }

    /// Re-apply display-mode visibility; retries briefly if Mapbox layers are not in the style yet (style/source races).
    private func scheduleLayerVisibilityReassert(attempt: Int = 0) {
        updateLayerVisibility(for: displayMode)
        guard attempt < 6 else { return }
        guard let map = mapView?.mapboxMap else { return }
        let hasBuildingsLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsLayerId })
        let hasAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressesLayerId })
        guard !hasBuildingsLayer || !hasAddressesLayer else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            scheduleLayerVisibilityReassert(attempt: attempt + 1)
        }
    }

    /// Update layer visibility based on display mode (cubes only or pins only)
    private func updateLayerVisibility(for mode: DisplayMode) {
        guard let manager = layerManager else { return }
        guard let map = mapView?.mapboxMap else { return }
        
        let hasBuildingsLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsLayerId })
        let hasTownhomeOverlayLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.townhomeOverlayLayerId })
        let hasAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressesLayerId })
        let hasAddressNumbersLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressNumbersLayerId })
        if !hasBuildingsLayer || !hasAddressesLayer {
            print("🔍 [CampaignMap] Layers not in style yet (buildings=\(hasBuildingsLayer) townhouseOverlay=\(hasTownhomeOverlayLayer) addresses=\(hasAddressesLayer)); visibility will apply after style load")
        }
        let shouldShowBuildings = cubeModeShouldShowBuildingExtrusions()
        let shouldShowAddressNumbers = shouldShowAddressNumberLabels()
        let visibilitySignature = [
            mode.rawValue,
            hasBuildingsLayer ? "b1" : "b0",
            hasTownhomeOverlayLayer ? "t1" : "t0",
            hasAddressesLayer ? "a1" : "a0",
            hasAddressNumbersLayer ? "n1" : "n0",
            shouldShowBuildings ? "buildings-visible" : "buildings-hidden",
            visibleBuildingFeatures.isEmpty ? "townhomes-hidden" : "townhomes-visible",
            displayMode == .addresses ? "addresses-visible" : "addresses-hidden",
            shouldShowAddressNumbers ? "numbers-visible" : "numbers-hidden"
        ].joined(separator: "|")
        guard lastLayerVisibilitySignature != visibilitySignature else { return }
        
        switch mode {
        case .buildings:
            manager.includeBuildingsLayer = true
            manager.includeAddressesLayer = false
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(shouldShowBuildings ? .visible : .none)
                }
            }
            if hasTownhomeOverlayLayer {
                try? map.updateLayer(withId: MapLayerManager.townhomeOverlayLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(visibleBuildingFeatures.isEmpty ? .none : .visible)
                }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) {
                    $0.visibility = .constant(.none)
                }
            }
            manager.updateAddressNumberLabelVisibility(isVisible: hasAddressNumbersLayer && shouldShowAddressNumbers)
        case .addresses:
            manager.includeBuildingsLayer = false
            manager.includeAddressesLayer = true
            let addressCount = visibleAddressFeatures.count
            let buildingCount = visibleBuildingFeatures.count
            let hasAddressPoints = addressCount > 0
            print("🔍 [CampaignMap] addresses=\(addressCount) buildings=\(buildingCount) hasAddressPoints=\(hasAddressPoints)")
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasTownhomeOverlayLayer {
                try? map.updateLayer(withId: MapLayerManager.townhomeOverlayLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            }
            manager.updateAddressNumberLabelVisibility(isVisible: hasAddressNumbersLayer && shouldShowAddressNumbers)
        }
        
        lastLayerVisibilitySignature = visibilitySignature
        print("🗺️ [CampaignMap] Display mode changed to: \(mode)")
    }

    /// House numbers on building tops (buildings mode) and on 3D address circles (addresses mode); hidden when map is pitched past oblique threshold.
    private func shouldShowAddressNumberLabels() -> Bool {
        guard let cameraState = mapView?.mapboxMap.cameraState else { return false }
        return cameraState.pitch <= 60
    }

    @ViewBuilder
    private func locationCardOverlay(bottomInset: CGFloat) -> some View {
        if showLocationCard,
           let building = selectedBuilding,
           let campId = UUID(uuidString: campaignId) {
            let gersIdString = building.canonicalBuildingIdentifier ?? building.id
            let resolvedAddrId = selectedAddress?.addressId ?? building.addressId.flatMap { UUID(uuidString: $0) }
            let resolvedAddrText = nonEmptyAddressText(
                formatted: selectedAddress?.formatted,
                houseNumber: selectedAddress?.houseNumber,
                streetName: selectedAddress?.streetName
            ) ?? nonEmptyAddressText(
                formatted: building.addressText,
                houseNumber: building.houseNumber,
                streetName: building.streetName
            )
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LocationCardView(
                    gersId: gersIdString,
                    campaignId: campId,
                    sessionId: sessionManager.sessionId,
                    addressId: resolvedAddrId,
                    addressText: resolvedAddrText,
                    preferredAddressId: selectedAddressIdForCard,
                    buildingSource: building.source,
                    addressSource: selectedAddress?.source,
                    addressStatuses: addressStatuses,
                    sessionTargetIdForAddress: sessionTargetIdForAddress,
                    onSelectAddress: { setSelectedAddressForCard($0) },
                    onAddressesResolved: { ids in
                        buildingAddressMap[gersIdString.lowercased()] = deduplicatedAddressIds(ids)
                        refreshTownhomeStatusOverlay()
                    },
                    onClose: {
                        showLocationCard = false
                        selectedBuilding = nil
                        selectedAddress = nil
                        selectedAddressIdForCard = nil
                    },
                    onStatusUpdated: { addressId, status in
                        if status == .delivered {
                            SessionManager.shared.recordAddressDelivered()
                        }
                        if status == .talked || status == .appointment || status == .hotLead {
                            SessionManager.shared.recordConversation(addressId: addressId)
                        }
                        if let map = mapView {
                            MapController.shared.applyStatusFeatureState(statuses: [addressId.uuidString: status], mapView: map)
                        }
                        // Update local status cache
                        addressStatuses[addressId] = status
                        if let targetId = sessionTargetIdForAddress(addressId: addressId) {
                            Task {
                                if status == .none || status == .untouched {
                                    try? await sessionManager.undoCompletion(targetId)
                                } else {
                                    await sessionManager.markCompletionLocallyAfterPersistedOutcome(targetId)
                                }
                            }
                        }
                        let scansTotal = visibleBuildingFeatures.first(where: { feature in
                            feature.properties.buildingIdentifierCandidates.contains { candidate in
                                candidate.caseInsensitiveCompare(gersIdString) == .orderedSame
                            } || (feature.id?.caseInsensitiveCompare(gersIdString) == .orderedSame)
                        })?.properties.scansTotal ?? 0
                        let layerStatus = featureStateStatus(for: status)
                        layerManager?.updateAddressState(addressId: addressId.uuidString, status: layerStatus, scansTotal: scansTotal)
                        // Building: green only when ALL addresses are visited
                        let addrIds = addressIdsForBuilding(gersId: gersIdString)
                        let buildingStatus = addrIds.isEmpty ? buildingFeatureStateStatus(for: status) : computeBuildingLayerStatus(gersId: gersIdString, addressIds: addrIds)
                        layerManager?.updateBuildingState(gersId: gersIdString, status: buildingStatus, scansTotal: scansTotal)
                        refreshTownhomeStatusOverlay()
                    },
                    onToolsAction: { action in
                        let currentAddress = selectedAddress
                        let context = prepareManualShapeContext(building: building, address: currentAddress)
                        switch action {
                        case .addHouse:
                            startAddHouseFlow(with: context)
                        case .addVisit, .resetHome:
                            break
                        case .deleteManualShape:
                            handleDeleteManualShape(building: building, address: currentAddress)
                        }
                    }
                )
                .id("building-\(gersIdString)-\(resolvedAddrId?.uuidString ?? "")")
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset)
                .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showLocationCard,
                  let address = selectedAddress,
                  let campId = UUID(uuidString: campaignId) {
            let gersIdString = address.buildingGersId ?? address.gersId ?? ""
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LocationCardView(
                    gersId: gersIdString,
                    campaignId: campId,
                    sessionId: sessionManager.sessionId,
                    addressId: address.addressId,
                    addressText: nonEmptyAddressText(
                        formatted: address.formatted,
                        houseNumber: address.houseNumber,
                        streetName: address.streetName
                    ),
                    preferredAddressId: selectedAddressIdForCard,
                    buildingSource: selectedBuilding?.source,
                    addressSource: address.source,
                    addressStatuses: addressStatuses,
                    sessionTargetIdForAddress: sessionTargetIdForAddress,
                    onSelectAddress: { setSelectedAddressForCard($0) },
                    onAddressesResolved: { ids in
                        if !gersIdString.isEmpty {
                            buildingAddressMap[gersIdString.lowercased()] = deduplicatedAddressIds(ids)
                            refreshTownhomeStatusOverlay()
                        }
                    },
                    onClose: {
                        showLocationCard = false
                        selectedBuilding = nil
                        selectedAddress = nil
                        selectedAddressIdForCard = nil
                    },
                    onStatusUpdated: { addressId, status in
                        if status == .delivered {
                            SessionManager.shared.recordAddressDelivered()
                        }
                        if status == .talked || status == .appointment || status == .hotLead {
                            SessionManager.shared.recordConversation(addressId: addressId)
                        }
                        if let map = mapView {
                            MapController.shared.applyStatusFeatureState(statuses: [addressId.uuidString: status], mapView: map)
                        }
                        // Update local status cache
                        addressStatuses[addressId] = status
                        if let targetId = sessionTargetIdForAddress(addressId: addressId) {
                            Task {
                                if status == .none || status == .untouched {
                                    try? await sessionManager.undoCompletion(targetId)
                                } else {
                                    await sessionManager.markCompletionLocallyAfterPersistedOutcome(targetId)
                                }
                            }
                        }
                        let scansTotal = visibleBuildingFeatures.first(where: { feature in
                            feature.properties.buildingIdentifierCandidates.contains { candidate in
                                candidate.caseInsensitiveCompare(gersIdString) == .orderedSame
                            } || (feature.id?.caseInsensitiveCompare(gersIdString) == .orderedSame)
                        })?.properties.scansTotal ?? 0
                        let layerStatus = featureStateStatus(for: status)
                        layerManager?.updateAddressState(addressId: addressId.uuidString, status: layerStatus, scansTotal: scansTotal)
                        // Building: green only when ALL addresses are visited
                        let addrIds = addressIdsForBuilding(gersId: gersIdString)
                        let buildingStatus = addrIds.isEmpty ? buildingFeatureStateStatus(for: status) : computeBuildingLayerStatus(gersId: gersIdString, addressIds: addrIds)
                        layerManager?.updateBuildingState(gersId: gersIdString, status: buildingStatus, scansTotal: scansTotal)
                        refreshTownhomeStatusOverlay()
                    },
                    onToolsAction: { action in
                        let currentBuilding = selectedBuilding
                        let context = prepareManualShapeContext(building: currentBuilding, address: address)
                        switch action {
                        case .addHouse:
                            startAddHouseFlow(with: context)
                        case .addVisit, .resetHome:
                            break
                        case .deleteManualShape:
                            handleDeleteManualShape(building: currentBuilding, address: address)
                        }
                    }
                )
                .id("address-\(address.addressId.uuidString)")
                .padding(.horizontal, 16)
                .padding(.bottom, bottomInset)
                .transition(.move(edge: .bottom))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if featuresService.isLoading {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    CampaignMapLoadingLottieView(name: "splash")
                        .frame(width: 340, height: 227)
                        .clipped()
                        .accessibilityHidden(true)

                    Text("Loading map")
                        .font(.flyrHeadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .offset(y: -56)
            }
            .allowsHitTesting(true)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading map data")
            .transition(.opacity)
        }
    }

    // MARK: - Setup
    
    private func setupMap(_ map: MapView) {
        let manager = MapLayerManager(mapView: map)
        manager.includeBuildingsLayer = true
        manager.includeAddressesLayer = true  // Add both layers; visibility controlled by toggle (buildings vs circle extrusions)
        manager.showRoadOverlay = false
        self.layerManager = manager

        // Hide map zoom/scale bar/compass ornaments
        map.ornaments.options.scaleBar.visibility = .hidden
        map.ornaments.options.compass.visibility = .hidden

        // Wait for style to load
        map.mapboxMap.onStyleLoaded.observe { _ in
            Self.removeStyleBuildingLayers(map: map)
            manager.setupLayers()
            addSessionPathLayersIfNeeded(map: map)
            addDemoTargetPulseLayersIfNeeded(map: map)

            // Set initial camera so map shows (default center; will fly to campaign when data loads)
            map.camera.fly(to: CameraOptions(
                center: Self.defaultCenter,
                padding: nil,
                zoom: 16,
                bearing: nil,
                pitch: 60
            ), duration: 0.5)

            // Load data if we have it
            updateMapData()
            syncManualAddressPreview()
            flyToCampaignCenterIfNeeded(map: map)
            updateSessionPathOnMap()
            updateDemoTargetPulseOnMap()
            // Apply current display mode so buildings vs circle extrusions match toggle
            lastLayerVisibilitySignature = nil
            scheduleLayerVisibilityReassert()
        }.store(in: &cancellables)

        map.mapboxMap.onCameraChanged.observe { _ in
            updateLayerVisibility(for: displayMode)
        }.store(in: &cancellables)
    }
    
    private func loadCampaignData(force: Bool) {
        let loadKey = currentMapLoadKey
        if !force, lastLoadedDataKey == loadKey {
            return
        }
        lastLoadedDataKey = loadKey
        Task {
            if let activeRouteWorkContext {
                await featuresService.fetchRouteScopedCampaignFeatures(
                    assignmentId: activeRouteWorkContext.assignmentId,
                    campaignId: campaignId
                )
            } else {
                await featuresService.fetchAllCampaignFeatures(campaignId: campaignId)
            }
        }
    }
    
    private func updateMapData() {
        guard let manager = layerManager else { return }

        logRouteScopeSummary()
        
        manager.updateBuildings(buildingsDataForCurrentDisplayMode())
        refreshTownhomeStatusOverlay()
        manager.updateAddressNumberLabels(
            addresses: visibleAddressFeatures,
            buildings: visibleBuildingFeatures,
            orderedAddressIdsByBuilding: buildingAddressMap
        )
        
        if let addressesData = addressDataForCurrentDisplayMode() {
            manager.updateAddresses(addressesData)
        } else if let buildingsData = visibleBuildingsGeoJSONData() {
            manager.updateAddressesFromBuildingCentroids(buildingGeoJSONData: buildingsData)
        }
        
        if let roadsData = featuresService.roadsAsGeoJSONData() {
            manager.updateRoads(roadsData)
        }
        
        // Apply current display mode visibility (reassert if layers were not ready yet)
        scheduleLayerVisibilityReassert()
        
        if let map = mapView {
            flyToCampaignCenterIfNeeded(map: map)
        }
        
        // Re-apply loaded campaign statuses after source update (Mapbox clears feature state when GeoJSON source is updated)
        scheduleLoadedStatusesRefresh()

        if activeRouteWorkContext != nil {
            flyerModeManager.load(targets: flyerSessionTargets)
        } else if let campaignUUID = UUID(uuidString: campaignId) {
            Task { await flyerModeManager.load(campaignId: campaignUUID, featuresService: featuresService) }
        }

        reconcilePendingManualAddressConfirmation()
    }

    private func scheduleLoadedStatusesRefresh(forceRefresh: Bool = false) {
        guard UUID(uuidString: campaignId) != nil else { return }
        guard forceRefresh || !featuresService.isLoading || !visibleBuildingFeatures.isEmpty || !visibleAddressFeatures.isEmpty else {
            return
        }

        let refreshKey = statusRefreshKey()
        if !forceRefresh, lastStatusRefreshKey == refreshKey {
            return
        }

        lastStatusRefreshKey = refreshKey
        if forceRefresh {
            pendingStatusRefreshWantsForce = true
        }
        statusRefreshTask?.cancel()
        // Debounce: incremental loads fire `updateMapData` many times; one pass after sources settle avoids duplicate fetches and cancelled in-flight work.
        statusRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            let useForce = pendingStatusRefreshWantsForce
            pendingStatusRefreshWantsForce = false
            await applyLoadedStatusesToMap(forceRefresh: useForce)
        }
    }

    private func statusRefreshKey() -> String {
        let buildingPreview = visibleBuildingFeatures
            .prefix(12)
            .compactMap { $0.id ?? $0.properties.gersId ?? $0.properties.buildingId }
            .joined(separator: ",")
        let addressPreview = visibleAddressFeatures
            .prefix(12)
            .compactMap { $0.properties.id ?? $0.id }
            .joined(separator: ",")

        return [
            campaignId.lowercased(),
            activeRouteWorkContext?.assignmentId.uuidString.lowercased() ?? "full-campaign",
            displayMode.rawValue.lowercased(),
            "b\(visibleBuildingFeatures.count)",
            "a\(visibleAddressFeatures.count)",
            buildingPreview,
            addressPreview
        ].joined(separator: "|")
    }

    private func logRouteScopeSummary() {
        let totalBuildings = featuresService.buildings?.features.count ?? 0
        let totalAddresses = featuresService.addresses?.features.count ?? 0
        let scopedBuildings = visibleBuildingFeatures.count
        let scopedAddresses = visibleAddressFeatures.count

        if let scope = activeRouteWorkContext {
            print(
                """
                🧭 [RouteScope] assignment=\(scope.assignmentId.uuidString) \
                campaign=\(scope.campaignId.uuidString) \
                stops=\(scope.stopCount) \
                buildings=\(scopedBuildings)/\(totalBuildings) \
                addresses=\(scopedAddresses)/\(totalAddresses) \
                mode=route-scoped
                """
            )
        } else {
            print(
                """
                🧭 [RouteScope] campaign=\(campaignId) \
                buildings=\(scopedBuildings)/\(totalBuildings) \
                addresses=\(scopedAddresses)/\(totalAddresses) \
                mode=full-campaign
                """
            )
        }
    }

    private func buildingsDataForCurrentDisplayMode() -> Data? {
        let baseFeatures = geoJSONFeatureDictionaries(from: visibleBuildingsGeoJSONData())

        switch displayMode {
        case .addresses:
            if baseFeatures.isEmpty {
                return visibleBuildingsGeoJSONData()
            }
            return geoJSONDataFromFeatureDictionaries(baseFeatures)
        case .buildings:
            let proxyFeatures = syntheticBuildingProxyFeaturesForBuildingsMode()
            if baseFeatures.isEmpty && proxyFeatures.isEmpty {
                return geoJSONDataFromFeatureDictionaries([])
            }
            return geoJSONDataFromFeatureDictionaries(baseFeatures + proxyFeatures)
        }
    }

    private func addressDataForCurrentDisplayMode() -> Data? {
        switch displayMode {
        case .addresses:
            return visibleAddressesGeoJSONData()
        case .buildings:
            return visibleAddressesGeoJSONData()
        }
    }

    private func orphanAddressFeaturesForBuildingsMode() -> [AddressFeature] {
        let addresses = visibleAddressFeatures
        guard !addresses.isEmpty else { return [] }

        let manualAddresses = addresses.filter { feature in
            (feature.properties.source ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "manual"
        }
        guard !manualAddresses.isEmpty else { return [] }
        let buildings = visibleBuildingFeatures
        guard !buildings.isEmpty else { return manualAddresses }

        var coveredAddressIds = Set<String>()

        for building in buildings {
            let candidateBuildingIds = [
                building.properties.gersId,
                building.properties.buildingId,
                building.id
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            for candidate in candidateBuildingIds {
                for addressId in addressIdsForBuilding(gersId: candidate) {
                    coveredAddressIds.insert(addressId.uuidString.lowercased())
                }
            }

            if let directAddressId = building.properties.addressId?.lowercased() {
                coveredAddressIds.insert(directAddressId)
            }
        }

        return manualAddresses.filter { feature in
            let rawId = (feature.properties.id ?? feature.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !rawId.isEmpty else { return false }
            return !coveredAddressIds.contains(rawId)
        }
    }

    private func syntheticBuildingProxyFeaturesForBuildingsMode() -> [[String: Any]] {
        orphanAddressFeaturesForBuildingsMode().compactMap { feature in
            syntheticBuildingProxyFeature(from: feature)
        }
    }

    private func syntheticBuildingProxyFeature(from feature: AddressFeature) -> [String: Any]? {
        guard let point = feature.geometry.asPoint, point.count >= 2 else { return nil }

        let rawId = (feature.properties.id ?? feature.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawId.isEmpty else { return nil }

        let normalizedGersId = rawId.contains("-") ? rawId.lowercased() : rawId
        let coordinate = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        let polygon = squarePolygonCoordinates(center: coordinate, halfSideMeters: Self.manualHomeProxyHalfSideMeters)
        let effectiveStatus = UUID(uuidString: normalizedGersId).flatMap { addressStatuses[$0] } ?? .untouched
        let formatted = nonEmptyAddressText(
            formatted: feature.properties.formatted,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName
        ) ?? "Address"

        let properties: [String: Any?] = [
            "id": normalizedGersId,
            "gers_id": normalizedGersId,
            "address_id": normalizedGersId,
            "building_id": normalizedGersId,
            "address_text": formatted,
            "house_number": feature.properties.houseNumber,
            "street_name": feature.properties.streetName,
            "source": feature.properties.source ?? "address_proxy",
            "feature_type": "address_proxy",
            "height": 9.0,
            "height_m": 9.0,
            "min_height": 0.0,
            "is_townhome": false,
            "units_count": 1,
            "address_count": 1,
            "status": buildingFeatureStateStatus(for: effectiveStatus),
            "scans_today": 0,
            "scans_total": 0,
            "qr_scanned": false
        ]

        return [
            "id": normalizedGersId,
            "type": "Feature",
            "geometry": [
                "type": "Polygon",
                "coordinates": [polygon]
            ],
            "properties": properties.compactMapValues { $0 }
        ]
    }

    private func squarePolygonCoordinates(
        center: CLLocationCoordinate2D,
        halfSideMeters: Double
    ) -> [[Double]] {
        let latDelta = halfSideMeters / 111_320.0
        let metersPerLonDegree = max(cos(center.latitude * .pi / 180.0) * 111_320.0, 0.0001)
        let lonDelta = halfSideMeters / metersPerLonDegree

        return [
            [center.longitude - lonDelta, center.latitude - latDelta],
            [center.longitude + lonDelta, center.latitude - latDelta],
            [center.longitude + lonDelta, center.latitude + latDelta],
            [center.longitude - lonDelta, center.latitude + latDelta],
            [center.longitude - lonDelta, center.latitude - latDelta]
        ]
    }

    private func visibleBuildingsGeoJSONData() -> Data? {
        try? JSONEncoder().encode(
            BuildingFeatureCollection(type: "FeatureCollection", features: visibleBuildingFeatures)
        )
    }

    private func visibleAddressesGeoJSONData() -> Data? {
        try? JSONEncoder().encode(
            AddressFeatureCollection(type: "FeatureCollection", features: visibleAddressFeatures)
        )
    }

    private func geoJSONFeatureDictionaries(from data: Data?) -> [[String: Any]] {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return []
        }
        return features
    }

    private func geoJSONDataFromFeatureDictionaries(_ features: [[String: Any]]) -> Data? {
        try? JSONSerialization.data(
            withJSONObject: [
                "type": "FeatureCollection",
                "features": features
            ]
        )
    }

    private func routeScopedSessionTargets(for scope: RouteWorkContext) -> [ResolvedCampaignTarget] {
        var seen = Set<String>()
        var resolved: [ResolvedCampaignTarget] = []

        for stop in scope.stops {
            let buildingCandidates = [
                stop.gersId,
                stop.buildingId?.uuidString
            ]
            .compactMap(RouteWorkContext.normalizedIdentifier)

            let target = resolvedTarget(for: stop, buildingCandidates: buildingCandidates)
            guard let target else { continue }

            let normalizedId = target.id.lowercased()
            guard seen.insert(normalizedId).inserted else { continue }
            resolved.append(target)
        }

        return resolved
    }

    private func resolvedTarget(for stop: RoutePlanStop, buildingCandidates: [String]) -> ResolvedCampaignTarget? {
        if let addressId = stop.addressId,
           let feature = visibleAddressFeatures.first(where: { feature in
               RouteWorkContext.normalizedIdentifier(feature.properties.id ?? feature.id) == addressId.uuidString.lowercased()
           }),
           let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) {
            return ResolvedCampaignTarget(
                id: addressId.uuidString.lowercased(),
                label: stop.displayAddress,
                coordinate: coordinate,
                addressId: addressId.uuidString.lowercased(),
                buildingId: feature.properties.buildingGersId ?? feature.properties.gersId ?? stop.gersId ?? stop.buildingId?.uuidString,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }

        if let feature = visibleBuildingFeatures.first(where: { feature in
            let candidateIds = feature.properties.buildingIdentifierCandidates
                .compactMap(RouteWorkContext.normalizedIdentifier)
            return candidateIds.contains { buildingCandidates.contains($0) }
        }),
           let coordinate = CampaignTargetResolver.coordinate(for: feature.geometry) {
            let targetId = stop.addressId?.uuidString.lowercased()
                ?? RouteWorkContext.normalizedIdentifier(feature.properties.canonicalBuildingIdentifier ?? feature.id)
                ?? buildingCandidates.first

            guard let targetId else { return nil }

            return ResolvedCampaignTarget(
                id: targetId,
                label: stop.displayAddress,
                coordinate: coordinate,
                addressId: stop.addressId?.uuidString.lowercased(),
                buildingId: feature.properties.canonicalBuildingIdentifier ?? feature.id ?? stop.gersId ?? stop.buildingId?.uuidString,
                houseNumber: feature.properties.houseNumber,
                streetName: feature.properties.streetName
            )
        }

        if let lat = stop.latitude, let lon = stop.longitude {
            let targetId = stop.addressId?.uuidString.lowercased() ?? buildingCandidates.first
            guard let targetId else { return nil }

            return ResolvedCampaignTarget(
                id: targetId,
                label: stop.displayAddress,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                addressId: stop.addressId?.uuidString.lowercased(),
                buildingId: stop.gersId ?? stop.buildingId?.uuidString,
                houseNumber: stop.displayAddress.extractHouseNumber(),
                streetName: nil
            )
        }

        return nil
    }
    
    /// Fetch campaign address statuses and apply them to the map so buildings/addresses show correct colors (delivered = green, etc.).
    /// Call after every source update since Mapbox clears feature state when GeoJSON is replaced.
    /// - Parameter forceRefresh: Pass `true` immediately after a status write when you need a network read (e.g. lead save); cooldown cache is also cleared by `VisitsAPI.invalidateStatusCache` on writes.
    private func applyLoadedStatusesToMap(forceRefresh: Bool = false) async {
        guard let manager = layerManager,
              let campaignUUID = UUID(uuidString: campaignId) else { return }
        do {
            print("🧭 [session_start.load_visit_statuses] begin campaign=\(campaignUUID.uuidString)")
            let statuses = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignUUID, forceRefresh: forceRefresh)
            guard !statuses.isEmpty else { return }
            await MainActor.run {
                // Populate local status cache
                for (addressId, row) in statuses {
                    let displayStatus = AddressStatus.preferredForDisplay(
                        current: addressStatuses[addressId],
                        incoming: row.status
                    )
                    addressStatuses[addressId] = displayStatus
                    manager.updateAddressState(
                        addressId: addressId.uuidString,
                        status: effectiveAddressLayerStatus(addressId: addressId, baseStatus: displayStatus),
                        scansTotal: 0
                    )
                }
                if !visibleBuildingFeatures.isEmpty {
                    for building in visibleBuildingFeatures {
                        guard let gersId = building.properties.canonicalBuildingIdentifier ?? building.id else { continue }
                        let scansTotal = building.properties.scansTotal

                        // Single-address building: use that address's status directly
                        if let addrIdStr = building.properties.addressId,
                           let addrId = UUID(uuidString: addrIdStr),
                           let row = statuses[addrId] {
                            let displayStatus = addressStatuses[addrId] ?? row.status
                            manager.updateBuildingState(
                                gersId: gersId,
                                status: effectiveBuildingLayerStatus(gersId: gersId, addressIds: [addrId], fallbackStatus: displayStatus),
                                scansTotal: scansTotal
                            )
                            continue
                        }

                        // Multi-address building: only go green if ALL addresses are visited
                        let addrIds = addressIdsForBuilding(gersId: gersId)
                        if !addrIds.isEmpty {
                            let buildingStatus = effectiveBuildingLayerStatus(gersId: gersId, addressIds: addrIds)
                            manager.updateBuildingState(gersId: gersId, status: buildingStatus, scansTotal: scansTotal)
                        }
                    }
                }
                refreshTownhomeStatusOverlay()
                updateFilters()
                applySessionVisitOverlayStates()
            }
            print("🧭 [session_start.load_visit_statuses] success count=\(statuses.count)")
        } catch {
            print("⚠️ [session_start.load_visit_statuses] failed error=\(error)")
        }
    }

    private func refreshTownhomeStatusOverlay() {
        guard let manager = layerManager else { return }
        manager.updateTownhomeStatusOverlay(
            buildings: visibleBuildingFeatures,
            addresses: visibleAddressFeatures,
            orderedAddressIdsByBuilding: buildingAddressMap,
            addressStatuses: addressStatuses
        )
    }

    /// Returns ordered address UUIDs for a building by scanning loaded address features for matching building_gers_id.
    private func addressIdsForBuilding(gersId: String) -> [UUID] {
        let gersLower = gersId.lowercased()
        if let cached = buildingAddressMap[gersLower], !cached.isEmpty {
            return cached
        }
        if !visibleAddressFeatures.isEmpty {
            let fromAddresses = visibleAddressFeatures
                .filter { ($0.properties.buildingGersId ?? "").lowercased() == gersLower }
                .sorted { lhs, rhs in
                    let left = (lhs.properties.formatted ?? lhs.properties.houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let right = (rhs.properties.formatted ?? rhs.properties.houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return left.localizedStandardCompare(right) == .orderedAscending
                }
                .compactMap { feature -> UUID? in
                    guard let idStr = feature.properties.id ?? feature.id,
                          let uuid = UUID(uuidString: idStr) else { return nil }
                    return uuid
                }
            let deduped = deduplicatedAddressIds(fromAddresses)
            if !deduped.isEmpty {
                return deduped
            }
        }

        guard !visibleBuildingFeatures.isEmpty else { return [] }
        return deduplicatedAddressIds(visibleBuildingFeatures.compactMap { feature -> UUID? in
            let candidateIds = [
                feature.properties.gersId,
                feature.properties.buildingId,
                feature.id
            ]
            .compactMap { $0?.lowercased() }

            guard candidateIds.contains(gersLower),
                  let addressId = feature.properties.addressId,
                  let uuid = UUID(uuidString: addressId) else { return nil }
            return uuid
        })
    }

    private func resolvedAddressIdsForSessionTarget(targetId: String) -> [UUID] {
        let normalizedTargetId = targetId.lowercased()
        if let target = sessionTargets(for: sessionManager.sessionMode).first(where: {
            $0.id.lowercased() == normalizedTargetId
        }) {
            if let addressId = target.addressId, let uuid = UUID(uuidString: addressId) {
                return [uuid]
            }
            if let buildingId = target.buildingId {
                let buildingAddressIds = addressIdsForBuilding(gersId: buildingId)
                if !buildingAddressIds.isEmpty {
                    return buildingAddressIds
                }
            }
        }

        if let addressId = UUID(uuidString: targetId) {
            return [addressId]
        }

        return addressIdsForBuilding(gersId: targetId)
    }

    private func resolvedBuildingIdForSessionTarget(targetId: String, addressIds: [UUID]) -> String? {
        let normalizedTargetId = targetId.lowercased()
        if let target = sessionTargets(for: sessionManager.sessionMode).first(where: {
            $0.id.lowercased() == normalizedTargetId
        }) {
            if let buildingId = target.buildingId, !buildingId.isEmpty {
                return buildingId
            }
        }

        if UUID(uuidString: targetId) != nil {
            return addressIds.compactMap(gersIdForAddress).first
        }

        return targetId
    }

    private func refreshSessionTargetMappings(for targets: [ResolvedCampaignTarget]) {
        let mappings = sessionTargetMappings(for: targets)
        sessionManager.configureSessionTargetMappings(
            addressIdsByTargetId: mappings.addressIdsByTargetId,
            buildingIdsByTargetId: mappings.buildingIdsByTargetId
        )
        applySessionVisitOverlayStates()
    }

    private func sessionTargetMappings(for targets: [ResolvedCampaignTarget]) -> (
        addressIdsByTargetId: [String: [UUID]],
        buildingIdsByTargetId: [String: String]
    ) {
        var addressMap: [String: [UUID]] = [:]
        var buildingMap: [String: String] = [:]

        for target in targets {
            let addressIds: [UUID]
            if let addressId = target.addressId.flatMap(UUID.init(uuidString:)) {
                addressIds = [addressId]
            } else if let buildingId = target.buildingId {
                addressIds = addressIdsForBuilding(gersId: buildingId)
            } else {
                addressIds = addressIdsForBuilding(gersId: target.id)
            }
            addressMap[target.id] = deduplicatedAddressIds(addressIds)

            if let buildingId = target.buildingId {
                buildingMap[target.id] = buildingId
            } else if let resolvedBuildingId = resolvedBuildingIdForSessionTarget(targetId: target.id, addressIds: addressIds) {
                buildingMap[target.id] = resolvedBuildingId
            }
        }

        return (addressMap, buildingMap)
    }

    private func effectiveAddressLayerStatus(addressId: UUID, baseStatus: AddressStatus) -> String {
        let key = addressId.uuidString.lowercased()
        if sessionManager.pendingVisitedAddressIds.contains(key) {
            return "pending_visited"
        }
        if sessionManager.confirmedVisitedAddressIds.contains(key), baseStatus.mapLayerStatus == "not_visited" {
            return "visited"
        }
        return featureStateStatus(for: baseStatus)
    }

    private func effectiveBuildingLayerStatus(
        gersId: String,
        addressIds: [UUID],
        fallbackStatus: AddressStatus? = nil
    ) -> String {
        let key = gersId.lowercased()
        if sessionManager.pendingVisitedBuildingIds.contains(key) {
            return "pending_visited"
        }

        let baseStatus: String
        if !addressIds.isEmpty {
            baseStatus = computeBuildingLayerStatus(gersId: gersId, addressIds: addressIds)
        } else if let fallbackStatus {
            baseStatus = buildingFeatureStateStatus(for: fallbackStatus)
        } else {
            baseStatus = "not_visited"
        }

        if sessionManager.confirmedVisitedBuildingIds.contains(key), baseStatus == "not_visited" {
            return "visited"
        }
        return baseStatus
    }

    private func applySessionVisitOverlayStates() {
        guard let manager = layerManager else { return }

        for feature in visibleAddressFeatures {
            guard let idString = feature.properties.id ?? feature.id,
                  let addressId = UUID(uuidString: idString) else {
                continue
            }
            let status = addressStatuses[addressId] ?? .untouched
            manager.updateAddressState(
                addressId: addressId.uuidString,
                status: effectiveAddressLayerStatus(addressId: addressId, baseStatus: status),
                scansTotal: 0
            )
        }

        for building in visibleBuildingFeatures {
            guard let gersId = building.properties.canonicalBuildingIdentifier ?? building.id else { continue }
            let scansTotal = building.properties.scansTotal
            let addressIds = addressIdsForBuilding(gersId: gersId)
            let fallbackStatus: AddressStatus?
            if let addressIdString = building.properties.addressId,
               let addressId = UUID(uuidString: addressIdString) {
                fallbackStatus = addressStatuses[addressId]
            } else {
                fallbackStatus = nil
            }
            manager.updateBuildingState(
                gersId: gersId,
                status: effectiveBuildingLayerStatus(
                    gersId: gersId,
                    addressIds: addressIds,
                    fallbackStatus: fallbackStatus
                ),
                scansTotal: scansTotal
            )
        }
    }

    private func deduplicatedAddressIds(_ addressIds: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return addressIds.filter { seen.insert($0).inserted }
    }

    private func applyPersistedAddressStatusLocally(_ status: AddressStatus, addressIds: [UUID]) async {
        let uniqueAddressIds = deduplicatedAddressIds(addressIds)
        await MainActor.run {
            for addressId in uniqueAddressIds {
                let effectiveStatus = status == .delivered
                    ? AddressStatus.automaticDeliveredStatus(preserving: addressStatuses[addressId])
                    : status
                addressStatuses[addressId] = effectiveStatus
                layerManager?.updateAddressState(
                    addressId: addressId.uuidString,
                    status: effectiveAddressLayerStatus(addressId: addressId, baseStatus: effectiveStatus),
                    scansTotal: 0
                )
            }
            refreshTownhomeStatusOverlay()
        }
    }

    private func refreshBuildingStateAfterPersistedStatus(
        buildingId: String,
        fallbackAddressIds: [UUID]
    ) async {
        let uniqueFallbackIds = deduplicatedAddressIds(fallbackAddressIds)
        await MainActor.run {
            let allAddressIds = deduplicatedAddressIds(addressIdsForBuilding(gersId: buildingId))
            let effectiveAddressIds = allAddressIds.isEmpty ? uniqueFallbackIds : allAddressIds
            let buildingStatus = effectiveBuildingLayerStatus(
                gersId: buildingId,
                addressIds: effectiveAddressIds,
                fallbackStatus: .delivered
            )
            layerManager?.updateBuildingState(gersId: buildingId, status: buildingStatus, scansTotal: 0)
            refreshTownhomeStatusOverlay()
        }
    }

    private func markSessionTargetDelivered(targetId: String) async throws {
        let result = try await sessionManager.persistDeliveredVisitTarget(targetId: targetId)
        let addressIds = deduplicatedAddressIds(result.addressIds)
        guard !addressIds.isEmpty else {
            print("ℹ️ [CampaignMap] No address IDs resolved for session target \(targetId)")
            return
        }
        await applyPersistedAddressStatusLocally(.delivered, addressIds: addressIds)

        guard let buildingId = result.buildingId ?? resolvedBuildingIdForSessionTarget(targetId: targetId, addressIds: addressIds) else {
            return
        }

        await refreshBuildingStateAfterPersistedStatus(buildingId: buildingId, fallbackAddressIds: addressIds)
    }

    private func gersIdForAddress(addressId: UUID) -> String? {
        visibleAddressFeatures.first(where: { feature in
            guard let idStr = feature.properties.id ?? feature.id,
                  let uuid = UUID(uuidString: idStr) else { return false }
            return uuid == addressId
        })?.properties.buildingGersId
        ?? visibleAddressFeatures.first(where: { feature in
            guard let idStr = feature.properties.id ?? feature.id,
                  let uuid = UUID(uuidString: idStr) else { return false }
            return uuid == addressId
        })?.properties.gersId
        ?? visibleBuildingFeatures.first(where: { feature in
            guard let addressIdString = feature.properties.addressId,
                  let uuid = UUID(uuidString: addressIdString) else { return false }
            return uuid == addressId
        })?.properties.canonicalBuildingIdentifier
        ?? visibleBuildingFeatures.first(where: { feature in
            guard let addressIdString = feature.properties.addressId,
                  let uuid = UUID(uuidString: addressIdString) else { return false }
            return uuid == addressId
        })?.id
    }

    private func matchingSessionTargetId(_ candidate: String) -> String? {
        sessionManager.targetBuildings.first {
            $0.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func sessionTargetIdForAddress(addressId: UUID) -> String? {
        if let addressTargetId = matchingSessionTargetId(addressId.uuidString.lowercased()) {
            return addressTargetId
        }

        guard let gersId = gersIdForAddress(addressId: addressId),
              addressIdsForBuilding(gersId: gersId).count <= 1 else {
            return nil
        }

        return matchingSessionTargetId(gersId)
    }

    private func featureStateStatus(for status: AddressStatus) -> String {
        switch status {
        case .none, .untouched:
            return "not_visited"
        case .noAnswer:
            return "no_answer"
        case .delivered:
            return "delivered"
        case .talked:
            return "talked"
        case .appointment:
            return "appointment"
        case .doNotKnock:
            return "do_not_knock"
        case .futureSeller:
            return "future_seller"
        case .hotLead:
            return "hot_lead"
        }
    }

    private func buildingFeatureStateStatus(for status: AddressStatus) -> String {
        switch status {
        case .talked, .appointment, .hotLead:
            return "hot"
        case .doNotKnock:
            return "do_not_knock"
        case .delivered, .noAnswer, .futureSeller:
            return "visited"
        case .none, .untouched:
            return "not_visited"
        }
    }

    /// Compute the map layer status for a building based on ALL its address statuses.
    /// Red means untouched units remain, green means completed with no conversations,
    /// and blue means at least one unit is in a conversation/hot state.
    private func computeBuildingLayerStatus(gersId: String, addressIds: [UUID]) -> String {
        guard !addressIds.isEmpty else { return "not_visited" }
        let statuses = addressIds.compactMap { addressStatuses[$0] }
        guard !statuses.isEmpty else { return "not_visited" }

        let allVisited = statuses.allSatisfy {
            switch $0 {
            case .delivered, .noAnswer, .doNotKnock, .futureSeller:
                return true
            default:
                return false
            }
        }
        if allVisited {
            let allDoNotKnock = statuses.allSatisfy { $0 == .doNotKnock }
            return allDoNotKnock ? "do_not_knock" : "visited"
        }

        let anyHot = statuses.contains {
            switch $0 {
            case .talked, .appointment, .hotLead:
                return true
            default:
                return false
            }
        }
        if anyHot { return "hot" }

        let anyVisited = statuses.contains {
            switch $0 {
            case .delivered, .noAnswer, .doNotKnock, .futureSeller:
                return true
            default:
                return false
            }
        }
        return anyVisited ? "visited" : "not_visited"
    }

    private func mapFieldLeadStatusToAddressStatus(_ status: FieldLeadStatus) -> AddressStatus {
        switch status {
        case .notHome: return .noAnswer
        case .interested: return .hotLead
        case .noAnswer: return .noAnswer
        case .qrScanned: return .hotLead
        }
    }

    /// Add session path source and line layer (breadcrumb trail) + session puck layers.
    private func addSessionPathLayersIfNeeded(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        do {
            var source = GeoJSONSource(id: CampaignSessionMapLayerIds.lineSource)
            source.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(source)
            var lineLayer = LineLayer(id: CampaignSessionMapLayerIds.lineLayer, source: CampaignSessionMapLayerIds.lineSource)
            lineLayer.lineColor = .constant(StyleColor(.red))
            lineLayer.lineWidth = .constant(5.0)
            lineLayer.lineOpacity = .constant(0.8)
            lineLayer.lineJoin = .constant(.round)
            lineLayer.lineCap = .constant(.round)
            try mapboxMap.addLayer(lineLayer)

            var headingSource = GeoJSONSource(id: CampaignSessionMapLayerIds.headingConeSource)
            headingSource.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(headingSource)

            for band in UserHeadingConeBand.allCases {
                var layer = FillLayer(id: CampaignSessionMapLayerIds.headingLayer(for: band), source: CampaignSessionMapLayerIds.headingConeSource)
                layer.filter = Exp(.eq) {
                    Exp(.get) { "band" }
                    band.rawValue
                }
                layer.fillColor = .constant(UserHeadingIndicatorRenderer.styleColor(for: band))
                layer.fillOpacity = .constant(1.0)
                try mapboxMap.addLayer(layer)
            }

            var puckSource = GeoJSONSource(id: CampaignSessionMapLayerIds.puckSource)
            puckSource.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(puckSource)
            var puckOuter = CircleLayer(id: CampaignSessionMapLayerIds.puckOuterLayer, source: CampaignSessionMapLayerIds.puckSource)
            puckOuter.circleRadius = .constant(14)
            puckOuter.circleColor = .constant(StyleColor(UIColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 0.28)))
            puckOuter.circleOpacity = .constant(1.0)
            puckOuter.circleStrokeWidth = .constant(0)
            puckOuter.circleBlur = .constant(0.45)
            try mapboxMap.addLayer(puckOuter)
            var puckInner = CircleLayer(id: CampaignSessionMapLayerIds.puckInnerLayer, source: CampaignSessionMapLayerIds.puckSource)
            puckInner.circleRadius = .constant(6)
            puckInner.circleColor = .constant(StyleColor(.white))
            puckInner.circleOpacity = .constant(1.0)
            puckInner.circleStrokeWidth = .constant(0)
            try mapboxMap.addLayer(puckInner)
        } catch {
            print("⚠️ [CampaignMap] Failed to add session path/puck layers: \(error)")
        }
    }

    private func addDemoTargetPulseLayersIfNeeded(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        do {
            if !mapboxMap.sourceExists(withId: CampaignSessionMapLayerIds.demoTargetSource) {
                var source = GeoJSONSource(id: CampaignSessionMapLayerIds.demoTargetSource)
                source.data = .featureCollection(FeatureCollection(features: []))
                try mapboxMap.addSource(source)
            }

            if !mapboxMap.layerExists(withId: CampaignSessionMapLayerIds.demoTargetHaloLayer) {
                var haloLayer = CircleLayer(
                    id: CampaignSessionMapLayerIds.demoTargetHaloLayer,
                    source: CampaignSessionMapLayerIds.demoTargetSource
                )
                haloLayer.circleColor = .constant(StyleColor(.red))
                haloLayer.circleOpacity = .expression(Exp(.get) { "pulse_opacity" })
                haloLayer.circleRadius = .expression(Exp(.get) { "pulse_radius" })
                haloLayer.circleStrokeWidth = .constant(0)
                try mapboxMap.addLayer(haloLayer)
            }

            if !mapboxMap.layerExists(withId: CampaignSessionMapLayerIds.demoTargetCoreLayer) {
                var coreLayer = CircleLayer(
                    id: CampaignSessionMapLayerIds.demoTargetCoreLayer,
                    source: CampaignSessionMapLayerIds.demoTargetSource
                )
                coreLayer.circleColor = .constant(StyleColor(.white))
                coreLayer.circleRadius = .constant(5)
                coreLayer.circleStrokeColor = .constant(StyleColor(.red))
                coreLayer.circleStrokeWidth = .constant(2)
                try mapboxMap.addLayer(coreLayer)
            }
        } catch {
            print("⚠️ [CampaignMap] Failed to add demo target pulse layers: \(error)")
        }
    }

    private func updateDemoTargetPulseOnMap() {
        guard let map = mapView?.mapboxMap else { return }
        guard sessionManager.isDemoSession,
              let target = demoSessionSimulator.currentTarget else {
            map.updateGeoJSONSource(
                withId: CampaignSessionMapLayerIds.demoTargetSource,
                geoJSON: .featureCollection(FeatureCollection(features: []))
            )
            return
        }

        let phase = Double(demoPulseTick % 4) / 3.0
        let radius = 11.0 + (phase * 14.0)
        let opacity = 0.34 - (phase * 0.18)
        var feature = Feature(geometry: .point(Point(target.coordinate)))
        feature.properties = [
            "pulse_radius": .number(radius),
            "pulse_opacity": .number(max(0.08, opacity))
        ]
        map.updateGeoJSONSource(
            withId: CampaignSessionMapLayerIds.demoTargetSource,
            geoJSON: .featureCollection(FeatureCollection(features: [feature]))
        )
    }

    private func focusDemoTargetIfNeeded() {
        guard sessionManager.isDemoSession,
              let target = demoSessionSimulator.currentTarget,
              let map = mapView else { return }
        map.camera.fly(to: CameraOptions(
            center: target.coordinate,
            padding: nil,
            zoom: 17,
            bearing: nil,
            pitch: 60
        ), duration: 0.45)
    }

    /// Update the session path line from current path (normalized when Pro Mode on, else simplified raw).
    private func updateSessionPathOnMap() {
        guard let map = mapView?.mapboxMap else { return }
        let mapCampaignId = UUID(uuidString: campaignId)
        let isCurrentCampaignSession =
            sessionManager.sessionId != nil &&
            mapCampaignId != nil &&
            sessionManager.campaignId == mapCampaignId

        guard isCurrentCampaignSession else {
            map.updateGeoJSONSource(
                withId: CampaignSessionMapLayerIds.lineSource,
                geoJSON: .featureCollection(FeatureCollection(features: []))
            )
            return
        }

        // Demo: hide the live session breadcrumb (red line); map + buildings carry the UX.
        if sessionManager.isDemoSession {
            map.updateGeoJSONSource(
                withId: CampaignSessionMapLayerIds.lineSource,
                geoJSON: .featureCollection(FeatureCollection(features: []))
            )
            return
        }

        let segments = sessionManager.renderPathSegments()
        if segments.contains(where: { $0.count >= 2 }) {
            let features = segments
                .filter { $0.count >= 2 }
                .map { segment -> Feature in
                    let lineCoords = segment.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    return Feature(geometry: .lineString(LineString(lineCoords)))
                }
            let collection = FeatureCollection(features: features)
            map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.lineSource, geoJSON: .featureCollection(collection))
        } else {
            map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.lineSource,
                                    geoJSON: .featureCollection(FeatureCollection(features: [])))
        }
    }
    
    /// Remove 3D building layers from the base map style so campaign map stays flat.
    private static func removeStyleBuildingLayers(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        let idsToRemove = mapboxMap.allLayerIdentifiers
            .map(\.id)
            .filter { $0.lowercased().contains("building") }
        for id in idsToRemove {
            try? mapboxMap.removeLayer(withId: id)
        }
    }

    /// Fly camera to campaign area center when we have features (once per load)
    private func flyToCampaignCenterIfNeeded(map: MapView) {
        guard !hasFlownToCampaign, let center = currentMapCenterCoordinate() else { return }
        hasFlownToCampaign = true
        map.camera.fly(to: CameraOptions(
            center: center,
            padding: nil,
            zoom: 16,
            bearing: nil,
            pitch: 60
        ), duration: 0.8)
    }

    private func currentMapCenterCoordinate() -> CLLocationCoordinate2D? {
        if let activeRouteWorkContext {
            let coords = activeRouteWorkContext.stops.compactMap { stop -> CLLocationCoordinate2D? in
                guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }

            if let center = averageCoordinate(coords) {
                return center
            }
        }

        return featuresService.campaignCenterCoordinate()
    }

    private func averageCoordinate(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coordinates.isEmpty else { return nil }

        let latitude = coordinates.reduce(0) { $0 + $1.latitude } / Double(coordinates.count)
        let longitude = coordinates.reduce(0) { $0 + $1.longitude } / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    private func updateFilters() {
        guard let manager = layerManager else { return }
        manager.showQrScanned = showQrScanned
        manager.showConversations = showConversations
        manager.showTouched = showTouched
        manager.showUntouched = showUntouched
        manager.updateStatusFilter()
    }
    
    private func handleMapLongPress(at point: CGPoint) {
        guard let mapView else { return }
        let coordinate = mapView.mapboxMap.coordinate(for: point)
        let seed = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let context = ManualShapeContext(
            buildingId: nil,
            addressId: nil,
            addressSource: nil,
            seedCoordinate: seed,
            addressText: nil
        )
        startAddHouseFlow(with: context)
    }

    private func handleTap(at point: CGPoint) {
        if activeMapEditTool == .addHouse {
            guard let mapView else { return }
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            let placement = CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            manualAddressPlacement = placement
            layerManager?.updateManualAddressPreview(coordinate: placement)
            return
        }

        guard let manager = layerManager else { return }

        switch displayMode {
        case .buildings:
            manager.getBuildingAt(point: point) { building in
                if let building {
                    presentBuildingSelection(building)
                    return
                }

                manager.getAddressAt(point: point) { address in
                    guard let address else { return }
                    presentAddressSelection(address)
                }
            }
        case .addresses:
            manager.getAddressAt(point: point) { address in
                if let address {
                    presentAddressSelection(address)
                    return
                }

                manager.getBuildingAt(point: point) { building in
                    guard let building else { return }
                    presentBuildingSelection(building)
                }
            }
        }
    }

    private func presentBuildingSelection(_ building: BuildingProperties) {
        selectedBuilding = building
        selectedAddress = resolveAddressForBuilding(building: building)
        selectedAddressIdForCard = nil
        withAnimation { showLocationCard = true }
    }

    private func presentAddressSelection(_ address: MapLayerManager.AddressTapResult) {
        selectedAddress = address
        selectedAddressIdForCard = address.addressId
        let gersIdString = address.buildingGersId ?? address.gersId ?? ""
        if !gersIdString.isEmpty,
           let match = visibleBuildingFeatures.first(where: {
               $0.properties.buildingIdentifierCandidates.contains(where: {
                   $0.caseInsensitiveCompare(gersIdString) == .orderedSame
               }) || ($0.id?.caseInsensitiveCompare(gersIdString) == .orderedSame)
           }) {
            selectedBuilding = match.properties
        } else {
            selectedBuilding = nil
        }
        withAnimation { showLocationCard = true }
    }

    private func prepareManualShapeContext(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) -> ManualShapeContext {
        ManualShapeContext(
            buildingId: building.flatMap { publicBuildingIdentifier(for: $0) },
            addressId: address?.addressId,
            addressSource: address?.source,
            seedCoordinate: seedCoordinate(for: building, address: address),
            addressText: address?.formatted
        )
    }

    private func startAddHouseFlow(with context: ManualShapeContext) {
        cancelPendingManualAddressConfirmation(clearPreview: false)
        manualShapeContext = context
        showLocationCard = false
        selectedBuilding = nil
        selectedAddress = nil
        selectedAddressIdForCard = nil
        activeMapEditTool = .addHouse
        manualAddressPlacement = context.seedCoordinate
        syncManualAddressPreview()
    }

    private var currentManualAddressPreviewCoordinate: CLLocationCoordinate2D? {
        pendingManualAddressConfirmation?.coordinate ?? manualAddressPlacement
    }

    private func syncManualAddressPreview() {
        layerManager?.updateManualAddressPreview(coordinate: currentManualAddressPreviewCoordinate)
    }

    private func handleManualAddressSaved(
        response: ManualAddressCreateResponse,
        coordinate: CLLocationCoordinate2D
    ) {
        manualAddressConfirmationTask?.cancel()
        pendingManualAddressConfirmation = PendingManualAddressConfirmation(
            addressId: response.address.id,
            coordinate: coordinate
        )
        syncManualAddressPreview()

        manualAddressConfirmationTask = Task {
            await confirmPendingManualAddressVisibility()
        }
    }

    private func cancelPendingManualAddressConfirmation(clearPreview: Bool) {
        manualAddressConfirmationTask?.cancel()
        manualAddressConfirmationTask = nil
        pendingManualAddressConfirmation = nil
        if clearPreview {
            layerManager?.clearManualAddressPreview()
        }
    }

    private func completePendingManualAddressConfirmation() {
        cancelPendingManualAddressConfirmation(clearPreview: true)
    }

    private func isPendingManualAddressLoaded(_ addressId: UUID) -> Bool {
        let targetId = addressId.uuidString.lowercased()

        let foundInAddresses = visibleAddressFeatures.contains { feature in
            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
            return featureId == targetId
        }

        if foundInAddresses {
            return true
        }

        return visibleBuildingFeatures.contains { feature in
            (feature.properties.addressId ?? "").lowercased() == targetId
        }
    }

    private func reconcilePendingManualAddressConfirmation() {
        guard let pendingManualAddressConfirmation else { return }
        guard isPendingManualAddressLoaded(pendingManualAddressConfirmation.addressId) else {
            syncManualAddressPreview()
            return
        }
        completePendingManualAddressConfirmation()
    }

    @MainActor
    private func reloadCampaignDataForManualAddressConfirmation() async {
        lastLoadedDataKey = nil
        if let activeRouteWorkContext {
            await featuresService.fetchRouteScopedCampaignFeatures(
                assignmentId: activeRouteWorkContext.assignmentId,
                campaignId: campaignId
            )
        } else {
            await featuresService.fetchAllCampaignFeatures(campaignId: campaignId)
        }
        updateMapData()
    }

    @MainActor
    private func confirmPendingManualAddressVisibility() async {
        for attempt in 0..<Self.manualAddressConfirmationRetryCount {
            guard !Task.isCancelled else { return }
            guard let pendingManualAddressConfirmation else { return }

            if isPendingManualAddressLoaded(pendingManualAddressConfirmation.addressId) {
                completePendingManualAddressConfirmation()
                return
            }

            await reloadCampaignDataForManualAddressConfirmation()

            guard let refreshedPending = self.pendingManualAddressConfirmation else { return }
            if isPendingManualAddressLoaded(refreshedPending.addressId) {
                completePendingManualAddressConfirmation()
                return
            }

            if attempt < Self.manualAddressConfirmationRetryCount - 1 {
                try? await Task.sleep(nanoseconds: Self.manualAddressConfirmationRetryDelayNs)
            }
        }

        guard pendingManualAddressConfirmation != nil else { return }
        manualAddressConfirmationTask = nil
        manualShapeMessage = "House saved, but the map is still syncing. It should appear shortly."
        syncManualAddressPreview()
    }

    private func publicBuildingIdentifier(for building: BuildingProperties) -> String? {
        building.canonicalBuildingIdentifier
    }

    private func normalizedBuildingIdentifiers(for building: BuildingProperties) -> [String] {
        var seen = Set<String>()
        return building.buildingIdentifierCandidates
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
    }

    private func shouldOpenAddressListFirst(for building: BuildingProperties) -> Bool {
        if let addressCount = building.addressCount, addressCount > 1 {
            return true
        }
        if building.unitsCount > 1 {
            return true
        }

        let buildingIds = normalizedBuildingIdentifiers(for: building)
        if buildingIds.contains(where: { addressIdsForBuilding(gersId: $0).count > 1 }) {
            return true
        }

        for buildingId in buildingIds {
            let linkedAddressIds = featuresService.silverBuildingLinks[buildingId] ?? []
            let normalizedLinkedIds = Set(linkedAddressIds.map { $0.lowercased() })
            if normalizedLinkedIds.count > 1 {
                return true
            }
        }

        return false
    }

    private func setSelectedAddressForCard(_ addressId: UUID?) {
        selectedAddressIdForCard = addressId

        guard let addressId else {
            selectedAddress = nil
            return
        }

        selectedAddress = nil
        let targetId = addressId.uuidString.lowercased()
        if let feature = visibleAddressFeatures.first(where: {
            (($0.properties.id ?? $0.id ?? "").lowercased()) == targetId
        }) {
            selectedAddress = addressTapResult(from: feature)
        }
    }

    private func seedCoordinate(
        for building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) -> CLLocationCoordinate2D? {
        if let addressId = address?.addressId.uuidString.lowercased(),
           let addressFeature = visibleAddressFeatures.first(where: {
               (($0.properties.id ?? $0.id ?? "").lowercased()) == addressId
           }),
           let coordinate = CampaignTargetResolver.coordinate(for: addressFeature.geometry) {
            return coordinate
        }

        guard let building else { return nil }
        let buildingIds = Set(
            building.buildingIdentifierCandidates
                .map { $0.lowercased() }
        )
        guard let buildingFeature = visibleBuildingFeatures.first(where: { feature in
            let featureIds = [
                feature.properties.gersId?.lowercased(),
                feature.properties.buildingId?.lowercased(),
                feature.id?.lowercased()
            ]
            return featureIds.contains(where: { id in
                guard let id else { return false }
                return buildingIds.contains(id)
            })
        }) else {
            return nil
        }
        return CampaignTargetResolver.coordinate(for: buildingFeature.geometry)
    }

    private func handleDeleteManualShape(
        building: BuildingProperties?,
        address: MapLayerManager.AddressTapResult?
    ) {
        Task {
            do {
                if address?.source?.lowercased() == "manual", let addressId = address?.addressId {
                    try await BuildingLinkService.shared.deleteManualAddress(
                        campaignId: campaignId,
                        addressId: addressId
                    )
                } else if let building, building.source?.lowercased() == "manual",
                          let buildingId = publicBuildingIdentifier(for: building) {
                    try await BuildingLinkService.shared.deleteManualBuilding(
                        campaignId: campaignId,
                        buildingId: buildingId
                    )
                } else {
                    await MainActor.run {
                        manualShapeMessage = "Only manual buildings or manual houses can be deleted from tools."
                    }
                    return
                }

                await MainActor.run {
                    showLocationCard = false
                    selectedBuilding = nil
                    selectedAddress = nil
                    selectedAddressIdForCard = nil
                    loadCampaignData(force: true)
                }
            } catch {
                await MainActor.run {
                    manualShapeMessage = error.localizedDescription
                }
            }
        }
    }

    /// Resolve address(es) from loaded address features for a tapped building.
    /// Tries multiple matching strategies: addressId, gersId, building id, and address_text.
    private func resolveAddressForBuilding(building: BuildingProperties) -> MapLayerManager.AddressTapResult? {
        // Multi-address Gold: address_id is null → don't resolve to a single address; list mode handles it
        if building.source == "gold",
           building.addressId == nil || building.addressId?.isEmpty == true {
            return nil
        }

        // Address cylinders often carry the campaign address UUID in `id` only; lenient building decode hides `address_id`.
        if let addrId = UUID(uuidString: building.id.trimmingCharacters(in: .whitespacesAndNewlines)),
           !visibleAddressFeatures.isEmpty {
            for feature in visibleAddressFeatures {
                let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
                if featureId == addrId.uuidString.lowercased() {
                    if let result = addressTapResult(from: feature) { return result }
                }
            }
        }

        // Fast path: address ID is embedded (Gold, or Silver enriched by backend).
        // Only use it directly when the building also carries address text (Gold).
        // For Silver S3 buildings address_id is set but addressText is nil — fall through to
        // Strategy 1 so we pick up the formatted address from the already-loaded address features.
        if let addrIdStr = building.addressId, !addrIdStr.isEmpty,
           let addrId = UUID(uuidString: addrIdStr),
           let formatted = nonEmptyAddressText(
               formatted: building.addressText,
               houseNumber: building.houseNumber,
               streetName: building.streetName
           ) {
            return MapLayerManager.AddressTapResult(
                addressId: addrId,
                formatted: formatted,
                gersId: building.gersId,
                buildingGersId: building.buildingId,
                houseNumber: building.houseNumber,
                streetName: building.streetName,
                source: nil
            )
        }

        let addresses = visibleAddressFeatures
        guard !addresses.isEmpty else { return nil }

        // Collect all building IDs for matching (case-insensitive)
        var buildingIds: [String] = []
        if let g = building.gersId, !g.isEmpty { buildingIds.append(g.lowercased()) }
        if !building.id.isEmpty { buildingIds.append(building.id.lowercased()) }
        if let bid = building.buildingId, !bid.isEmpty { buildingIds.append(bid.lowercased()) }

        // Silver strategy: use preloaded building_address_links (gers_id → [address_id]).
        // This is the authoritative source for Silver S3 buildings, which arrive from the Lambda
        // without address_id embedded in their GeoJSON properties.
        // Deliberately skipped for Gold buildings (they resolve via addressId fast path above).
        if building.source != "gold" {
            for gersKey in buildingIds {
                if let linkedIds = featuresService.silverBuildingLinks[gersKey], !linkedIds.isEmpty {
                    // Multi-address Silver building: return the first linked address.
                    // (Full multi-address sheet support can be added later.)
                    for linkedId in linkedIds {
                        for feature in addresses {
                            let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
                            if featureId == linkedId.lowercased() {
                                if let result = addressTapResult(from: feature) { return result }
                            }
                        }
                    }
                }
            }
        }

        // Strategy 1: Match by building's addressId against address feature id (Gold / enriched Silver)
        if let addrIdStr = building.addressId, !addrIdStr.isEmpty {
            for feature in addresses {
                let featureId = (feature.properties.id ?? feature.id ?? "").lowercased()
                if featureId == addrIdStr.lowercased() {
                    if let result = addressTapResult(from: feature) { return result }
                }
            }
        }

        // Strategy 2: Match building IDs against address building_gers_id (case-insensitive)
        for feature in addresses {
            let addrBuildingGers = (feature.properties.buildingGersId ?? "").lowercased()
            if !addrBuildingGers.isEmpty, buildingIds.contains(addrBuildingGers) {
                if let result = addressTapResult(from: feature) { return result }
            }
        }

        // Strategy 3: Match building's addressText against address formatted text
        if let buildingAddr = building.addressText, !buildingAddr.isEmpty {
            let normalized = buildingAddr.lowercased().trimmingCharacters(in: .whitespaces)
            for feature in addresses {
                let formatted = (feature.properties.formatted ?? "").lowercased().trimmingCharacters(in: .whitespaces)
                if !formatted.isEmpty, formatted.contains(normalized) || normalized.contains(formatted) {
                    if let result = addressTapResult(from: feature) { return result }
                }
            }
        }

        return nil
    }

    /// Convert an address feature into an AddressTapResult
    private func addressTapResult(from feature: AddressFeature) -> MapLayerManager.AddressTapResult? {
        let idString = feature.properties.id ?? feature.id ?? ""
        guard let uuid = UUID(uuidString: idString) else { return nil }
        let formatted = nonEmptyAddressText(
            formatted: feature.properties.formatted,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName
        ) ?? "Address"
        return MapLayerManager.AddressTapResult(
            addressId: uuid,
            formatted: formatted,
            gersId: feature.properties.gersId,
            buildingGersId: feature.properties.buildingGersId,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName,
            source: feature.properties.source
        )
    }

    /// Prefer explicit formatted value, then fall back to "house number + street name".
    private func nonEmptyAddressText(formatted: String?, houseNumber: String?, streetName: String?) -> String? {
        let formattedValue = formatted?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !formattedValue.isEmpty {
            return formattedValue
        }
        let house = houseNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let street = streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let combined = "\(house) \(street)".trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private func markAutoCompletedBuildingDelivered(gersId: String) async {
        guard let campaignUUID = UUID(uuidString: campaignId) else { return }
        let addressIds = deduplicatedAddressIds(addressIdsForBuilding(gersId: gersId))
        guard !addressIds.isEmpty else {
            print("ℹ️ [CampaignMap] Auto-completed building \(gersId) has no mapped address IDs for delivered sync")
            return
        }
        let addressIdsToDeliver = addressIds.filter { addressId in
            automaticCompletionStatusForAddress(addressId) == .delivered &&
            addressStatuses[addressId] != .delivered
        }

        if !addressIdsToDeliver.isEmpty {
            do {
                try await VisitsAPI.shared.updateTargetStatus(
                    addressIds: addressIdsToDeliver,
                    campaignId: campaignUUID,
                    status: .delivered,
                    notes: nil,
                    sessionId: sessionManager.sessionId,
                    sessionTargetId: gersId,
                    sessionEventType: .flyerLeft,
                    location: sessionManager.currentLocation
                )
            } catch {
                print("⚠️ [CampaignMap] Failed to mark auto-completed building delivered (\(gersId)): \(error)")
                return
            }
        }
        await applyPersistedAddressStatusLocally(.delivered, addressIds: addressIds)

        await refreshBuildingStateAfterPersistedStatus(buildingId: gersId, fallbackAddressIds: addressIds)
    }

    private func addressLabelsForTargets() -> [String: String] {
        let targets = sessionManager.sessionMode == .flyer ? flyerSessionTargets : preferredSessionTargets
        return Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.label) })
    }

    private func sessionTargets(for mode: SessionMode) -> [ResolvedCampaignTarget] {
        switch mode {
        case .doorKnocking:
            return preferredSessionTargets
        case .flyer:
            return flyerSessionTargets
        }
    }

    /// Restore clears `SessionManager.buildingCentroids`; repopulate from loaded GeoJSON so GPS visit scoring can run again.
    private func rehydrateSessionVisitInferenceIfNeeded() {
        guard sessionManager.sessionId != nil else { return }
        var seen = Set<String>()
        var merged: [ResolvedCampaignTarget] = []
        for t in buildingSessionTargets {
            let k = t.id.lowercased()
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            merged.append(t)
        }
        for t in CampaignTargetResolver.addressTargets(from: visibleAddressFeatures) {
            let k = t.id.lowercased()
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            merged.append(t)
        }
        guard !merged.isEmpty else { return }
        sessionManager.rehydrateVisitInferenceFromMapTargets(merged)
        refreshSessionTargetMappings(for: merged)
    }

    private func startBuildingSession(
        campaignId: UUID,
        targets: [ResolvedCampaignTarget],
        mode: SessionMode = .doorKnocking,
        goalAmount: Int? = nil,
        routeAssignmentId: UUID? = nil,
        farmExecutionContext: FarmExecutionContext? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        let targetIds = targets.map(\.id)
        guard !targetIds.isEmpty else {
            onFinished?()
            return
        }
        let centroids = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.coordinate) })
        Task {
            do {
                try await sessionManager.startBuildingSession(
                    campaignId: campaignId,
                    targetBuildings: targetIds,
                    autoCompleteEnabled: mode == .flyer,
                    centroids: centroids,
                    mode: mode,
                    goalAmountOverride: goalAmount,
                    routeAssignmentId: routeAssignmentId,
                    farmExecutionContext: farmExecutionContext
                )
                await MainActor.run {
                    if farmExecutionContext != nil {
                        uiState.clearPlannedFarmExecution()
                    }
                    refreshSessionTargetMappings(for: targets)
                }
            } catch {
                print("⚠️ [CampaignMap] Failed to start session: \(error.localizedDescription)")
                let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    sessionStartGateMessage = msg
                    showSessionStartGateAlert = true
                }
            }
            await MainActor.run {
                onFinished?()
            }
        }
    }

    private func maybeStartDemoSession() {
        guard let demoLaunchConfiguration,
              !hasStartedDemoLaunch,
              sessionManager.sessionId == nil,
              UUID(uuidString: campaignId) == demoLaunchConfiguration.campaign.id else {
            return
        }

        let desiredCount = min(preferredSessionTargets.count, max(1, demoLaunchConfiguration.homeCount))
        let targets = DemoSessionRoutePlanner.orderedTargets(preferredSessionTargets, limit: desiredCount)
        guard !targets.isEmpty else { return }

        hasStartedDemoLaunch = true
        displayMode = .buildings
        scheduleLayerVisibilityReassert()

        let centroids = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0.coordinate) })
        let initialCoordinate = targets.first?.coordinate
        Task {
            let corridors = await CampaignRoadService.shared.getRoadsForSession(campaignId: campaignId)
            let steps = DemoSessionRoutePlanner.buildSteps(for: targets, corridors: corridors)

            guard let campaignUUID = UUID(uuidString: campaignId) else { return }
            sessionManager.startDemoBuildingSession(
                campaignId: campaignUUID,
                targetBuildings: targets.map(\.id),
                centroids: centroids,
                mode: .doorKnocking,
                initialLocation: initialCoordinate
            )

            demoSessionSimulator.start(
                steps: steps,
                speed: demoLaunchConfiguration.speed,
                initialCoordinate: initialCoordinate,
                onTargetWillAdvance: { target in
                    demoPulseTick = 0
                    focusBuildingId = target.buildingId ?? target.id
                },
                onLocationUpdate: { coordinate, appendToTrail in
                    await sessionManager.injectDemoLocation(coordinate, appendToTrail: appendToTrail)
                },
                onTargetHit: { target in
                    do {
                        try await markSessionTargetDelivered(targetId: target.id)
                        try await sessionManager.completeBuilding(target.id)
                        sessionManager.recordAddressDelivered()
                    } catch {
                        print("⚠️ [CampaignMap] Demo target completion failed for \(target.id): \(error)")
                    }
                },
                onFinish: { reason in
                    Task {
                        switch reason {
                        case .completed, .stopped:
                            await stopDemoSessionAndDismiss()
                        }
                    }
                }
            )
        }
    }

    private func stopDemoSessionAndDismiss() async {
        demoSessionSimulator.stop(notify: false)
        await sessionManager.stopBuildingSession(presentSummary: true)
    }

    // MARK: - Real-time Subscription
    
    private func setupRealTimeSubscription() {
        guard let campId = UUID(uuidString: campaignId) else { return }
        guard subscribedRealtimeCampaignId != campId else { return }
        subscribedRealtimeCampaignId = campId
        
        let subscriber = BuildingStatsSubscriber(supabase: SupabaseManager.shared.client)
        self.statsSubscriber = subscriber
        
        // Set up update callback before subscribing
        Task {
            await subscriber.setUpdateCallback { gersId, status, scansTotal, qrScanned in
                Task { @MainActor in
                    self.updateBuildingColor(gersId: gersId, status: status, scansTotal: scansTotal, qrScanned: qrScanned)
                }
            }
            print("🧭 [session_start.subscribe_realtime] begin campaign=\(campId.uuidString)")
            await subscriber.subscribe(campaignId: campId)
            print("🧭 [session_start.subscribe_realtime] success")
        }
    }
    
    private func updateBuildingColor(gersId: String, status: String, scansTotal: Int, qrScanned: Bool) {
        guard let manager = layerManager else { return }
        print("📊 Building stats updated: GERS=\(gersId), status=\(status), scans=\(scansTotal)")
        let effectiveStatus: String
        if sessionManager.pendingVisitedBuildingIds.contains(gersId.lowercased()) {
            effectiveStatus = "pending_visited"
        } else if sessionManager.confirmedVisitedBuildingIds.contains(gersId.lowercased()), status == "not_visited" {
            effectiveStatus = "visited"
        } else {
            effectiveStatus = status
        }
        manager.updateBuildingState(gersId: gersId, status: effectiveStatus, scansTotal: scansTotal)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

private extension Array where Element == BuildingFeature {
    func sortedByRouteScope(_ scope: RouteWorkContext?) -> [BuildingFeature] {
        guard let scope else { return self }

        return sorted { lhs, rhs in
            let lhsOrder = scope.stopOrder(
                addressId: lhs.properties.addressId.flatMap(UUID.init(uuidString:)),
                buildingIdentifiers: lhs.properties.buildingIdentifierCandidates
            ) ?? .max
            let rhsOrder = scope.stopOrder(
                addressId: rhs.properties.addressId.flatMap(UUID.init(uuidString:)),
                buildingIdentifiers: rhs.properties.buildingIdentifierCandidates
            ) ?? .max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            let lhsLabel = lhs.properties.addressText ?? lhs.properties.houseNumber ?? lhs.id ?? ""
            let rhsLabel = rhs.properties.addressText ?? rhs.properties.houseNumber ?? rhs.id ?? ""
            return lhsLabel.localizedStandardCompare(rhsLabel) == .orderedAscending
        }
    }
}

private extension Array where Element == AddressFeature {
    func sortedByRouteScope(_ scope: RouteWorkContext?) -> [AddressFeature] {
        guard let scope else { return self }

        return sorted { lhs, rhs in
            let lhsOrder = scope.stopOrder(
                addressId: UUID(uuidString: lhs.properties.id ?? lhs.id ?? ""),
                buildingIdentifiers: [lhs.properties.buildingGersId, lhs.properties.gersId].compactMap { $0 }
            ) ?? .max
            let rhsOrder = scope.stopOrder(
                addressId: UUID(uuidString: rhs.properties.id ?? rhs.id ?? ""),
                buildingIdentifiers: [rhs.properties.buildingGersId, rhs.properties.gersId].compactMap { $0 }
            ) ?? .max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            let lhsLabel = lhs.properties.formatted ?? lhs.properties.houseNumber ?? lhs.id ?? ""
            let rhsLabel = rhs.properties.formatted ?? rhs.properties.houseNumber ?? rhs.id ?? ""
            return lhsLabel.localizedStandardCompare(rhsLabel) == .orderedAscending
        }
    }
}

// MARK: - Mapbox Map Representable

private enum CampaignSessionMapLayerIds {
    static let lineSource = "session-line-source"
    static let lineLayer = "session-line-layer"
    static let demoTargetSource = "demo-target-source"
    static let demoTargetHaloLayer = "demo-target-halo-layer"
    static let demoTargetCoreLayer = "demo-target-core-layer"
    static let puckSource = "session-puck-source"
    static let puckOuterLayer = "session-puck-outer"
    static let puckInnerLayer = "session-puck-inner"
    static let headingConeSource = "session-heading-cone-source"

    static func headingLayer(for band: UserHeadingConeBand) -> String {
        "session-heading-cone-\(band.rawValue)"
    }
}

struct CampaignMapboxMapViewRepresentable: UIViewRepresentable {
    var preferredSize: CGSize = CGSize(width: 320, height: 260)
    var useDarkStyle: Bool = false
    var sessionLocation: CLLocation?
    var sessionHeadingState: MapHeadingState = .unavailable
    var showSessionPuck: Bool = false
    let onMapReady: (MapView) -> Void
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void

    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!

    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions()
        // Fallback when preferredSize is zero, negative, or non-finite to avoid Mapbox "Invalid size" / content scale factor nan
        let pw = preferredSize.width
        let ph = preferredSize.height
        let size: CGSize
        if pw.isFinite, ph.isFinite, pw > 0, ph > 0 {
            size = CGSize(width: max(320, pw), height: max(260, ph))
        } else {
            size = CGSize(width: 320, height: 260)
        }
        let initialFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let mapView = MapView(frame: initialFrame, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let scale = mapView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0 {
            mapView.contentScaleFactor = scale
        }

        let styleURI = useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI
        mapView.mapboxMap.loadStyle(styleURI)
        
        // Enable gestures
        mapView.gestures.options.pitchEnabled = true
        mapView.gestures.options.rotateEnabled = true
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        longPressGesture.cancelsTouchesInView = false
        mapView.addGestureRecognizer(longPressGesture)

        context.coordinator.mapView = mapView
        
        DispatchQueue.main.async {
            onMapReady(mapView)
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
        let width = preferredSize.width
        let height = preferredSize.height
        let resolvedSize: CGSize
        if width.isFinite, height.isFinite, width > 0, height > 0 {
            resolvedSize = CGSize(width: max(320, width), height: max(260, height))
        } else {
            resolvedSize = CGSize(width: 320, height: 260)
        }
        if uiView.bounds.size != resolvedSize {
            uiView.bounds = CGRect(origin: .zero, size: resolvedSize)
        }
        context.coordinator.updateSessionPuck(
            location: sessionLocation,
            headingState: sessionHeadingState,
            show: showSessionPuck
        )
        let scale = uiView.window?.screen.scale ?? UIScreen.main.scale
        if scale.isFinite, scale > 0, uiView.contentScaleFactor != scale {
            uiView.contentScaleFactor = scale
        }
        uiView.setNeedsLayout()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }
    
    class Coordinator: NSObject {
        weak var mapView: MapView?
        var onTap: (CGPoint) -> Void
        var onLongPress: (CGPoint) -> Void
        private var lastPuckSnapshot: PuckSnapshot?

        init(onTap: @escaping (CGPoint) -> Void, onLongPress: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        func updateSessionPuck(location: CLLocation?, headingState: MapHeadingState, show: Bool) {
            guard let map = mapView?.mapboxMap else { return }
            guard map.sourceExists(withId: CampaignSessionMapLayerIds.puckSource) else { return }
            let snapshot = PuckSnapshot(location: location?.coordinate, headingState: headingState, show: show)
            guard lastPuckSnapshot != snapshot else { return }
            lastPuckSnapshot = snapshot
            let emptyCollection = FeatureCollection(features: [])

            if show, let loc = location {
                let feature = Feature(geometry: .point(Point(loc.coordinate)))
                map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.puckSource, geoJSON: .feature(feature))

                if map.sourceExists(withId: CampaignSessionMapLayerIds.headingConeSource),
                   headingState.isRenderable,
                   let heading = headingState.heading {
                    let collection = UserHeadingIndicatorRenderer.featureCollection(center: loc.coordinate, heading: heading)
                    map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.headingConeSource, geoJSON: .featureCollection(collection))
                } else if map.sourceExists(withId: CampaignSessionMapLayerIds.headingConeSource) {
                    map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.headingConeSource, geoJSON: .featureCollection(emptyCollection))
                }
            } else {
                map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.puckSource, geoJSON: .featureCollection(emptyCollection))
                if map.sourceExists(withId: CampaignSessionMapLayerIds.headingConeSource) {
                    map.updateGeoJSONSource(withId: CampaignSessionMapLayerIds.headingConeSource, geoJSON: .featureCollection(emptyCollection))
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = gesture.location(in: mapView)
            onTap(point)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView else { return }
            onLongPress(gesture.location(in: mapView))
        }
    }
}

private struct PuckSnapshot: Equatable {
    let latitude: Double?
    let longitude: Double?
    let headingState: MapHeadingState
    let show: Bool

    init(location: CLLocationCoordinate2D?, headingState: MapHeadingState, show: Bool) {
        latitude = location?.latitude
        longitude = location?.longitude
        self.headingState = headingState
        self.show = show
    }
}

// MARK: - Map Legend View

struct MapLegendView: View {
    @Binding var showQrScanned: Bool
    @Binding var showConversations: Bool
    @Binding var showTouched: Bool
    @Binding var showUntouched: Bool
    let onFilterChanged: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.flyrCaption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            LegendItem(
                color: Color(UIColor(hex: "#8b5cf6")!),
                label: "QR Scanned",
                isOn: $showQrScanned,
                onToggle: onFilterChanged
            )
            
            LegendItem(
                color: Color(UIColor(hex: "#3b82f6")!),
                label: "Conversations",
                isOn: $showConversations,
                onToggle: onFilterChanged
            )
            
            LegendItem(
                color: Color(UIColor(hex: "#22c55e")!),
                label: "Touched",
                isOn: $showTouched,
                onToggle: onFilterChanged
            )
            
            LegendItem(
                color: Color(UIColor(hex: "#ef4444")!),
                label: "Untouched",
                isOn: $showUntouched,
                onToggle: onFilterChanged
            )
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    @Binding var isOn: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button {
            HapticManager.light()
            isOn.toggle()
            onToggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .opacity(isOn ? 1.0 : 0.3)
                
                Text(label)
                    .font(.flyrCaption)
                    .foregroundColor(isOn ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Location Card Sub-Views (broken out to reduce generic type depth)

private struct LocationCardTextField: View {
    let placeholder: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let borderColor: Color

    var body: some View {
        TextField(placeholder, text: $text)
            .focused(isFocused)
            .padding(10)
            .foregroundColor(.white)
            .background(Color.black)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borderColor, lineWidth: 1))
    }
}

private struct LocationCardContactFields: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var phoneText: String
    @Binding var emailText: String
    @Binding var showSecondContact: Bool
    @Binding var secondFirstName: String
    @Binding var secondLastName: String
    @Binding var secondPhoneText: String
    @Binding var secondEmailText: String
    var isFocused: FocusState<Bool>.Binding
    let placeholderColor: Color
    let borderColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person")
                        .foregroundColor(placeholderColor)
                        .frame(width: 20)
                    LocationCardTextField(placeholder: "First name", text: $firstName, isFocused: isFocused, borderColor: borderColor)
                }
                LocationCardTextField(placeholder: "Last name", text: $lastName, isFocused: isFocused, borderColor: borderColor)
            }
            HStack(spacing: 8) {
                Image(systemName: "phone")
                    .foregroundColor(placeholderColor)
                    .frame(width: 20)
                LocationCardTextField(placeholder: "Phone", text: $phoneText, isFocused: isFocused, borderColor: borderColor)
            }
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .foregroundColor(placeholderColor)
                    .frame(width: 20)
                LocationCardTextField(placeholder: "Email", text: $emailText, isFocused: isFocused, borderColor: borderColor)
            }
            Button {
                if showSecondContact {
                    secondFirstName = ""
                    secondLastName = ""
                    secondPhoneText = ""
                    secondEmailText = ""
                }
                showSecondContact.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showSecondContact ? "minus.circle" : "plus.circle")
                        .foregroundColor(.red)
                        .frame(width: 20)
                    Text(showSecondContact ? "Remove 2nd contact" : "Add 2nd contact")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showSecondContact {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .foregroundColor(placeholderColor)
                            .frame(width: 20)
                        LocationCardTextField(placeholder: "2nd first name", text: $secondFirstName, isFocused: isFocused, borderColor: borderColor)
                    }
                    LocationCardTextField(placeholder: "2nd last name", text: $secondLastName, isFocused: isFocused, borderColor: borderColor)
                }
                HStack(spacing: 8) {
                    Image(systemName: "phone")
                        .foregroundColor(placeholderColor)
                        .frame(width: 20)
                    LocationCardTextField(placeholder: "2nd phone", text: $secondPhoneText, isFocused: isFocused, borderColor: borderColor)
                }
                HStack(spacing: 8) {
                    Image(systemName: "envelope")
                        .foregroundColor(placeholderColor)
                        .frame(width: 20)
                    LocationCardTextField(placeholder: "2nd email", text: $secondEmailText, isFocused: isFocused, borderColor: borderColor)
                }
            }
        }
    }
}

private struct LocationCardExtractedChip: Identifiable {
    let id: String
    let icon: String
    let title: String
    let value: String
    let tint: Color
}

private struct LocationCardExtractedChipsBlock: View {
    let chips: [LocationCardExtractedChip]

    var body: some View {
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Extracted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            HStack(spacing: 8) {
                                Image(systemName: chip.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(chip.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chip.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(chip.value)
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.78))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(chip.tint.opacity(0.14))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(chip.tint.opacity(0.38), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

// MARK: - Follow-up type (location card)

private enum FollowUpType: String, CaseIterable, Identifiable, Codable {
    case call, text, visit, email

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .call: return "phone"
        case .text: return "message"
        case .visit: return "figure.walk"
        case .email: return "envelope"
        }
    }
}

// MARK: - Follow-Up / Appointment sheets (location card)

private struct FollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    let onSave: (String, Date, FollowUpType, String) -> Void
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var date: Date
    @State private var type: FollowUpType
    @State private var notes: String

    init(
        isEditing: Bool,
        initialTitle: String,
        initialDate: Date,
        initialType: FollowUpType,
        initialNotes: String,
        onSave: @escaping (String, Date, FollowUpType, String) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _date = State(initialValue: initialDate)
        _type = State(initialValue: initialType)
        _notes = State(initialValue: initialNotes)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                        TextField("What to do", text: $title)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .foregroundColor(.white)
                            .background(Color.black)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.28), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(FollowUpType.allCases) { t in
                                    Button {
                                        type = t
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: t.icon)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(t.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundColor(type == t ? .white : Color(white: 0.65))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(type == t ? Color.red.opacity(0.85) : Color(white: 0.15))
                                        .cornerRadius(20)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date & time")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                        DatePicker("", selection: $date, displayedComponents: [.date])
                            .labelsHidden()
                            .colorScheme(.dark)
                            .tint(.red)
                            .foregroundColor(.white)
                        DatePicker("", selection: $date, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .colorScheme(.dark)
                            .tint(.red)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (optional)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                        TextField("Add context", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .foregroundColor(.white)
                            .background(Color.black)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.28), lineWidth: 1))
                    }

                    Button {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            date,
                            type,
                            notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        dismiss()
                    } label: {
                        Text(isEditing ? "Save Follow-Up" : "Add Follow-Up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? Color.red : Color.gray.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .buttonStyle(.plain)

                    if isEditing, let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete Follow-Up")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(white: 0.08))
            .navigationTitle(isEditing ? "Edit follow-up" : "Add follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct AppointmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isEditing: Bool
    /// End time is always one hour after start; not shown in the UI.
    let onSave: (String, Date) -> Void
    let onDelete: (() -> Void)?

    @State private var title: String
    @State private var startDate: Date

    init(
        isEditing: Bool,
        initialTitle: String,
        initialStart: Date,
        onSave: @escaping (String, Date) -> Void,
        onDelete: (() -> Void)?
    ) {
        self.isEditing = isEditing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _startDate = State(initialValue: initialStart)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                        TextField("Appointment title", text: $title)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .foregroundColor(.white)
                            .background(Color.black)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.28), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Starts")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.55))
                        Text("Duration is 1 hour")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(white: 0.45))
                        DatePicker("", selection: $startDate, displayedComponents: [.date])
                            .labelsHidden()
                            .colorScheme(.dark)
                            .tint(.red)
                            .foregroundColor(.white)
                        DatePicker("", selection: $startDate, displayedComponents: [.hourAndMinute])
                            .labelsHidden()
                            .colorScheme(.dark)
                            .tint(.red)
                            .foregroundColor(.white)
                    }

                    Button {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            startDate
                        )
                        dismiss()
                    } label: {
                        Text(isEditing ? "Save Appointment" : "Add Appointment")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? Color.red : Color.gray.opacity(0.4))
                            .cornerRadius(12)
                    }
                    .disabled(!canSave)
                    .buttonStyle(.plain)

                    if isEditing, let onDelete {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete Appointment")
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(white: 0.08))
            .navigationTitle(isEditing ? "Edit appointment" : "Add appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Location Card View

@MainActor
struct LocationCardView: View {

    /// Overture GERS ID string (from map feature)
    let gersId: String
    let campaignId: UUID
    let sessionId: UUID?
    /// Campaign address ID from tapped building (used for direct lookup so card shows linked state)
    let addressId: UUID?
    /// Address from tapped building (shown immediately)
    let addressText: String?
    /// When multiple addresses exist, which one to show as primary; nil = show list or first
    var preferredAddressId: UUID?
    var buildingSource: String?
    var addressSource: String?
    /// Per-address statuses for pill coloring in the multi-address list
    var addressStatuses: [UUID: AddressStatus] = [:]
    /// Resolves the session target that should receive completion credit for a specific address.
    var sessionTargetIdForAddress: ((UUID) -> String?)?
    /// Called when user selects an address from the list (id) or taps "Back to list" (nil)
    var onSelectAddress: ((UUID?) -> Void)?
    /// Called once when addresses are resolved, with all address UUIDs for this building
    var onAddressesResolved: (([UUID]) -> Void)?
    let onClose: () -> Void
    /// Called after status is saved to Supabase so the map can update building color immediately
    var onStatusUpdated: ((UUID, AddressStatus) -> Void)?
    var onToolsAction: ((LocationCardToolsAction) -> Void)?
    
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @StateObject private var dataService: BuildingDataService
    @StateObject private var calendarService = CalendarService()
    /// Building details from GET /api/buildings/{gersId} (scan data gated by backend for non‑Pro).
    @State private var buildingDetails: BuildingDetailResponse?
    @StateObject private var voiceRecorder = VoiceRecorderManager()
    @StateObject private var transcriptionService = TranscriptionService()
    @State private var nameText: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var showSecondContact = false
    @State private var secondFirstName: String = ""
    @State private var secondLastName: String = ""
    @State private var secondPhoneText: String = ""
    @State private var secondEmailText: String = ""
    @State private var customHeaderLabel: String = ""
    @State private var phoneText: String = ""
    @State private var emailText: String = ""
    @State private var notesText: String = ""
    @State private var manualAddressText: String = ""
    @State private var showAddResidentSheet = false
    @State private var addResidentAddress: ResolvedAddress?
    @State private var isUploadingVoiceNote = false
    @State private var voiceNoteError: String?
    @State private var showContactBlock = false
    @State private var showNotesBlock = false
    @State private var showDoNotKnockConfirmation = false
    @State private var showDeleteManualShapeConfirmation = false
    @State private var showToolsSheet = false
    @State private var toolMessage: String?
    @State private var showFollowUpDetails = false
    @State private var showAppointmentDetails = false
    @State private var showFollowUpSheet = false
    @State private var showAppointmentSheet = false
    @State private var showVoiceLogPreviewSheet = false
    @State private var followUpText = ""
    @State private var followUpType: FollowUpType = .call
    @State private var followUpNotes = ""
    @State private var followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var appointmentTitle = ""
    @State private var appointmentStartDate = Date()
    @State private var appointmentEndDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
    @State private var voiceLogPreviewResult: VoiceLogResponse?
    @State private var flyrEventIdForRecording: UUID?
    @State private var showPaywall = false
    @State private var showTranscribedNoteSheet = false
    @State private var transcribedNoteText = ""
    @State private var isTranscribing = false
    @State private var isSavingForm = false
    @State private var calendarMessage: String?
    @State private var didHydrateContactFields = false
    @State private var didApplyDraftKey: String?
    @State private var suggestedStatusFromVoice: AddressStatus?
    @State private var shouldPushVoiceToCRM = true
    @State private var showExtractedContactChip = false
    @State private var showExtractedFollowUpChip = false
    @State private var showExtractedAppointmentChip = false
    @State private var showExtractedStatusChip = false
    @State private var contactSaveError: String?
    @State private var contactSaveSuccess = false
    @AppStorage("location_card_notes_auto_record") private var notesAutoRecordEnabled = false
    /// Prevents duplicate concurrent `talked` writes from repeated Contact taps.
    @State private var isPersistingContactTalk = false
    @State private var lastContactTalkPersistAt: Date = .distantPast
    @State private var lastPersistedContactTalkAddressId: UUID?
    @FocusState private var isInputFocused: Bool
    private let contactTalkPersistDebounceSeconds: TimeInterval = 2
    private let locationCardDraftStoragePrefix = "flyr.location_card_draft"

    init(gersId: String, campaignId: UUID, sessionId: UUID? = nil, addressId: UUID? = nil, addressText: String? = nil, preferredAddressId: UUID? = nil, buildingSource: String? = nil, addressSource: String? = nil, addressStatuses: [UUID: AddressStatus] = [:], sessionTargetIdForAddress: ((UUID) -> String?)? = nil, onSelectAddress: ((UUID?) -> Void)? = nil, onAddressesResolved: (([UUID]) -> Void)? = nil, onClose: @escaping () -> Void, onStatusUpdated: ((UUID, AddressStatus) -> Void)? = nil, onToolsAction: ((LocationCardToolsAction) -> Void)? = nil) {
        self.gersId = gersId
        self.campaignId = campaignId
        self.sessionId = sessionId
        self.addressId = addressId
        self.addressText = addressText
        self.preferredAddressId = preferredAddressId
        self.buildingSource = buildingSource
        self.addressSource = addressSource
        self.addressStatuses = addressStatuses
        self.sessionTargetIdForAddress = sessionTargetIdForAddress
        self.onSelectAddress = onSelectAddress
        self.onAddressesResolved = onAddressesResolved
        self.onClose = onClose
        self.onStatusUpdated = onStatusUpdated
        self.onToolsAction = onToolsAction
        _dataService = StateObject(wrappedValue: BuildingDataService(supabase: SupabaseManager.shared.client))
    }
    
    private var cardBackground: Color { .black }
    private var cardFieldBorder: Color { Color(white: 0.28) }
    private var cardPlaceholder: Color { Color(white: 0.5) }
    private var saveButtonDisabled: Bool { isSavingForm }
    private var isManualShape: Bool {
        buildingSource?.lowercased() == "manual" || addressSource?.lowercased() == "manual"
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    /// Street number and name only (e.g. "9 LIVING N, CLARINGTON, ON, CA" or "74 MADDEN PL , BOWMANVILLE, ON" -> "9 LIVING N" / "74 MADDEN PL")
    private func streetOnly(from full: String) -> String {
        if let idx = full.range(of: " , ")?.lowerBound {
            return String(full[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        if let idx = full.range(of: ",")?.lowerBound {
            return String(full[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return full.trimmingCharacters(in: .whitespaces)
    }

    private var preferredHeaderAddressText: String? {
        if let address = dataService.buildingData.address {
            let fullAddress = address.displayFull.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fullAddress.isEmpty {
                return isManualShape ? fullAddress : streetOnly(from: fullAddress)
            }
            let displayStreet = address.displayStreet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayStreet.isEmpty {
                return isManualShape ? displayStreet : streetOnly(from: displayStreet)
            }
        }

        let fallbackAddress = addressText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fallbackAddress.isEmpty {
            return isManualShape ? fallbackAddress : streetOnly(from: fallbackAddress)
        }

        return nil
    }

    /// Placeholder text for the editable card header (same row as Save and X).
    private var headerPlaceholder: String {
        if let headerText = preferredHeaderAddressText {
            return headerText.uppercased()
        }
        if dataService.buildingData.isLoading {
            return "Loading..."
        }
        return "add address"
    }

    private var headerPromptColor: Color {
        dataService.buildingData.addressLinked ? .white : cardPlaceholder
    }

    /// Header label used by UI and event defaults.
    private var headerLabel: String {
        let trimmedCustom = customHeaderLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCustom.isEmpty ? headerPlaceholder : trimmedCustom
    }

    private var fallbackResolvedAddress: ResolvedAddress? {
        guard let addressId else { return nil }

        let formattedValue = addressText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeFormatted = (formattedValue?.isEmpty == false ? formattedValue : nil) ?? ""
        let safeStreet = streetOnly(from: safeFormatted)
        let streetParts = safeStreet.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

        return ResolvedAddress(
            id: addressId,
            street: safeStreet,
            formatted: safeFormatted,
            locality: "",
            region: "",
            postalCode: "",
            houseNumber: streetParts.first.map(String.init) ?? "",
            streetName: streetParts.count > 1 ? String(streetParts[1]) : "",
            gersId: gersId
        )
    }

    private var editableAddress: ResolvedAddress? {
        dataService.buildingData.address ?? fallbackResolvedAddress
    }

    private var needsScroll: Bool {
        showContactBlock || showNotesBlock || dataService.buildingData.error != nil
    }

    @ViewBuilder
    private var cardContentBody: some View {
        if needsScroll {
            ScrollView(.vertical, showsIndicators: false) {
                cardContentViews
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: 420)
        } else {
            cardContentViews
        }
    }

    /// Multiple addresses for this building and no unit selected → show list
    private var showAddressList: Bool {
        let addresses = dataService.buildingData.addresses
        return addresses.count > 1 && preferredAddressId == nil
    }

    @ViewBuilder
    private var cardContentViews: some View {
        if dataService.buildingData.isLoading {
            loadingView
        } else if let error = dataService.buildingData.error {
            errorView(error: error)
        } else if !dataService.buildingData.addressLinked {
            unlinkedBuildingView
        } else if showAddressList {
            multipleAddressesListView
        } else if let address = dataService.buildingData.address {
            mainContentViewWithBackToList(address: address)
        } else if let addressText = addressText, !addressText.isEmpty {
            universalCardContent(displayAddress: addressText, address: editableAddress)
        }
    }

    /// List of addresses for this building; tap one to select
    @ViewBuilder
    private var multipleAddressesListView: some View {
        let addresses = dataService.buildingData.addresses
        VStack(alignment: .leading, spacing: 12) {
            Text("\(addresses.count) addresses")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            ForEach(addresses) { addr in
                let addrStatus = addressStatuses[addr.id]
                let isDoNotKnock = addrStatus == .doNotKnock
                let isVisited = addrStatus?.mapLayerStatus == "visited" && !isDoNotKnock
                let isHot = addrStatus?.mapLayerStatus == "hot"
                Button {
                    onSelectAddress?(addr.id)
                } label: {
                    HStack {
                        Text(streetOnly(from: addr.displayStreet))
                            .font(.system(size: 14))
                            .foregroundColor(
                                isDoNotKnock
                                    ? Color(UIColor(hex: "#9ca3af")!)
                                    : (isVisited ? .green : (isHot ? Color(UIColor(hex: "#3b82f6")!) : .white))
                            )
                        Spacer()
                        if isDoNotKnock {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(UIColor(hex: "#9ca3af")!))
                        } else if isVisited {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                        } else if isHot {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color(UIColor(hex: "#3b82f6")!))
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        isDoNotKnock
                            ? Color(UIColor(hex: "#9ca3af")!).opacity(0.2)
                            : isVisited
                            ? Color.green.opacity(0.15)
                            : (isHot ? Color(UIColor(hex: "#3b82f6")!).opacity(0.15) : Color.white.opacity(0.08))
                    )
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onAppear {
            let ids = dataService.buildingData.addresses.map { $0.id }
            if !ids.isEmpty { onAddressesResolved?(ids) }
        }
        .onChange(of: dataService.buildingData.addresses.count) { _, _ in
            let ids = dataService.buildingData.addresses.map { $0.id }
            if !ids.isEmpty { onAddressesResolved?(ids) }
        }
    }

    /// Single-address content; when multiple exist, show "Back to list"
    @ViewBuilder
    private func mainContentViewWithBackToList(address: ResolvedAddress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if dataService.buildingData.addresses.count > 1, onSelectAddress != nil {
                Button {
                    onSelectAddress?(nil)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Back to list")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            mainContentView(address: address)
        }
    }

    var body: some View {
        rootCardView
    }

    private var rootCardView: some View {
        cardViewWithPresentation
    }

    private var cardViewWithDataLoading: some View {
        baseCardView
            .toolbar { keyboardToolbarContent }
            .task {
                await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId, preferredAddressId: preferredAddressId)
                buildingDetails = try? await BuildingDetailsAPI.shared.fetchBuildingDetails(gersId: gersId, campaignId: campaignId)
            }
            .onChange(of: preferredAddressId) { _, newId in
                Task {
                    await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId, preferredAddressId: newId)
                }
            }
            .onChange(of: appointmentStartDate) { _, newValue in
                appointmentEndDate = newValue.addingTimeInterval(3600)
            }
    }

    private var cardViewWithPrimarySheets: some View {
        cardViewWithDataLoading
            .sheet(isPresented: $showAddResidentSheet, onDismiss: { addResidentAddress = nil }) {
                if let address = addResidentAddress {
                    AddResidentSheetView(
                        address: address,
                        campaignId: campaignId,
                        onSave: {
                            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                            dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
                            await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id, preferredAddressId: address.id)
                        },
                        onDismiss: {
                            showAddResidentSheet = false
                            addResidentAddress = nil
                        }
                    )
                }
            }
    }

    private var cardViewWithAlerts: some View {
        cardViewWithPrimarySheets
            .alert("Voice note", isPresented: .init(get: { voiceNoteError != nil }, set: { if !$0 { voiceNoteError = nil } })) {
                Button("OK", role: .cancel) { voiceNoteError = nil }
            } message: {
                if let msg = voiceNoteError { Text(msg) }
            }
            .alert("Calendar", isPresented: .init(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
                Button("OK", role: .cancel) { calendarMessage = nil }
            } message: {
                if let msg = calendarMessage { Text(msg) }
            }
            .alert("Mark as do not knock?", isPresented: $showDoNotKnockConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Confirm", role: .destructive) {
                    guard let address = editableAddress else { return }
                    deleteHouse(address)
                }
            } message: {
                Text("This will mark the house as do not knock and show it in grey on the map.")
            }
            .alert("Delete manual shape?", isPresented: $showDeleteManualShapeConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    handleToolsAction(.deleteManualShape)
                }
            } message: {
                Text("This removes the manual map object from the campaign and refreshes the map.")
            }
            .alert("Tools", isPresented: .init(get: { toolMessage != nil }, set: { if !$0 { toolMessage = nil } })) {
                Button("OK", role: .cancel) { toolMessage = nil }
            } message: {
                if let toolMessage { Text(toolMessage) }
            }
            .confirmationDialog("Tools", isPresented: $showToolsSheet, titleVisibility: .visible) {
                Button("Add House") {
                    handleToolsAction(.addHouse)
                }
                if editableAddress != nil {
                    Button("Add Visit") {
                        handleToolsAction(.addVisit)
                    }
                    Button("Reset Home") {
                        handleToolsAction(.resetHome)
                    }
                    Button("Do Not Knock", role: .destructive) {
                        showDoNotKnockConfirmation = true
                    }
                }
                if isManualShape {
                    Button("Delete Manual Shape", role: .destructive) {
                        showDeleteManualShapeConfirmation = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't save", isPresented: .init(get: { contactSaveError != nil }, set: { if !$0 { contactSaveError = nil } })) {
                Button("OK", role: .cancel) { contactSaveError = nil }
            } message: {
                if let msg = contactSaveError { Text(msg) }
            }
            .alert("Saved", isPresented: $contactSaveSuccess) {
                Button("OK", role: .cancel) {
                    contactSaveSuccess = false
                    onClose()
                }
            } message: {
                Text("Contact, follow-up, and appointment details have been saved.")
            }
    }

    private var cardViewWithPresentation: some View {
        cardViewWithAlerts
            .sheet(isPresented: $showVoiceLogPreviewSheet) {
                if let result = voiceLogPreviewResult {
                    VoiceLogPreviewSheet(
                        result: result,
                        onDismiss: {
                            showVoiceLogPreviewSheet = false
                            voiceLogPreviewResult = nil
                        }
                    )
                }
            }
            .sheet(isPresented: $showTranscribedNoteSheet) {
                TranscribedNoteSheet(
                    text: $transcribedNoteText,
                    addressId: addressId,
                    campaignId: campaignId,
                    onDismiss: { showTranscribedNoteSheet = false }
                )
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showFollowUpSheet) {
                FollowUpSheet(
                    isEditing: showFollowUpDetails,
                    initialTitle: followUpText,
                    initialDate: followUpDate,
                    initialType: followUpType,
                    initialNotes: followUpNotes,
                    onSave: { title, date, type, notes in
                        followUpText = title
                        followUpDate = date
                        followUpType = type
                        followUpNotes = notes
                        showFollowUpDetails = true
                    },
                    onDelete: showFollowUpDetails
                        ? {
                            followUpText = ""
                            followUpNotes = ""
                            followUpType = .call
                            followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            showFollowUpDetails = false
                        }
                        : nil
                )
            }
            .sheet(isPresented: $showAppointmentSheet) {
                AppointmentSheet(
                    isEditing: showAppointmentDetails,
                    initialTitle: appointmentTitle,
                    initialStart: appointmentStartDate,
                    onSave: { title, start in
                        appointmentTitle = title
                        appointmentStartDate = start
                        appointmentEndDate = start.addingTimeInterval(3600)
                        showAppointmentDetails = true
                    },
                    onDelete: showAppointmentDetails
                        ? {
                            appointmentTitle = ""
                            let now = Date()
                            appointmentStartDate = now
                            appointmentEndDate = now.addingTimeInterval(3600)
                            showAppointmentDetails = false
                        }
                        : nil
                )
            }
    }

    private var baseCardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            cardContentBody
        }
        .frame(maxWidth: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 20)
        .onAppear {
            applyAutosavedDraftIfNeeded()
        }
        .onChange(of: editableAddress?.id) { _, _ in
            applyAutosavedDraftIfNeeded(force: true)
        }
        .onChange(of: locationCardDraftSnapshot) { _, _ in
            persistAutosavedDraft()
        }
        .onDisappear {
            isInputFocused = false
            dismissKeyboard()
        }
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField("", text: $customHeaderLabel, prompt: Text(headerPlaceholder).foregroundColor(headerPromptColor))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
            Spacer(minLength: 8)
            Button("Save") {
                isInputFocused = false
                dismissKeyboard()
                Task {
                    await onSaveForm()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.red)
            .disabled(saveButtonDisabled)
            Button {
                isInputFocused = false
                dismissKeyboard()
                DispatchQueue.main.async {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ToolbarContentBuilder
    private var keyboardToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            HStack {
                Button("Done") {
                    isInputFocused = false
                    dismissKeyboard()
                }
                Spacer(minLength: 0)
                Button("Save") {
                    isInputFocused = false
                    dismissKeyboard()
                    Task {
                        await onSaveForm()
                    }
                }
                .disabled(saveButtonDisabled)
            }
        }
    }

    // MARK: - QR Scans (Pro-gated)

    /// Display scan count for status/badge: from API when Pro, 0 when not Pro so we don’t leak scan data.
    private var displayScanCount: Int {
        guard entitlementsService.canUsePro else { return 0 }
        return buildingDetails?.scans ?? dataService.buildingData.qrStatus.totalScans
    }

    @ViewBuilder
    private var qrScansSection: some View {
        if entitlementsService.canUsePro {
            qrScansRowPro
        } else {
            qrScansRowUpgrade
        }
    }

    private var qrScansRowPro: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(getQRStatusColor().opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "qrcode")
                    .foregroundColor(getQRStatusColor())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayScanCount > 0 ? "Scanned \(displayScanCount)×" : "QR scans")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                Text(
                    buildingDetails?.lastScannedAt.map { "Last scanned \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No scans yet"
                )
                .font(.flyrCaption)
                .foregroundColor(.gray)
            }
            Spacer()
            if displayScanCount > 0 {
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.flyrCaption)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }

    private var qrScansRowUpgrade: some View {
        Button(action: { showPaywall = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "qrcode")
                        .foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("QR scan activity")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text("Upgrade to Pro to see scan activity")
                        .font(.flyrCaption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "crown.fill")
                    .foregroundColor(.yellow)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Loading...")
                .foregroundColor(cardPlaceholder)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Error State
    
    private func errorView(error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                VStack(alignment: .leading) {
                    Text("Error loading data")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(error.localizedDescription)
                        .font(.system(size: 12))
                        .foregroundColor(cardPlaceholder)
                }
            }
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            actionButtons(address: editableAddress)
            Button("Retry") {
                Task {
                    await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId)
                }
            }
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.red)
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Unlinked Building State
    
    private var unlinkedBuildingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            actionButtons(address: editableAddress)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Universal card content (dark layout like screenshot)
    
    private func universalCardContent(displayAddress: String, address: ResolvedAddress?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            actionButtons(address: address)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var contactDetailsFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            LocationCardContactFields(
                firstName: $firstName,
                lastName: $lastName,
                phoneText: $phoneText,
                emailText: $emailText,
                showSecondContact: $showSecondContact,
                secondFirstName: $secondFirstName,
                secondLastName: $secondLastName,
                secondPhoneText: $secondPhoneText,
                secondEmailText: $secondEmailText,
                isFocused: $isInputFocused,
                placeholderColor: cardPlaceholder,
                borderColor: cardFieldBorder
            )
            LocationCardExtractedChipsBlock(chips: extractedPreviewChipModels)
            followUpSchedulingRow
            appointmentSchedulingRow
        }
    }

    /// Empty row with "+" or tappable summary once a follow-up has been added via the sheet.
    /// Icon is outside the bordered box (same layout as Phone / Email).
    private var followUpSchedulingRow: some View {
        Group {
            if showFollowUpDetails {
                Button {
                    showFollowUpSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.right.circle")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(followUpText.isEmpty ? "Follow up" : followUpText)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                Text("\(followUpType.displayName) · \(followUpDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 13))
                                    .foregroundColor(cardPlaceholder)
                                if !followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(followUpNotes)
                                        .font(.system(size: 13))
                                        .foregroundColor(cardPlaceholder)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(cardPlaceholder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showFollowUpSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.right.circle")
                            .foregroundColor(cardPlaceholder)
                            .frame(width: 20)
                        HStack(spacing: 10) {
                            Text("Follow up")
                                .font(.system(size: 17))
                                .foregroundColor(cardPlaceholder)
                            Spacer(minLength: 8)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Empty row with "+" or tappable summary once an appointment has been added via the sheet.
    /// Icon is outside the bordered box (same layout as Phone / Email).
    private var appointmentSchedulingRow: some View {
        Group {
            if showAppointmentDetails {
                Button {
                    showAppointmentSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appointmentTitle.isEmpty ? "Appointment" : appointmentTitle)
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                Text(
                                    "\(appointmentStartDate.formatted(date: .abbreviated, time: .shortened)) · 1 hr"
                                )
                                .font(.system(size: 13))
                                .foregroundColor(cardPlaceholder)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(cardPlaceholder)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showAppointmentSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(cardPlaceholder)
                            .frame(width: 20)
                        HStack(spacing: 10) {
                            Text("Appointment")
                                .font(.system(size: 17))
                                .foregroundColor(cardPlaceholder)
                            Spacer(minLength: 8)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var notesOnlyDetailsFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            notesFieldsBlock
            notesVoiceControls(address: editableAddress)
            LocationCardExtractedChipsBlock(chips: extractedPreviewChipModels)
        }
    }

    private var notesFieldsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldGroupLabel("Notes")
            TextField("Add notes", text: $notesText, axis: .vertical)
                .lineLimit(3...5)
                .focused($isInputFocused)
                .padding(10)
                .foregroundColor(.white)
                .background(Color.black)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
        }
    }

    private func fieldGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
    }

    private enum CalendarDraftKind {
        case followUp
        case appointment
    }

    private struct LocationCardDraftPayload: Codable {
        let customHeaderLabel: String
        let firstName: String
        let lastName: String
        let phoneText: String
        let emailText: String
        let notesText: String
        let followUpText: String
        /// Persisted as `FollowUpType.rawValue`; nil for drafts saved before this field existed.
        let followUpType: String?
        let followUpNotes: String?
        let followUpDate: Date
        let appointmentTitle: String
        let appointmentStartDate: Date
        let appointmentEndDate: Date
        let showFollowUpDetails: Bool
        let showAppointmentDetails: Bool
        let showContactBlock: Bool
        let showNotesBlock: Bool
    }

    private struct LocationCardDraftSnapshot: Equatable {
        let customHeaderLabel: String
        let firstName: String
        let lastName: String
        let phoneText: String
        let emailText: String
        let notesText: String
        let followUpText: String
        let followUpType: FollowUpType
        let followUpNotes: String
        let followUpDate: Date
        let appointmentTitle: String
        let appointmentStartDate: Date
        let appointmentEndDate: Date
        let showFollowUpDetails: Bool
        let showAppointmentDetails: Bool
        let showContactBlock: Bool
        let showNotesBlock: Bool
    }

    private var locationCardDraftSnapshot: LocationCardDraftSnapshot {
        LocationCardDraftSnapshot(
            customHeaderLabel: customHeaderLabel,
            firstName: firstName,
            lastName: lastName,
            phoneText: phoneText,
            emailText: emailText,
            notesText: notesText,
            followUpText: followUpText,
            followUpType: followUpType,
            followUpNotes: followUpNotes,
            followUpDate: followUpDate,
            appointmentTitle: appointmentTitle,
            appointmentStartDate: appointmentStartDate,
            appointmentEndDate: appointmentEndDate,
            showFollowUpDetails: showFollowUpDetails,
            showAppointmentDetails: showAppointmentDetails,
            showContactBlock: showContactBlock,
            showNotesBlock: showNotesBlock
        )
    }

    private var locationCardDraftStorageKey: String {
        let addressComponent = editableAddress?.id.uuidString ?? addressId?.uuidString ?? gersId
        return "\(locationCardDraftStoragePrefix).\(campaignId.uuidString).\(addressComponent)"
    }

    private var hasMeaningfulDraftValues: Bool {
        !customHeaderLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !phoneText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        showFollowUpDetails ||
        showAppointmentDetails
    }

    private func persistAutosavedDraft() {
        let key = locationCardDraftStorageKey
        guard hasMeaningfulDraftValues else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        let payload = LocationCardDraftPayload(
            customHeaderLabel: customHeaderLabel,
            firstName: firstName,
            lastName: lastName,
            phoneText: phoneText,
            emailText: emailText,
            notesText: notesText,
            followUpText: followUpText,
            followUpType: followUpType.rawValue,
            followUpNotes: followUpNotes,
            followUpDate: followUpDate,
            appointmentTitle: appointmentTitle,
            appointmentStartDate: appointmentStartDate,
            appointmentEndDate: appointmentEndDate,
            showFollowUpDetails: showFollowUpDetails,
            showAppointmentDetails: showAppointmentDetails,
            showContactBlock: showContactBlock,
            showNotesBlock: showNotesBlock
        )

        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    private func applyAutosavedDraftIfNeeded(force: Bool = false) {
        let key = locationCardDraftStorageKey
        if !force, didApplyDraftKey == key { return }
        didApplyDraftKey = key

        guard let encoded = UserDefaults.standard.data(forKey: key),
              let payload = try? JSONDecoder().decode(LocationCardDraftPayload.self, from: encoded) else {
            return
        }

        customHeaderLabel = payload.customHeaderLabel
        firstName = payload.firstName
        lastName = payload.lastName
        phoneText = payload.phoneText
        emailText = payload.emailText
        notesText = payload.notesText
        followUpText = payload.followUpText
        if let raw = payload.followUpType, let ft = FollowUpType(rawValue: raw) {
            followUpType = ft
        } else {
            followUpType = .call
        }
        followUpNotes = payload.followUpNotes ?? ""
        followUpDate = payload.followUpDate
        appointmentTitle = payload.appointmentTitle
        appointmentStartDate = payload.appointmentStartDate
        appointmentEndDate = payload.appointmentStartDate.addingTimeInterval(3600)
        showFollowUpDetails = payload.showFollowUpDetails
        showAppointmentDetails = payload.showAppointmentDetails
        showContactBlock = payload.showContactBlock
        showNotesBlock = payload.showNotesBlock
    }

    private func clearAutosavedDraftForCurrentContext() {
        UserDefaults.standard.removeObject(forKey: locationCardDraftStorageKey)
    }

    private var extractedPreviewChipModels: [LocationCardExtractedChip] {
        var chips: [LocationCardExtractedChip] = []

        if showExtractedContactChip, let contactValue = extractedContactSummary {
            chips.append(
                LocationCardExtractedChip(
                    id: "contact",
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Contact",
                    value: contactValue,
                    tint: .red
                )
            )
        }

        if showExtractedFollowUpChip, let followUpValue = extractedFollowUpSummary {
            chips.append(
                LocationCardExtractedChip(
                    id: "follow_up",
                    icon: "arrow.uturn.right.circle.fill",
                    title: "Follow up",
                    value: followUpValue,
                    tint: .orange
                )
            )
        }

        if showExtractedAppointmentChip, let appointmentValue = extractedAppointmentSummary {
            chips.append(
                LocationCardExtractedChip(
                    id: "appointment",
                    icon: "calendar.badge.clock",
                    title: "Appointment",
                    value: appointmentValue,
                    tint: .blue
                )
            )
        }

        if showExtractedStatusChip {
            chips.append(
                LocationCardExtractedChip(
                    id: "status",
                    icon: preferredConversationStatus.iconName,
                    title: "Status",
                    value: preferredConversationStatus.displayName,
                    tint: extractedStatusTint(for: preferredConversationStatus)
                )
            )
        }

        return chips
    }

    private var extractedContactSummary: String? {
        let fullName = [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let phone = phoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullName.isEmpty { return fullName }
        if !phone.isEmpty { return phone }
        if !email.isEmpty { return email }
        return nil
    }

    private var extractedFollowUpSummary: String? {
        let details = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedDate = extractedChipDateFormatter.string(from: followUpDate)
        let typeLabel = followUpType.displayName
        if !details.isEmpty { return "\(typeLabel) • \(details) • \(formattedDate)" }
        return "\(typeLabel) • \(formattedDate)"
    }

    private var extractedAppointmentSummary: String? {
        let title = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedStart = extractedChipDateFormatter.string(from: appointmentStartDate)
        if !title.isEmpty { return "\(title) • \(formattedStart)" }
        return formattedStart
    }

    private var extractedChipDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • h:mm a"
        return formatter
    }

    private func extractedStatusTint(for status: AddressStatus) -> Color {
        switch status {
        case .talked, .appointment, .hotLead:
            return .blue
        case .doNotKnock:
            return .green
        case .noAnswer:
            return .orange
        default:
            return .red
        }
    }

    private func actionButtonPillStyle(background: Color) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(background.opacity(1))
    }

    private func actionButtonBackground(
        isActive: Bool,
        activeColor: Color,
        inactiveColor: Color = Color.red
    ) -> Color {
        isActive ? activeColor : inactiveColor
    }

    private func actionButton(icon: String, label: String, isActive: Bool = false, activeColor: Color = .red, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    actionButtonPillStyle(
                        background: actionButtonBackground(
                            isActive: isActive,
                            activeColor: activeColor
                        )
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func isVisitedActionActive(for address: ResolvedAddress?) -> Bool {
        guard let address, let status = addressStatuses[address.id] else { return false }
        return status != .none && status != .untouched
    }

    private func hasContactOrConversation(for address: ResolvedAddress?) -> Bool {
        guard let address else {
            return showContactBlock
        }

        if let status = addressStatuses[address.id], status.mapLayerStatus == "hot" {
            return true
        }

        return showContactBlock
    }

    private func actionButtons(address: ResolvedAddress?) -> some View {
        HStack(spacing: 8) {
            actionButton(
                icon: "door.left.hand.closed",
                label: "Visited",
                isActive: isVisitedActionActive(for: address),
                activeColor: Color(UIColor(hex: "#22c55e")!)
            ) {
                guard let address else { return }
                Task {
                    do {
                        let nextStatus: AddressStatus = isVisitedActionActive(for: address) ? .untouched : .delivered
                        try await logVisitStatus(address, status: nextStatus)
                    } catch {
                        await MainActor.run { contactSaveError = error.localizedDescription }
                    }
                }
            }

            actionButton(
                icon: "person.fill",
                label: "Contact",
                isActive: hasContactOrConversation(for: address),
                activeColor: Color(UIColor(hex: "#3b82f6")!)
            ) {
                toggleContactCard(address: address)
            }

            actionButton(icon: "note.text", label: "Notes") {
                toggleNotesCard(address: address)
            }

            actionButton(icon: "wrench.and.screwdriver.fill", label: "Tools") {
                showToolsSheet = true
            }
        }
        .padding(.top, 8)
    }

    private func universalActionButtons(address: ResolvedAddress) -> some View {
        actionButtons(address: address)
    }

    // MARK: - Name Row (legacy / compatibility)
    
    private var nameRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person")
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .center)
            TextField("Add name", text: $nameText)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.words)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Main Content
    
    private func mainContentView(address: ResolvedAddress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let lead = dataService.buildingData.leadStatus, !lead.isEmpty, leadStatusDisplay(lead).lowercased() != "new" {
                Text(leadStatusDisplay(lead))
                    .font(.system(size: 12))
                    .foregroundColor(cardPlaceholder)
            }
            if showContactBlock {
                contactDetailsFields
            }
            if showNotesBlock && !showContactBlock {
                notesOnlyDetailsFields
            }
            actionButtons(address: address)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear {
            hydrateContactFieldsIfNeeded()
        }
    }

    private var statusBadgeUniversal: some View {
        Text(getStatusText())
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(white: 0.35))
            .cornerRadius(12)
    }
    
    private func voiceActionButton(address: ResolvedAddress?) -> some View {
        Group {
            if voiceRecorder.isRecording {
                Button(action: { stopAndProcessVoiceLog(address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.black)
                        Text(isTranscribing ? "Transcribing…" : "\(Int(voiceRecorder.recordingDuration))s")
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(actionButtonPillStyle(background: .red))
                }
                .buttonStyle(.plain)
                .disabled(isTranscribing)
                .accessibilityLabel("Stop voice note")
            } else {
                Button(action: { startVoiceCapture() }) {
                    Group {
                        if isTranscribing {
                            Text("Transcribing…")
                                .font(.system(size: 12))
                                .foregroundColor(.black)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(actionButtonPillStyle(background: .red))
                }
                .buttonStyle(.plain)
                .disabled(isTranscribing || address == nil)
                .accessibilityLabel(isTranscribing ? "Transcribing" : "Record voice note")
            }
        }
    }

    private func notesVoiceControls(address: ResolvedAddress?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldGroupLabel("Voice note")
            HStack(alignment: .center, spacing: 12) {
                voiceActionButton(address: address)
                    .frame(maxWidth: 132)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Auto-record")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Text("Start recording when Notes opens")
                        .font(.system(size: 11))
                        .foregroundColor(cardPlaceholder)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $notesAutoRecordEnabled)
                    .labelsHidden()
                    .tint(.red)
            }
        }
    }

    private func startVoiceCapture() {
        flyrEventIdForRecording = UUID()
        isInputFocused = false
        dismissKeyboard()
        showContactBlock = false
        showNotesBlock = true
        resetExtractedChipFlags()
        Task {
            let micGranted = await voiceRecorder.requestPermission()
            guard micGranted else {
                voiceNoteError = "Microphone access is required for voice notes."
                return
            }
            let speechGranted = await transcriptionService.requestSpeechPermission()
            if !speechGranted {
                voiceNoteError = "Speech recognition is required to transcribe to a note."
                return
            }
            await MainActor.run {
                _ = voiceRecorder.startRecording()
            }
        }
    }

    private func stopAndProcessVoiceLog(address: ResolvedAddress?) {
        guard let url = voiceRecorder.stopRecording() else {
            flyrEventIdForRecording = nil
            return
        }
        let eventId = flyrEventIdForRecording ?? UUID()
        flyrEventIdForRecording = nil
        isTranscribing = true
        Task {
            do {
                if let address {
                    let result = try await VoiceLogAPI.shared.submitVoiceLog(
                        audioURL: url,
                        flyrEventId: eventId,
                        addressId: address.id,
                        campaignId: campaignId,
                        address: address.displayFull,
                        parseOnly: true
                    )
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        applyStructuredVoiceLog(result, for: address)
                        isTranscribing = false
                    }
                    return
                }

                let text = try await transcriptionService.transcribeWithDevice(audioURL: url)
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    applyFallbackTranscript(text)
                    isTranscribing = false
                }
            } catch {
                do {
                    let fallbackText = try await transcriptionService.transcribeWithDevice(audioURL: url)
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        applyFallbackTranscript(fallbackText)
                        isTranscribing = false
                    }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    await MainActor.run {
                        voiceNoteError = "Transcription failed: \(error.localizedDescription)"
                        isTranscribing = false
                    }
                }
            }
        }
    }

    private func applyStructuredVoiceLog(_ result: VoiceLogResponse, for address: ResolvedAddress) {
        showContactBlock = false
        showNotesBlock = true
        transcribedNoteText = result.transcript
        resetExtractedChipFlags()

        if let ai = result.aiJson {
            let first = ai.contact.firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let last = ai.contact.lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let email = ai.contact.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let phone = ai.contact.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasExtractedContact = ai.contactUpdate == true && (![first, last, email, phone].allSatisfy { $0.isEmpty })

            if hasExtractedContact {
                if !first.isEmpty { firstName = first }
                if !last.isEmpty { lastName = last }
                if !email.isEmpty { emailText = email }
                if !phone.isEmpty { phoneText = phone }
            }
            showExtractedContactChip = hasExtractedContact

            let normalizedNote = ai.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            mergeTranscriptIntoNotes(normalizedNote.isEmpty ? (ai.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.transcript : ai.summary) : normalizedNote)

            var hasExtractedFollowUp = false
            if let followUpAt = parseVoiceLogDate(ai.followUp?.at ?? ai.followUpAt) {
                followUpDate = followUpAt
                showFollowUpDetails = true
                let followUpDetails = ai.followUp?.details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let taskTitle = ai.followUp?.taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let suggestedTask = !followUpDetails.isEmpty
                    ? followUpDetails
                    : (
                        !taskTitle.isEmpty
                            ? taskTitle
                            : ai.nextAction.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                if !suggestedTask.isEmpty, suggestedTask.lowercased() != "none" {
                    followUpText = suggestedTask.capitalized
                }
                hasExtractedFollowUp = true
            }
            showExtractedFollowUpChip = hasExtractedFollowUp

            var hasExtractedAppointment = false
            if let appointment = ai.appointment,
               let startDate = parseVoiceLogDate(appointment.startAt) {
                appointmentTitle = appointment.title.trimmingCharacters(in: .whitespacesAndNewlines)
                appointmentStartDate = startDate
                appointmentEndDate = startDate.addingTimeInterval(3600)
                showAppointmentDetails = true
                hasExtractedAppointment = true
            }
            showExtractedAppointmentChip = hasExtractedAppointment

            suggestedStatusFromVoice = mapVoiceOutcomeToSuggestedStatus(ai.leadStatus ?? ai.outcome)
            showExtractedStatusChip = !(ai.leadStatus ?? ai.outcome).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            shouldPushVoiceToCRM = ai.pushToFUB ?? true
        } else {
            applyFallbackTranscript(result.transcript)
        }
        onStatusUpdated?(address.id, suggestedStatusFromVoice ?? .talked)
    }

    private func applyFallbackTranscript(_ transcript: String) {
        showContactBlock = false
        showNotesBlock = true
        transcribedNoteText = transcript
        mergeTranscriptIntoNotes(transcript)
        shouldPushVoiceToCRM = true
        resetExtractedChipFlags()
    }

    private func resetExtractedChipFlags() {
        showExtractedContactChip = false
        showExtractedFollowUpChip = false
        showExtractedAppointmentChip = false
        showExtractedStatusChip = false
    }

    private func mergeTranscriptIntoNotes(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesText = trimmed
            return
        }
        guard !notesText.contains(trimmed) else { return }
        notesText += "\n\n" + trimmed
    }

    private func parseVoiceLogDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: raw) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return fallback.date(from: raw)
    }

    private func mapVoiceOutcomeToSuggestedStatus(_ rawStatus: String) -> AddressStatus {
        switch rawStatus.lowercased() {
        case "appointment_set", "follow_up", "appointment":
            return .appointment
        case "hot_lead":
            return .hotLead
        case "spoke", "talked":
            return .talked
        case "not_interested", "do_not_knock":
            return .doNotKnock
        case "no_answer":
            return .noAnswer
        default:
            return .talked
        }
    }

    private var preferredConversationStatus: AddressStatus {
        let trimmedAppointmentTitle = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAppointmentTitle.isEmpty {
            return .appointment
        }
        return suggestedStatusFromVoice ?? .talked
    }

    private var shouldSaveConversationStatus: Bool {
        if showContactBlock { return true }
        if showNotesBlock && !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if !transcribedNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return showExtractedContactChip || showExtractedFollowUpChip || showExtractedAppointmentChip || showExtractedStatusChip
    }
    
    private func mapLeadStatusToAddressStatus(_ leadStatus: String) -> AddressStatus {
        switch leadStatus.lowercased() {
        case "not_home": return .noAnswer
        case "interested": return .hotLead
        case "follow_up": return .appointment
        case "not_interested": return .doNotKnock
        default: return .talked
        }
    }
    
    private func mapFieldLeadStatusToAddressStatus(_ status: FieldLeadStatus) -> AddressStatus {
        switch status {
        case .notHome:
            return .noAnswer
        case .interested:
            return .hotLead  // Blue = conversation
        case .noAnswer:
            return .noAnswer
        case .qrScanned:
            return .hotLead  // Blue = conversation
        }
    }
    
    private func leadStatusDisplay(_ lead: String) -> String {
        switch lead.lowercased() {
        case "not_home": return "Not home"
        case "interested": return "Interested"
        case "follow_up": return "Follow up"
        case "not_interested": return "Not interested"
        default: return lead
        }
    }
    
    private var statusBadge: some View {
        Text(getStatusText())
            .font(.flyrCaption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(getStatusColor())
            .foregroundColor(.white)
            .cornerRadius(4)
    }
    
    private func residentsRow(address: ResolvedAddress) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "person.2")
                    .foregroundColor(.blue)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(getResidentsText())
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(dataService.buildingData.residents.count) resident\(dataService.buildingData.residents.count != 1 ? "s" : "")")
                    .font(.flyrCaption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: { addContact(address) }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                    Text("Add resident")
                        .font(.flyrCaption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var addNotesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add notes")
                .font(.flyrCaption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            TextField("Add notes", text: $notesText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding(.vertical, 4)
    }
    
    private func notesSection(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notes")
                .font(.flyrCaption)
                .fontWeight(.medium)
                .foregroundColor(.flyrPrimary)
            Text(notes)
                .font(.flyrCaption)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color.flyrPrimary.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func getResidentsText() -> String {
        let residents = dataService.buildingData.residents
        if residents.isEmpty { return "No residents" }
        if residents.count == 1 { return residents[0].displayName }
        return "\(residents[0].displayName) + \(residents.count - 1) other\(residents.count > 2 ? "s" : "")"
    }
    
    private func getStatusText() -> String {
        if displayScanCount > 0 { return "Scanned" }
        if dataService.buildingData.qrStatus.hasFlyer { return "Target" }
        return "New"
    }
    
    private func getStatusColor() -> Color {
        if displayScanCount > 0 { return .blue }
        if dataService.buildingData.qrStatus.hasFlyer { return .gray.opacity(0.6) }
        return .gray.opacity(0.4)
    }
    
    private func getQRStatusColor() -> Color {
        let hasFlyer = dataService.buildingData.qrStatus.hasFlyer
        if hasFlyer {
            return displayScanCount > 0 ? Color(UIColor(hex: "#8b5cf6")!) : .flyrPrimary
        }
        return .gray
    }
    
    // MARK: - Actions
    
    private func logVisitStatus(_ address: ResolvedAddress, status: AddressStatus) async throws {
        let sessionTargetId = sessionTargetIdForAddress?(address.id)
        let shouldLogSessionCompletion = sessionId != nil &&
            sessionTargetId != nil &&
            status != .none &&
            status != .untouched

        try await VisitsAPI.shared.updateStatus(
            addressId: address.id,
            campaignId: campaignId,
            status: status,
            notes: notesText.isEmpty ? nil : notesText,
            sessionId: shouldLogSessionCompletion ? sessionId : nil,
            sessionTargetId: shouldLogSessionCompletion ? sessionTargetId : nil,
            sessionEventType: shouldLogSessionCompletion ? SessionEventType.recordedVisitEventType(for: status) : nil,
            location: shouldLogSessionCompletion ? SessionManager.shared.currentLocation : nil
        )
        dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
        await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id, preferredAddressId: preferredAddressId ?? address.id)
        await MainActor.run {
            onStatusUpdated?(address.id, status)
        }
    }

    private func toggleContactCard(address: ResolvedAddress?) {
        isInputFocused = false
        guard let address else { return }
        let isActive = hasContactOrConversation(for: address)

        if isActive {
            showContactBlock = false
            showNotesBlock = false
            Task {
                do {
                    try await logVisitStatus(address, status: .untouched)
                } catch {
                    await MainActor.run { contactSaveError = error.localizedDescription }
                }
            }
            return
        }

        showContactBlock = true
        showNotesBlock = false
        onStatusUpdated?(address.id, .talked)
        Task {
            await persistTalkedFromContactTap(for: address)
        }
    }

    /// Persists `talked` immediately so the blue conversation state survives reload (not only after Save).
    @MainActor
    private func persistTalkedFromContactTap(for address: ResolvedAddress) async {
        guard !isPersistingContactTalk else { return }
        let now = Date()
        if lastPersistedContactTalkAddressId == address.id,
           now.timeIntervalSince(lastContactTalkPersistAt) < contactTalkPersistDebounceSeconds {
            return
        }
        isPersistingContactTalk = true
        defer { isPersistingContactTalk = false }

        let sessionTargetId = sessionTargetIdForAddress?(address.id)
        let shouldLogSessionCompletion = sessionId != nil &&
            sessionTargetId != nil
        let existingStatus = addressStatuses[address.id]
        let shouldLogDoorHitFirst: Bool
        switch existingStatus {
        case nil, .some(.none), .some(.untouched):
            shouldLogDoorHitFirst = true
        default:
            shouldLogDoorHitFirst = false
        }

        do {
            if shouldLogDoorHitFirst {
                try await VisitsAPI.shared.updateStatus(
                    addressId: address.id,
                    campaignId: campaignId,
                    status: .delivered,
                    notes: nil,
                    sessionId: shouldLogSessionCompletion ? sessionId : nil,
                    sessionTargetId: shouldLogSessionCompletion ? sessionTargetId : nil,
                    sessionEventType: shouldLogSessionCompletion ? SessionEventType.recordedVisitEventType(for: .delivered) : nil,
                    location: shouldLogSessionCompletion ? SessionManager.shared.currentLocation : nil
                )
                onStatusUpdated?(address.id, .delivered)
            }

            try await VisitsAPI.shared.updateStatus(
                addressId: address.id,
                campaignId: campaignId,
                status: .talked,
                notes: nil,
                sessionId: shouldLogSessionCompletion ? sessionId : nil,
                sessionTargetId: shouldLogSessionCompletion ? sessionTargetId : nil,
                sessionEventType: shouldLogSessionCompletion ? SessionEventType.recordedVisitEventType(for: .talked) : nil,
                location: shouldLogSessionCompletion ? SessionManager.shared.currentLocation : nil
            )
            lastPersistedContactTalkAddressId = address.id
            lastContactTalkPersistAt = Date()
            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
            await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id, preferredAddressId: preferredAddressId ?? address.id)
            onStatusUpdated?(address.id, .talked)
        } catch {
            contactSaveError = error.localizedDescription
        }
    }

    private func toggleNotesCard(address: ResolvedAddress?) {
        let isEnteringNotesMode = !showNotesBlock || showContactBlock
        let shouldAutoRecord = isEnteringNotesMode &&
            notesAutoRecordEnabled &&
            address != nil &&
            !voiceRecorder.isRecording &&
            !isTranscribing
        showNotesBlock = true
        showContactBlock = false
        if shouldAutoRecord {
            isInputFocused = false
        } else {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        guard shouldAutoRecord else { return }
        startVoiceCapture()
    }

    private func deleteHouse(_ address: ResolvedAddress) {
        Task {
            do {
                try await logVisitStatus(address, status: .doNotKnock)
                await MainActor.run { onClose() }
            } catch {
                await MainActor.run {
                    contactSaveError = error.localizedDescription
                }
            }
        }
    }

    private func handleToolsAction(_ action: LocationCardToolsAction) {
        switch action {
        case .addVisit:
            guard let address = editableAddress else { return }
            Task {
                do {
                    try await logVisitStatus(address, status: .delivered)
                } catch {
                    await MainActor.run { contactSaveError = error.localizedDescription }
                }
            }
            return
        case .resetHome:
            guard let address = editableAddress else { return }
            Task {
                do {
                    try await ContactsService.shared.deleteContactsForAddress(addressId: address.id)
                    try await VisitsAPI.shared.clearCampaignAddressCaptureMetadata(
                        addressId: address.id,
                        campaignId: campaignId
                    )
                    try await VisitsAPI.shared.updateStatus(
                        addressId: address.id,
                        campaignId: campaignId,
                        status: .untouched,
                        notes: ""
                    )
                    await MainActor.run {
                        clearLocationCardFormForReset()
                    }
                    dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                    dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
                    await dataService.fetchBuildingData(
                        gersId: gersId,
                        campaignId: campaignId,
                        addressId: address.id,
                        preferredAddressId: preferredAddressId ?? address.id
                    )
                    await MainActor.run {
                        onStatusUpdated?(address.id, .untouched)
                    }
                } catch {
                    await MainActor.run { contactSaveError = error.localizedDescription }
                }
            }
            return
        case .addHouse, .deleteManualShape:
            break
        }

        if let onToolsAction {
            onToolsAction(action)
            return
        }

        switch action {
        case .addHouse:
            toolMessage = "Add House mode is ready. Tap the map to place or move the cylinder, then continue."
        case .addVisit, .resetHome:
            break
        case .deleteManualShape:
            toolMessage = "Delete Manual Shape requires the parent map view to coordinate the refresh."
        }
    }

    private func clearLocationCardFormForReset() {
        clearAutosavedDraftForCurrentContext()
        nameText = ""
        firstName = ""
        lastName = ""
        showSecondContact = false
        secondFirstName = ""
        secondLastName = ""
        secondPhoneText = ""
        secondEmailText = ""
        phoneText = ""
        emailText = ""
        notesText = ""
        manualAddressText = ""
        followUpText = ""
        followUpDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        appointmentTitle = ""
        appointmentStartDate = Date()
        appointmentEndDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        showFollowUpDetails = false
        showAppointmentDetails = false
        showContactBlock = false
        showNotesBlock = false
        didHydrateContactFields = false
        suggestedStatusFromVoice = nil
        showExtractedContactChip = false
        showExtractedFollowUpChip = false
        showExtractedAppointmentChip = false
        showExtractedStatusChip = false
        transcribedNoteText = ""
        isInputFocused = false
    }

    private func hydrateContactFieldsIfNeeded() {
        guard !didHydrateContactFields else { return }
        didHydrateContactFields = true

        if firstName.isEmpty, lastName.isEmpty {
            if let resident = dataService.buildingData.primaryResident {
                let parts = resident.displayName.split(separator: " ", maxSplits: 1)
                firstName = String(parts.first ?? "")
                lastName = parts.count > 1 ? String(parts[1]) : ""
                phoneText = resident.phone ?? phoneText
                emailText = resident.email ?? emailText
            } else if let contact = dataService.buildingData.contactName, !contact.isEmpty {
                let parts = contact.split(separator: " ", maxSplits: 1)
                firstName = String(parts.first ?? "")
                lastName = parts.count > 1 ? String(parts[1]) : ""
            }
        }

        if let secondResident = dataService.buildingData.residents.dropFirst().first,
           secondFirstName.isEmpty,
           secondLastName.isEmpty,
           secondPhoneText.isEmpty,
           secondEmailText.isEmpty {
            let parts = secondResident.displayName.split(separator: " ", maxSplits: 1)
            secondFirstName = String(parts.first ?? "")
            secondLastName = parts.count > 1 ? String(parts[1]) : ""
            secondPhoneText = secondResident.phone ?? secondPhoneText
            secondEmailText = secondResident.email ?? secondEmailText
            showSecondContact = true
        }

        if notesText.isEmpty, let existingNotes = dataService.buildingData.firstNotes, !existingNotes.isEmpty {
            notesText = existingNotes
        }

        if let existingReminder = dataService.buildingData.primaryResident?.reminderDate ?? dataService.buildingData.followUpDate {
            followUpDate = existingReminder
            showFollowUpDetails = true
        }

        appointmentEndDate = appointmentStartDate.addingTimeInterval(3600)

        // Hydration can run after the card appears; re-apply any local draft so user input wins.
        applyAutosavedDraftIfNeeded(force: true)
    }
    
    private func addContact(_ address: ResolvedAddress) {
        showAddResidentSheet = true
        addResidentAddress = address
    }

    /// Save form and close. If we have an address context, persist notes/status then close.
    private func onSaveForm() async {
        guard !isSavingForm else { return }
        isInputFocused = false
        isSavingForm = true
        contactSaveError = nil
        contactSaveSuccess = false
        defer { isSavingForm = false }

        if let address = editableAddress {
            await saveContactDetailsIfNeeded(for: address)
            let status: AddressStatus = shouldSaveConversationStatus
                ? preferredConversationStatus
                : (addressStatuses[address.id] ?? .delivered)
            do {
                try await logVisitStatus(address, status: status)
            } catch {
                contactSaveSuccess = false
                contactSaveError = error.localizedDescription
                return
            }
        }
        if contactSaveError != nil {
            return
        }
        if contactSaveSuccess {
            return
        }
        clearAutosavedDraftForCurrentContext()
        onClose()
    }

    private func saveContactDetailsIfNeeded(for address: ResolvedAddress) async {
        guard showContactBlock || showNotesBlock else { return }
        guard let userId = AuthManager.shared.user?.id else { return }

        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondFirstName = secondFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondLastName = secondLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = emailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondPhone = secondPhoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondEmail = secondEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFollowUp = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAppointmentTitle = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [trimmedFirstName, trimmedLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let secondFullName = [trimmedSecondFirstName, trimmedSecondLastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let fallbackName = dataService.buildingData.primaryResident?.fullName
            ?? dataService.buildingData.contactName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let resolvedName = !fullName.isEmpty ? fullName : fallbackName
        let reminderDate = showFollowUpDetails ? followUpDate : nil
        let appointmentEndNormalized = appointmentStartDate.addingTimeInterval(3600)
        let crmAppointment: LeadSyncAppointment? = trimmedAppointmentTitle.isEmpty
            ? nil
            : LeadSyncAppointment(
                date: appointmentStartDate,
                title: trimmedAppointmentTitle,
                notes: appointmentSummary(
                    title: trimmedAppointmentTitle,
                    start: appointmentStartDate,
                    end: appointmentEndNormalized,
                    address: address.displayFull
                )
            )
        let crmTask: LeadSyncTask? = {
            // If user typed follow-up text, always create a CRM task and use that text as title.
            // When no explicit reminder is set, fall back to the current follow-up picker date.
            guard reminderDate != nil || !trimmedFollowUp.isEmpty else { return nil }
            let taskTitle = trimmedFollowUp.isEmpty ? "Follow up" : trimmedFollowUp
            let prefixedTitle = "\(followUpType.displayName): \(taskTitle)"
            return LeadSyncTask(title: prefixedTitle, dueDate: reminderDate ?? followUpDate)
        }()

        let hasContactChanges =
            !resolvedName.isEmpty ||
            !trimmedPhone.isEmpty ||
            !trimmedEmail.isEmpty ||
            !secondFullName.isEmpty ||
            !trimmedSecondPhone.isEmpty ||
            !trimmedSecondEmail.isEmpty ||
            !trimmedNotes.isEmpty ||
            !trimmedFollowUp.isEmpty ||
            !trimmedAppointmentTitle.isEmpty

        guard hasContactChanges else { return }

        let existingContact = dataService.buildingData.primaryResident
        let baseContact = existingContact ?? Contact(
            fullName: resolvedName.isEmpty ? "New contact" : resolvedName,
            phone: nil,
            email: nil,
            address: address.displayFull,
            campaignId: campaignId,
            gersId: gersId,
            addressId: address.id,
            status: .warm
        )

        let contact = Contact(
            id: baseContact.id,
            fullName: resolvedName.isEmpty ? baseContact.fullName : resolvedName,
            phone: trimmedPhone.isEmpty ? baseContact.phone : trimmedPhone,
            email: trimmedEmail.isEmpty ? baseContact.email : trimmedEmail,
            address: address.displayFull,
            campaignId: campaignId,
            farmId: baseContact.farmId,
            gersId: gersId,
            addressId: address.id,
            tags: baseContact.tags,
            status: baseContact.status == .new ? .warm : baseContact.status,
            lastContacted: Date(),
            notes: trimmedNotes.isEmpty ? baseContact.notes : trimmedNotes,
            reminderDate: reminderDate ?? baseContact.reminderDate,
            createdAt: baseContact.createdAt,
            updatedAt: Date()
        )

        do {
            let shouldPushCRMManually = shouldPushVoiceToCRM && (existingContact != nil || crmAppointment != nil || crmTask != nil)
            let savedContact: Contact
            if existingContact != nil {
                savedContact = try await ContactsService.shared.updateContact(contact, addressId: address.id)
            } else {
                savedContact = try await ContactsService.shared.addContact(
                    contact,
                    userID: userId,
                    workspaceId: WorkspaceContext.shared.workspaceId,
                    addressId: address.id,
                    syncToCRM: !shouldPushCRMManually
                )
            }

            if showFollowUpDetails,
               let followUpNote = followUpSummary(
                details: trimmedFollowUp,
                reminderDate: reminderDate,
                notes: followUpNotes,
                type: followUpType
               ) {
                _ = try? await ContactsService.shared.logActivity(
                    contactID: savedContact.id,
                    type: .note,
                    note: followUpNote
                )
            }

            if showAppointmentDetails,
               let appointmentNote = appointmentSummary(
                title: trimmedAppointmentTitle,
                start: appointmentStartDate,
                end: appointmentEndNormalized,
                address: address.displayFull
               ) {
                _ = try? await ContactsService.shared.logActivity(
                    contactID: savedContact.id,
                    type: .meeting,
                    note: appointmentNote
                )
            }

            if shouldPushCRMManually {
                let leadModel = LeadModel(from: savedContact)
                await LeadSyncManager.shared.syncLeadToCRM(
                    lead: leadModel,
                    userId: userId,
                    appointment: crmAppointment,
                    task: crmTask,
                    trackFieldLeadCRMStatus: true
                )
            }

            if !secondFullName.isEmpty {
                let secondaryExistingContact = dataService.buildingData.residents.dropFirst().first(where: {
                    $0.fullName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(secondFullName) == .orderedSame
                })

                let secondaryContact = Contact(
                    id: secondaryExistingContact?.id ?? UUID(),
                    fullName: secondFullName,
                    phone: trimmedSecondPhone.isEmpty ? secondaryExistingContact?.phone : trimmedSecondPhone,
                    email: trimmedSecondEmail.isEmpty ? secondaryExistingContact?.email : trimmedSecondEmail,
                    address: address.displayFull,
                    campaignId: campaignId,
                    farmId: secondaryExistingContact?.farmId,
                    gersId: gersId,
                    addressId: address.id,
                    tags: secondaryExistingContact?.tags,
                    status: secondaryExistingContact?.status == .new ? .warm : (secondaryExistingContact?.status ?? .warm),
                    lastContacted: Date(),
                    notes: secondaryExistingContact?.notes,
                    reminderDate: secondaryExistingContact?.reminderDate,
                    createdAt: secondaryExistingContact?.createdAt ?? Date(),
                    updatedAt: Date()
                )

                if secondaryExistingContact != nil {
                    _ = try await ContactsService.shared.updateContact(secondaryContact, addressId: address.id)
                } else {
                    _ = try await ContactsService.shared.addContact(
                        secondaryContact,
                        userID: userId,
                        workspaceId: WorkspaceContext.shared.workspaceId,
                        addressId: address.id,
                        syncToCRM: !shouldPushCRMManually
                    )
                }
            }

            dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
            dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
            await dataService.fetchBuildingData(
                gersId: gersId,
                campaignId: campaignId,
                addressId: address.id,
                preferredAddressId: preferredAddressId ?? address.id
            )
            contactSaveSuccess = true
            clearAutosavedDraftForCurrentContext()
        } catch {
            contactSaveError = error.localizedDescription
        }
    }

    private func followUpSummary(details: String, reminderDate: Date?, notes: String, type: FollowUpType) -> String? {
        var components: [String] = []
        components.append("Type: \(type.displayName)")
        if !details.isEmpty {
            components.append("Follow up: \(details)")
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            components.append("Notes: \(trimmedNotes)")
        }
        if let reminderDate {
            components.append("Due: \(reminderDate.formatted(date: .abbreviated, time: .shortened))")
        }
        return components.joined(separator: " | ")
    }

    private func appointmentSummary(title: String, start: Date, end: Date, address: String) -> String? {
        var components: [String] = []
        if !title.isEmpty {
            components.append(title)
        }
        components.append("Start: \(start.formatted(date: .abbreviated, time: .shortened))")
        components.append("End: \(end.formatted(date: .abbreviated, time: .shortened))")
        if !address.isEmpty {
            components.append("Address: \(address)")
        }
        guard !components.isEmpty else { return nil }
        return "Appointment | " + components.joined(separator: " | ")
    }

    private func calendarEventDraft(for kind: CalendarDraftKind) -> CalendarService.EventDraft? {
        let defaultLocation = dataService.buildingData.address?.displayFull
            ?? addressText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? headerLabel
        let contactName = [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let defaultLabel = contactName.isEmpty ? headerLabel : contactName

        switch kind {
        case .followUp:
            let trimmedDetails = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmedDetails.isEmpty ? "Follow up - \(defaultLabel)" : trimmedDetails
            let title = "\(followUpType.displayName): \(base)"
            return CalendarService.EventDraft(
                title: title,
                startDate: followUpDate,
                endDate: followUpDate.addingTimeInterval(30 * 60),
                location: defaultLocation.isEmpty ? nil : defaultLocation,
                notes: trimmedNotesForCalendar
            )
        case .appointment:
            let trimmedTitle = appointmentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { return nil }
            let endDate = appointmentStartDate.addingTimeInterval(3600)
            return CalendarService.EventDraft(
                title: trimmedTitle,
                startDate: appointmentStartDate,
                endDate: endDate,
                location: defaultLocation.isEmpty ? nil : defaultLocation,
                notes: trimmedNotesForCalendar
            )
        }
    }

    private var trimmedNotesForCalendar: String? {
        let trimmed = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func addDraftToAppleCalendar(kind: CalendarDraftKind) async {
        guard let draft = calendarEventDraft(for: kind) else { return }
        do {
            try await calendarService.addEventToAppleCalendar(draft)
            calendarMessage = "Added to Apple Calendar."
        } catch {
            calendarMessage = error.localizedDescription
        }
    }

    private func openDraftInGoogleCalendar(kind: CalendarDraftKind) {
        guard let draft = calendarEventDraft(for: kind),
              let url = calendarService.googleCalendarURL(for: draft) else {
            calendarMessage = "Fill in the event details first."
            return
        }
        UIApplication.shared.open(url)
    }
}

// MARK: - Manual Map Shape Sheets

private struct ManualAddressCreationSheet: View {
    let campaignId: String
    let draft: PendingManualAddressDraft
    let onSaved: (ManualAddressCreateResponse, CLLocationCoordinate2D) -> Void
    let onCancelled: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var addressAuto = UseAddressAutocomplete()
    @State private var effectiveCoordinate: CLLocationCoordinate2D
    @State private var contactFullName = ""
    @State private var contactPhone = ""
    @State private var contactEmail = ""
    @State private var contactNotes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showContactFailureAlert = false
    @State private var contactFailureTitle = "Address saved"
    @State private var contactFailureDetail = ""

    init(
        campaignId: String,
        draft: PendingManualAddressDraft,
        onSaved: @escaping (ManualAddressCreateResponse, CLLocationCoordinate2D) -> Void,
        onCancelled: @escaping () -> Void
    ) {
        self.campaignId = campaignId
        self.draft = draft
        self.onSaved = onSaved
        self.onCancelled = onCancelled
        _effectiveCoordinate = State(initialValue: draft.coordinate)
    }

    private var trimmedAddressQuery: String {
        addressAuto.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let linkedBuildingId = draft.linkedBuildingId {
                    Section("Placement") {
                        Text("Will link to building \(linkedBuildingId)")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Address") {
                    AddressSearchField(
                        auto: addressAuto,
                        onPick: { suggestion in
                            effectiveCoordinate = suggestion.coordinate
                        },
                        onSubmitQuery: { query in
                            Task { await centerOnSubmittedQuery(query) }
                        },
                        placeholder: "Search or confirm address"
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                Section("Contact (optional)") {
                    TextField("Name", text: $contactFullName)
                        .textContentType(.name)
                    TextField("Phone", text: $contactPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $contactEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                    TextField("Notes", text: $contactNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add House")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancelled()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        save()
                    }
                    .disabled(isSaving || trimmedAddressQuery.isEmpty)
                }
            }
            .onAppear {
                addressAuto.query = draft.prefilledAddressText ?? ""
                addressAuto.autocompleteProximity = draft.coordinate
            }
            .alert("Couldn't create address", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                if let errorMessage { Text(errorMessage) }
            }
            .alert(contactFailureTitle, isPresented: $showContactFailureAlert) {
                Button("OK", role: .cancel) {
                    showContactFailureAlert = false
                    dismiss()
                }
            } message: {
                Text(contactFailureDetail)
            }
        }
    }

    private func centerOnSubmittedQuery(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let seed = try await GeoAPI.shared.forwardGeocodeSeed(trimmed)
            await MainActor.run {
                effectiveCoordinate = seed.coordinate
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not locate \"\(trimmed)\""
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedFormatted = trimmedAddressQuery
        guard !trimmedFormatted.isEmpty else { return }

        isSaving = true
        Task {
            do {
                let response = try await BuildingLinkService.shared.createManualAddress(
                    campaignId: campaignId,
                    input: ManualAddressCreateInput(
                        coordinate: effectiveCoordinate,
                        formatted: trimmedFormatted,
                        houseNumber: nil,
                        streetName: nil,
                        locality: nil,
                        region: nil,
                        postalCode: nil,
                        country: nil,
                        buildingId: draft.linkedBuildingId
                    )
                )

                let name = contactFullName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    guard let userId = AuthManager.shared.user?.id else {
                        await MainActor.run {
                            isSaving = false
                            contactFailureTitle = "Contact not saved"
                            contactFailureDetail = "You must be signed in to add a contact."
                            onSaved(response, effectiveCoordinate)
                            showContactFailureAlert = true
                        }
                        return
                    }
                    let campaignUUID = UUID(uuidString: campaignId)
                    let savedFormatted = response.address.formatted?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let addressLine = (savedFormatted.flatMap { $0.isEmpty ? nil : $0 }) ?? trimmedFormatted
                    let trimmedPhone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedEmail = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedNotes = contactNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let gersForContact: String? = {
                        let a = response.address.gersId?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let a, !a.isEmpty { return a }
                        let b = response.address.buildingGersId?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let b, !b.isEmpty { return b }
                        return nil
                    }()
                    let contact = Contact(
                        fullName: name,
                        phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                        email: trimmedEmail.isEmpty ? nil : trimmedEmail,
                        address: addressLine,
                        campaignId: campaignUUID,
                        gersId: gersForContact,
                        addressId: response.address.id,
                        status: .new,
                        notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                    )
                    do {
                        _ = try await ContactsService.shared.addContact(
                            contact,
                            userID: userId,
                            workspaceId: WorkspaceContext.shared.workspaceId,
                            addressId: response.address.id
                        )
                        await MainActor.run {
                            isSaving = false
                            onSaved(response, effectiveCoordinate)
                            dismiss()
                        }
                    } catch {
                        await MainActor.run {
                            isSaving = false
                            contactFailureTitle = "Address saved"
                            contactFailureDetail = "Could not add contact: \(error.localizedDescription)"
                            onSaved(response, effectiveCoordinate)
                            showContactFailureAlert = true
                        }
                    }
                } else {
                    await MainActor.run {
                        isSaving = false
                        onSaved(response, effectiveCoordinate)
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Add Resident Sheet

private struct AddResidentSheetView: View {
    let address: ResolvedAddress
    let campaignId: UUID
    let onSave: () async -> Void
    let onDismiss: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var showSecondContact = false
    @State private var secondFullName = ""
    @State private var secondPhone = ""
    @State private var secondEmail = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $fullName)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                } header: {
                    Text("Resident")
                }

                Section {
                    Button(showSecondContact ? "Remove 2nd Contact" : "Add 2nd Contact") {
                        if showSecondContact {
                            secondFullName = ""
                            secondPhone = ""
                            secondEmail = ""
                        }
                        showSecondContact.toggle()
                    }
                }

                if showSecondContact {
                    Section {
                        TextField("Name", text: $secondFullName)
                            .textContentType(.name)
                        TextField("Phone", text: $secondPhone)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                        TextField("Email", text: $secondEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                    } header: {
                        Text("2nd Contact")
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.flyrCaption)
                    }
                }
            }
            .navigationTitle("Add resident")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveResident()
                    }
                    .disabled(
                        fullName.trimmingCharacters(in: .whitespaces).isEmpty ||
                        (showSecondContact && secondFullName.trimmingCharacters(in: .whitespaces).isEmpty) ||
                        isSaving
                    )
                }
            }
            .disabled(isSaving)
        }
    }
    
    private func saveResident() {
        guard !isSaving else { return }
        let name = fullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let userId = AuthManager.shared.user?.id else {
            errorMessage = "You must be signed in to add a resident."
            return
        }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let contacts = try makeContacts()
                for contact in contacts {
                    _ = try await ContactsService.shared.addContact(
                        contact,
                        userID: userId,
                        workspaceId: WorkspaceContext.shared.workspaceId,
                        addressId: address.id
                    )
                }
                await onSave()
                await MainActor.run {
                    onDismiss()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func makeContacts() throws -> [Contact] {
        var contacts: [Contact] = [
            Contact(
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : phone.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines),
                address: address.displayFull,
                campaignId: campaignId,
                status: .new
            )
        ]

        if showSecondContact {
            let secondName = secondFullName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !secondName.isEmpty else {
                throw NSError(domain: "AddResidentSheetView", code: -1, userInfo: [NSLocalizedDescriptionKey: "2nd contact name is required."])
            }
            let normalizedSecondPhone = secondPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSecondEmail = secondEmail.trimmingCharacters(in: .whitespacesAndNewlines)
            contacts.append(
                Contact(
                    fullName: secondName,
                    phone: normalizedSecondPhone.isEmpty ? nil : normalizedSecondPhone,
                    email: normalizedSecondEmail.isEmpty ? nil : normalizedSecondEmail,
                    address: address.displayFull,
                    campaignId: campaignId,
                    status: .new
                )
            )
        }

        return contacts
    }
}

// MARK: - Lead Task Sheet (MVP: placeholder; can add FUB task create later)

private struct LeadTaskSheetView: View {
    let addressId: UUID?
    let campaignId: UUID
    let addressText: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !addressText.isEmpty {
                    Text(addressText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Add a task for this address. FUB task creation can be wired here.")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Lead Appointment Sheet (MVP: placeholder; can add FUB appointment create later)

private struct LeadAppointmentSheetView: View {
    let addressId: UUID?
    let campaignId: UUID
    let addressText: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if !addressText.isEmpty {
                    Text(addressText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text("Add an appointment for this address. FUB appointment creation can be wired here.")
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Appointment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Voice Log Preview Sheet (summary, outcome, follow-up, appointment; Done / Cancel)

private struct VoiceLogPreviewSheet: View {
    let result: VoiceLogResponse
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ai = result.aiJson {
                        Text(ai.summary)
                            .font(.body)
                        if !ai.outcome.isEmpty {
                            Text(ai.outcome)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(8)
                        }
                        if let followUp = ai.followUpAt, !followUp.isEmpty {
                            Text("Follow up: \(followUp)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if let appt = ai.appointment {
                            Text("Appointment: \(appt.title) \(appt.startAt)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        if ai.isLowConfidence {
                            Text("Low confidence – review before relying on task/appointment.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    if result.alreadyPushedToFUB {
                        Text("Sent to Follow Up Boss")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                }
                .padding()
            }
            .navigationTitle("Voice Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Transcribed Note Sheet (voice → on-device transcript; edit and optionally save to address)

private struct TranscribedNoteSheet: View {
    @Binding var text: String
    let addressId: UUID?
    let campaignId: UUID
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .navigationTitle("Voice note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onDismiss()
                            dismiss()
                        }
                    }
                    if addressId != nil {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveToAddress()
                            }
                            .disabled(text.isEmpty || isSaving)
                        }
                    }
                }
        }
    }

    private func saveToAddress() {
        guard let addrId = addressId, !text.isEmpty else { return }
        isSaving = true
        Task {
            do {
                try await VoiceNoteAPI.saveVoiceNoteToCampaign(transcript: text, addressId: addrId, campaignId: campaignId)
                await MainActor.run {
                    isSaving = false
                    onDismiss()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
            }
        }
    }
}

struct BuildingStatusBadge: View {
    let status: String
    let scansTotal: Int
    
    var color: Color {
        if scansTotal > 0 {
            return Color(UIColor(hex: "#8b5cf6")!)
        }
        switch status {
        case "hot": return Color(UIColor(hex: "#3b82f6")!)
        case "visited": return Color(UIColor(hex: "#22c55e")!)
        default: return Color(UIColor(hex: "#ef4444")!)
        }
    }
    
    var label: String {
        if scansTotal > 0 { return "QR Scanned" }
        switch status {
        case "hot": return "Conversation"
        case "visited": return "Touched"
        default: return "Untouched"
        }
    }
    
    var body: some View {
        Text(label)
            .font(.flyrCaption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(4)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.flyrCaption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.flyrCaption)
                .fontWeight(.medium)
        }
    }
}

@MainActor
private final class CalendarService: ObservableObject {
    struct EventDraft {
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let notes: String?
    }

    private let eventStore = EKEventStore()

    func addEventToAppleCalendar(_ draft: EventDraft) async throws {
        let granted = try await requestEventAccess()
        guard granted else {
            throw NSError(
                domain: "CalendarService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Calendar access was not granted."]
            )
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = max(draft.endDate, draft.startDate.addingTimeInterval(30 * 60))
        event.location = draft.location
        event.notes = draft.notes
        event.calendar = eventStore.defaultCalendarForNewEvents

        try eventStore.save(event, span: .thisEvent)
    }

    func googleCalendarURL(for draft: EventDraft) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: draft.title),
            URLQueryItem(name: "dates", value: "\(googleDateString(draft.startDate))/\(googleDateString(max(draft.endDate, draft.startDate.addingTimeInterval(30 * 60))))"),
            URLQueryItem(name: "location", value: draft.location),
            URLQueryItem(name: "details", value: draft.notes)
        ]
        return components?.url
    }

    private func requestEventAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            return try await eventStore.requestWriteOnlyAccessToEvents()
        }

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func googleDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}

// MARK: - Campaign map loading (FLYR Lottie + blur; matches SignIn / campaign creation)

private struct CampaignMapLoadingLottieView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        let lottie = LottieAnimationView(name: name, bundle: .main)
        lottie.loopMode = .loop
        lottie.contentMode = .scaleAspectFit
        lottie.backgroundBehavior = .pauseAndRestore
        lottie.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lottie)
        NSLayoutConstraint.activate([
            lottie.topAnchor.constraint(equalTo: container.topAnchor),
            lottie.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lottie.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lottie.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        lottie.play()
        context.coordinator.lottieView = lottie
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.lottieView?.contentMode = .scaleAspectFit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var lottieView: LottieAnimationView?
    }
}

private struct PreSessionGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var goalAmount: Int
    let maxGoal: Int
    @State private var draftGoal: Double

    init(goalAmount: Binding<Int>, maxGoal: Int) {
        self._goalAmount = goalAmount
        self.maxGoal = maxGoal
        _draftGoal = State(initialValue: Double(goalAmount.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Up to \(maxGoal) homes in this campaign.")
                    .font(.flyrSubheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                VStack(spacing: 12) {
                    Text("\(Int(draftGoal))")
                        .font(.system(size: 34, weight: .bold))
                        .frame(maxWidth: .infinity, alignment: .center)

                    Slider(
                        value: $draftGoal,
                        in: 1...Double(maxGoal),
                        step: 1
                    )
                }

                Stepper(value: Binding(
                    get: { Int(draftGoal) },
                    set: { draftGoal = Double(min(max(1, $0), maxGoal)) }
                ), in: 1...maxGoal) {
                    Text("Goal: \(Int(draftGoal)) homes")
                        .font(.flyrBody)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        goalAmount = min(max(1, Int(draftGoal)), maxGoal)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CampaignMapView(campaignId: "preview-campaign-id")
}
