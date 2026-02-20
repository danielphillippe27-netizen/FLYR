import SwiftUI
import UIKit
import MapboxMaps
import Combine
import CoreLocation

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
    var onAddressCompleted: (UUID) -> Void

    var body: some View {
        if let addr = flyerModeManager.currentAddress {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text(addr.segmentLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
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
                flyerModeManager.onAddressCompleted = onAddressCompleted
            }
        }
    }
}

/// Campaign Map View with 3D buildings, roads, and addresses
/// Mirrors FLYR-PRO's CampaignDetailMapView.tsx functionality
struct CampaignMapView: View {
    let campaignId: String
    @Environment(\.colorScheme) private var colorScheme

    /// Default center when no campaign data yet (Toronto)
    private static let defaultCenter = CLLocationCoordinate2D(latitude: 43.65, longitude: -79.38)

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

    // Status filters
    @State private var showQrScanned = true
    @State private var showConversations = true
    @State private var showTouched = true
    @State private var showUntouched = true
    // Display mode: Buildings only or Pins only (never both)
    @State private var displayMode: DisplayMode = .buildings
    @State private var showEndSessionConfirmation = false
    @State private var keyboardHeight: CGFloat = 0
    /// Per-address visit statuses (populated from VisitsAPI and updated live via onStatusUpdated)
    @State private var addressStatuses: [UUID: AddressStatus] = [:]
    /// Maps building gersId → set of address UUIDs (populated when a multi-address card is opened)
    @State private var buildingAddressMap: [String: Set<UUID>] = [:]
    @StateObject private var flyerModeManager = FlyerModeManager()

    var body: some View {
        campaignMapContent
    }

    private var campaignMapContent: some View {
        campaignMapWithAlertsAndObservers
            .sheet(isPresented: $showTargetsSheet) { nextTargetsSheetContent }
            .sheet(isPresented: $showLeadCaptureSheet, onDismiss: { selectedBuilding = nil }) {
                leadCaptureSheetContent
            }
    }

    private var campaignMapWithObservers: some View {
        campaignMapGeometry
            .alert("Are you sure?", isPresented: $showEndSessionConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("End", role: .destructive) { SessionManager.shared.stop() }
            } message: {
                Text("This will end your session. You’ll see your summary and can share the transparent card.")
            }
            .onAppear {
                loadCampaignData()
                setupRealTimeSubscription()
            }
            .onChange(of: campaignId) { _, _ in hasFlownToCampaign = false }
            .onDisappear { Task { await statsSubscriber?.unsubscribe() } }
            .onChange(of: featuresService.buildings?.features.count ?? 0) { _, _ in updateMapData() }
            .onChange(of: featuresService.addresses?.features.count ?? 0) { _, _ in updateMapData() }
            .onChange(of: sessionManager.pathCoordinates.count) { _, _ in updateSessionPathOnMap() }
            .onChange(of: sessionManager.sessionId) { _, new in
                updateSessionPathOnMap()
                if new == nil {
                    flyerModeManager.reset()
                } else {
                    flyerModeManager.startObservingLocation()
                }
            }
            .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
                guard sessionManager.sessionId != nil else { return }
                updateSessionPathOnMap()
            }
    }

    private var campaignMapWithAlertsAndObservers: some View {
        campaignMapWithObservers
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
                    try? await sessionManager.completeBuilding(buildingId)
                    updateBuildingColorAfterComplete(gersId: buildingId)
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
            let gersIdString = building.gersId ?? building.id
            LeadCaptureSheet(
                addressDisplay: building.addressText ?? "Address",
                campaignId: campId,
                sessionId: sessionManager.sessionId,
                gersIdString: gersIdString,
                onSave: { lead in
                    _ = try? await FieldLeadsService.shared.addLead(lead)
                    // Count every lead save as a conversation (any status = had contact at door)
                    await MainActor.run { sessionManager.conversationsHad += 1 }
                    if let addressId = selectedAddress?.addressId {
                        let addressStatus = mapFieldLeadStatusToAddressStatus(lead.status)
                        try? await VisitsAPI.shared.updateStatus(
                            addressId: addressId,
                            campaignId: campId,
                            status: addressStatus,
                            notes: lead.notes
                        )
                        await applyLoadedStatusesToMap()
                    }
                    try? await sessionManager.completeBuilding(gersIdString)
                    await MainActor.run { updateBuildingColorAfterComplete(gersId: gersIdString) }
                    HapticManager.success()
                },
                onJustMark: {
                    HapticManager.soft()
                    try? await sessionManager.completeBuilding(gersIdString)
                    await MainActor.run { updateBuildingColorAfterComplete(gersId: gersIdString) }
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
        ZStack {
            mapLayer(geometry: geometry)
            sessionStatsOverlay
            overlayUI
            flyerModeOverlay
            locationCardOverlay
            loadingOverlay
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

    // MARK: - Body subviews (split for type-checker)

    @ViewBuilder
    private func mapLayer(geometry: GeometryProxy) -> some View {
        let size = geometry.size
        let hasValidSize = size.width > 0 && size.height > 0
        if hasValidSize {
            CampaignMapboxMapViewRepresentable(
                preferredSize: size,
                useDarkStyle: colorScheme == .dark,
                sessionLocation: sessionManager.sessionId != nil ? sessionManager.currentLocation : nil,
                showSessionPuck: sessionManager.sessionId != nil,
                onMapReady: { map in
                    self.mapView = map
                    setupMap(map)
                },
                onTap: { point in
                    handleTap(at: point)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var flyerModeOverlay: some View {
        FlyerModeOverlay(
            flyerModeManager: flyerModeManager,
            onAddressCompleted: flyerAddressCompleted
        )
        .id(layerManager != nil)
    }

    private func flyerAddressCompleted(addressId: UUID) {
        layerManager?.updateAddressState(addressId: addressId.uuidString, status: "visited", scansTotal: 0)
        addressStatuses[addressId] = .delivered
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
    private var overlayUI: some View {
        VStack {
            if sessionManager.sessionId != nil {
                // Session: building/circle toggle, Progress pill, End button top right
                HStack(alignment: .top, spacing: 12) {
                    BuildingCircleToggle(mode: $displayMode) { newMode in
                        updateLayerVisibility(for: newMode)
                    }
                    Spacer(minLength: 8)
                    SessionProgressPill(sessionManager: sessionManager, isExpanded: $statsExpanded)
                    Button {
                        HapticManager.light()
                        showEndSessionConfirmation = true
                    } label: {
                        Text("End")
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
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .safeAreaPadding(.top, 48)
                .safeAreaPadding(.leading, 4)
                .safeAreaPadding(.trailing, 4)
            } else {
                // Pre-session: building/circle toggle brought down, Start session at bottom
                HStack(alignment: .top, spacing: 0) {
                    BuildingCircleToggle(mode: $displayMode) { newMode in
                        updateLayerVisibility(for: newMode)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
                .safeAreaPadding(.top, 48)
                .safeAreaPadding(.leading, 4)
            }
            
            Spacer()
            
            if sessionManager.sessionId == nil,
               let features = featuresService.buildings?.features,
               !features.isEmpty,
               let campId = UUID(uuidString: campaignId) {
                GeometryReader { geo in
                    HStack {
                        Spacer()
                        Button {
                            HapticManager.medium()
                            startBuildingSession(campaignId: campId, features: features)
                        } label: {
                            Label("Start session", systemImage: "play.circle.fill")
                                .font(.flyrSubheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .frame(width: geo.size.width * 0.5)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .padding(.bottom, 64)
            }
        }
    }
    
    /// Update layer visibility based on display mode (cubes only or pins only)
    private func updateLayerVisibility(for mode: DisplayMode) {
        guard let manager = layerManager else { return }
        guard let map = mapView?.mapboxMap else { return }
        
        let hasBuildingsLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.buildingsLayerId })
        let hasAddressesLayer = map.allLayerIdentifiers.contains(where: { $0.id == MapLayerManager.addressesLayerId })
        if !hasBuildingsLayer || !hasAddressesLayer {
            print("🔍 [CampaignMap] Layers not in style yet (buildings=\(hasBuildingsLayer) addresses=\(hasAddressesLayer)); visibility will apply after style load")
        }
        
        switch mode {
        case .buildings:
            manager.includeBuildingsLayer = true
            manager.includeAddressesLayer = false
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
        case .addresses:
            manager.includeBuildingsLayer = false
            manager.includeAddressesLayer = true
            // Update addresses source first so circles have data when layer becomes visible
            let addressCount = featuresService.addresses?.features.count ?? 0
            let buildingCount = featuresService.buildings?.features.count ?? 0
            let hasAddressPoints = addressCount > 0
            print("🔍 [CampaignMap] addresses=\(addressCount) buildings=\(buildingCount) hasAddressPoints=\(hasAddressPoints)")
            if hasAddressPoints, let addressesData = featuresService.addressesAsGeoJSONData() {
                manager.updateAddresses(addressesData)
            } else if let buildingsData = featuresService.buildingsAsGeoJSONData() {
                manager.updateAddressesFromBuildingCentroids(buildingGeoJSONData: buildingsData)
            } else {
                print("⚠️ [CampaignMap] No address or building data for circle extrusions")
            }
            if hasBuildingsLayer {
                try? map.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            }
            if hasAddressesLayer {
                try? map.updateLayer(withId: MapLayerManager.addressesLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            }
        }
        
        print("🗺️ [CampaignMap] Display mode changed to: \(mode)")
    }

    @ViewBuilder
    private var locationCardOverlay: some View {
        if showLocationCard,
           let building = selectedBuilding,
           let campId = UUID(uuidString: campaignId) {
            let gersIdString = building.gersId ?? building.id
            let resolvedAddrId = selectedAddress?.addressId ?? building.addressId.flatMap { UUID(uuidString: $0) }
            let resolvedAddrText = selectedAddress?.formatted ?? building.addressText
            VStack {
                Spacer()
                LocationCardView(
                    gersId: gersIdString,
                    campaignId: campId,
                    addressId: resolvedAddrId,
                    addressText: resolvedAddrText,
                    preferredAddressId: selectedAddressIdForCard,
                    addressStatuses: addressStatuses,
                    onSelectAddress: { selectedAddressIdForCard = $0 },
                    onAddressesResolved: { ids in
                        buildingAddressMap[gersIdString.lowercased()] = Set(ids)
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
                        if let map = mapView {
                            MapController.shared.applyStatusFeatureState(statuses: [addressId.uuidString: status], mapView: map)
                        }
                        // Update local status cache
                        addressStatuses[addressId] = status
                        let scansTotal = featuresService.buildings?.features.first(where: { $0.properties.gersId == gersIdString })?.properties.scansTotal ?? 0
                        let layerStatus = status.mapLayerStatus
                        layerManager?.updateAddressState(addressId: addressId.uuidString, status: layerStatus, scansTotal: scansTotal)
                        // Building: green only when ALL addresses are visited
                        let addrIds = addressIdsForBuilding(gersId: gersIdString)
                        let buildingStatus = addrIds.isEmpty ? layerStatus : computeBuildingLayerStatus(gersId: gersIdString, addressIds: addrIds)
                        layerManager?.updateBuildingState(gersId: gersIdString, status: buildingStatus, scansTotal: scansTotal)
                    }
                )
                .id("building-\(gersIdString)-\(resolvedAddrId?.uuidString ?? "")")
                .padding()
            }
            .padding(.bottom, keyboardHeight)
            .transition(.move(edge: .bottom))
        } else if showLocationCard,
                  let address = selectedAddress,
                  let campId = UUID(uuidString: campaignId) {
            let gersIdString = address.buildingGersId ?? address.gersId ?? ""
            VStack {
                Spacer()
                LocationCardView(
                    gersId: gersIdString,
                    campaignId: campId,
                    addressId: address.addressId,
                    addressText: address.formatted,
                    preferredAddressId: selectedAddressIdForCard,
                    addressStatuses: addressStatuses,
                    onSelectAddress: { selectedAddressIdForCard = $0 },
                    onAddressesResolved: { ids in
                        if !gersIdString.isEmpty {
                            buildingAddressMap[gersIdString.lowercased()] = Set(ids)
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
                        if let map = mapView {
                            MapController.shared.applyStatusFeatureState(statuses: [addressId.uuidString: status], mapView: map)
                        }
                        // Update local status cache
                        addressStatuses[addressId] = status
                        let scansTotal = featuresService.buildings?.features.first(where: { $0.properties.gersId == gersIdString })?.properties.scansTotal ?? 0
                        let layerStatus = status.mapLayerStatus
                        layerManager?.updateAddressState(addressId: addressId.uuidString, status: layerStatus, scansTotal: scansTotal)
                        // Building: green only when ALL addresses are visited
                        let addrIds = addressIdsForBuilding(gersId: gersIdString)
                        let buildingStatus = addrIds.isEmpty ? layerStatus : computeBuildingLayerStatus(gersId: gersIdString, addressIds: addrIds)
                        layerManager?.updateBuildingState(gersId: gersIdString, status: buildingStatus, scansTotal: scansTotal)
                    }
                )
                .id("address-\(address.addressId.uuidString)")
                .padding()
            }
            .padding(.bottom, keyboardHeight)
            .transition(.move(edge: .bottom))
        }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if featuresService.isLoading {
            ProgressView()
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
        }
    }

    // MARK: - Setup
    
    private func setupMap(_ map: MapView) {
        let manager = MapLayerManager(mapView: map)
        manager.includeBuildingsLayer = true
        manager.includeAddressesLayer = true  // Add both layers; visibility controlled by toggle (buildings vs circle extrusions)
        self.layerManager = manager

        // Hide map zoom/scale bar/compass ornaments
        map.ornaments.options.scaleBar.visibility = .hidden
        map.ornaments.options.compass.visibility = .hidden

        // Wait for style to load
        map.mapboxMap.onStyleLoaded.observe { _ in
            Self.removeStyleBuildingLayers(map: map)
            manager.setupLayers()
            addSessionPathLayersIfNeeded(map: map)

            // Set initial camera so map shows (default center; will fly to campaign when data loads)
            map.camera.fly(to: CameraOptions(
                center: Self.defaultCenter,
                padding: nil,
                zoom: 15,
                bearing: nil,
                pitch: 60
            ), duration: 0.5)

            // Load data if we have it
            updateMapData()
            flyToCampaignCenterIfNeeded(map: map)
            updateSessionPathOnMap()
            // Apply current display mode so buildings vs circle extrusions match toggle
            updateLayerVisibility(for: displayMode)
        }.store(in: &cancellables)
    }
    
    private func loadCampaignData() {
        Task {
            await featuresService.fetchAllCampaignFeatures(campaignId: campaignId)
        }
    }
    
    private func updateMapData() {
        guard let manager = layerManager else { return }
        
        manager.updateBuildings(featuresService.buildingsAsGeoJSONData())
        
        let hasAddressPoints = (featuresService.addresses?.features.isEmpty ?? true) == false
        if hasAddressPoints, let addressesData = featuresService.addressesAsGeoJSONData() {
            manager.updateAddresses(addressesData)
        } else if let buildingsData = featuresService.buildingsAsGeoJSONData() {
            manager.updateAddressesFromBuildingCentroids(buildingGeoJSONData: buildingsData)
        }
        
        if let roadsData = featuresService.roadsAsGeoJSONData() {
            manager.updateRoads(roadsData)
        }
        
        // Apply current display mode visibility
        updateLayerVisibility(for: displayMode)
        
        if let map = mapView {
            flyToCampaignCenterIfNeeded(map: map)
        }
        
        // Re-apply loaded campaign statuses after source update (Mapbox clears feature state when GeoJSON source is updated)
        Task { await applyLoadedStatusesToMap() }

        if let campaignUUID = UUID(uuidString: campaignId) {
            Task { await flyerModeManager.load(campaignId: campaignUUID, featuresService: featuresService) }
        }
    }
    
    /// Fetch campaign address statuses and apply them to the map so buildings/addresses show correct colors (delivered = green, etc.).
    /// Call after every source update since Mapbox clears feature state when GeoJSON is replaced.
    private func applyLoadedStatusesToMap() async {
        guard let manager = layerManager,
              let campaignUUID = UUID(uuidString: campaignId) else { return }
        do {
            let statuses = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignUUID)
            guard !statuses.isEmpty else { return }
            await MainActor.run {
                // Populate local status cache
                for (addressId, row) in statuses {
                    addressStatuses[addressId] = row.status
                    manager.updateAddressState(addressId: addressId.uuidString, status: row.status.mapLayerStatus, scansTotal: 0)
                }
                if let buildings = featuresService.buildings?.features {
                    for building in buildings {
                        guard let gersId = building.properties.gersId ?? building.id else { continue }
                        let scansTotal = building.properties.scansTotal

                        // Single-address building: use that address's status directly
                        if let addrIdStr = building.properties.addressId,
                           let addrId = UUID(uuidString: addrIdStr),
                           let row = statuses[addrId] {
                            manager.updateBuildingState(gersId: gersId, status: row.status.mapLayerStatus, scansTotal: scansTotal)
                            continue
                        }

                        // Multi-address building: only go green if ALL addresses are visited
                        let addrIds = addressIdsForBuilding(gersId: gersId)
                        if !addrIds.isEmpty {
                            let buildingStatus = computeBuildingLayerStatus(gersId: gersId, addressIds: addrIds)
                            manager.updateBuildingState(gersId: gersId, status: buildingStatus, scansTotal: scansTotal)
                        }
                    }
                }
                updateFilters()
            }
            print("📊 [CampaignMap] Applied \(statuses.count) loaded statuses to map")
        } catch {
            print("⚠️ [CampaignMap] Failed to load/apply statuses: \(error)")
        }
    }

    /// Returns address UUIDs for a building by scanning loaded address features for matching building_gers_id.
    private func addressIdsForBuilding(gersId: String) -> [UUID] {
        let gersLower = gersId.lowercased()
        // First check the card-populated map (most accurate for multi-address buildings)
        if let cached = buildingAddressMap[gersLower], !cached.isEmpty {
            return Array(cached)
        }
        // Fall back to address features that have building_gers_id set
        guard let addresses = featuresService.addresses?.features else { return [] }
        return addresses.compactMap { feature -> UUID? in
            let buildingGers = (feature.properties.buildingGersId ?? "").lowercased()
            guard buildingGers == gersLower,
                  let idStr = feature.properties.id ?? feature.id,
                  let uuid = UUID(uuidString: idStr) else { return nil }
            return uuid
        }
    }

    /// Compute the map layer status for a building based on ALL its address statuses.
    /// Green only when every address has been visited (delivered / doNotKnock / futureSeller).
    private func computeBuildingLayerStatus(gersId: String, addressIds: [UUID]) -> String {
        guard !addressIds.isEmpty else { return "not_visited" }
        let allVisited = addressIds.allSatisfy {
            (addressStatuses[$0]?.mapLayerStatus ?? "not_visited") == "visited"
        }
        if allVisited { return "visited" }
        let anyHot = addressIds.contains {
            (addressStatuses[$0]?.mapLayerStatus ?? "not_visited") == "hot"
        }
        return anyHot ? "hot" : "not_visited"
    }

    private func mapFieldLeadStatusToAddressStatus(_ status: FieldLeadStatus) -> AddressStatus {
        switch status {
        case .notHome: return .noAnswer
        case .interested: return .hotLead
        case .noAnswer: return .noAnswer
        case .qrScanned: return .hotLead
        }
    }

    private static let sessionLineSourceId = "session-line-source"
    private static let sessionLineLayerId = "session-line-layer"
    private static let sessionPuckSourceId = "session-puck-source"
    private static let sessionPuckOuterLayerId = "session-puck-outer"
    private static let sessionPuckInnerLayerId = "session-puck-inner"

    /// Add session path source and line layer (breadcrumb trail) + session puck layers.
    private func addSessionPathLayersIfNeeded(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        do {
            var source = GeoJSONSource(id: Self.sessionLineSourceId)
            source.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(source)
            var lineLayer = LineLayer(id: Self.sessionLineLayerId, source: Self.sessionLineSourceId)
            lineLayer.lineColor = .constant(StyleColor(.red))
            lineLayer.lineWidth = .constant(5.0)
            lineLayer.lineOpacity = .constant(0.8)
            lineLayer.lineJoin = .constant(.round)
            lineLayer.lineCap = .constant(.round)
            try mapboxMap.addLayer(lineLayer)

            var puckSource = GeoJSONSource(id: Self.sessionPuckSourceId)
            puckSource.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(puckSource)
            var puckOuter = CircleLayer(id: Self.sessionPuckOuterLayerId, source: Self.sessionPuckSourceId)
            puckOuter.circleRadius = .constant(14)
            puckOuter.circleColor = .constant(StyleColor(UIColor.red.withAlphaComponent(0.45)))
            puckOuter.circleOpacity = .constant(1.0)
            puckOuter.circleStrokeWidth = .constant(0)
            try mapboxMap.addLayer(puckOuter)
            var puckInner = CircleLayer(id: Self.sessionPuckInnerLayerId, source: Self.sessionPuckSourceId)
            puckInner.circleRadius = .constant(6)
            puckInner.circleColor = .constant(StyleColor(.white))
            puckInner.circleOpacity = .constant(1.0)
            puckInner.circleStrokeWidth = .constant(0)
            try mapboxMap.addLayer(puckInner)
        } catch {
            print("⚠️ [CampaignMap] Failed to add session path/puck layers: \(error)")
        }
    }

    /// Update the session path line from current pathCoordinates (Strava-style breadcrumb during building session).
    private func updateSessionPathOnMap() {
        guard let map = mapView?.mapboxMap else { return }
        let coords = sessionManager.pathCoordinates
        if coords.count >= 2 {
            let lineCoords = coords.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            let lineString = LineString(lineCoords)
            let feature = Feature(geometry: .lineString(lineString))
            try? map.updateGeoJSONSource(withId: Self.sessionLineSourceId, geoJSON: .feature(feature))
        } else {
            try? map.updateGeoJSONSource(withId: Self.sessionLineSourceId, geoJSON: .featureCollection(FeatureCollection(features: [])))
        }
        updateSessionPuckOnMap()
    }

    /// Show session puck at current location when in a session; hide when not.
    private func updateSessionPuckOnMap() {
        guard let map = mapView?.mapboxMap else { return }
        guard map.sourceExists(withId: Self.sessionPuckSourceId) else { return }
        let show = sessionManager.sessionId != nil
        let location = sessionManager.currentLocation
        if show, let loc = location {
            let feature = Feature(geometry: .point(Point(loc.coordinate)))
            try? map.updateGeoJSONSource(withId: Self.sessionPuckSourceId, geoJSON: .feature(feature))
        } else {
            try? map.updateGeoJSONSource(withId: Self.sessionPuckSourceId, geoJSON: .featureCollection(FeatureCollection(features: [])))
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
        guard !hasFlownToCampaign, let center = featuresService.campaignCenterCoordinate() else { return }
        hasFlownToCampaign = true
        map.camera.fly(to: CameraOptions(
            center: center,
            padding: nil,
            zoom: 15,
            bearing: nil,
            pitch: 60
        ), duration: 0.8)
    }
    
    private func updateFilters() {
        guard let manager = layerManager else { return }
        manager.showQrScanned = showQrScanned
        manager.showConversations = showConversations
        manager.showTouched = showTouched
        manager.showUntouched = showUntouched
        manager.updateStatusFilter()
    }
    
    private func handleTap(at point: CGPoint) {
        guard let manager = layerManager else { return }

        manager.getBuildingOrAddressAt(point: point) { result in
            guard let result = result else { return }
            switch result {
            case .building(let building):
                selectedBuilding = building
                if let matchedAddress = resolveAddressForBuilding(building: building) {
                    selectedAddress = matchedAddress
                    selectedAddressIdForCard = matchedAddress.addressId
                } else {
                    selectedAddress = nil
                    selectedAddressIdForCard = nil
                }
                withAnimation { showLocationCard = true }
            case .address(let address):
                selectedAddress = address
                selectedAddressIdForCard = address.addressId
                let gersIdString = address.buildingGersId ?? address.gersId ?? ""
                if !gersIdString.isEmpty,
                   let match = featuresService.buildings?.features.first(where: {
                       ($0.properties.gersId ?? $0.id ?? "").caseInsensitiveCompare(gersIdString) == .orderedSame
                   }) {
                    selectedBuilding = match.properties
                } else {
                    selectedBuilding = nil
                }
                withAnimation { showLocationCard = true }
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

        // Fast path: Gold/address_point — feature already has full address in properties
        if building.source == "gold" || building.source == "address_point",
           let addrIdStr = building.addressId, !addrIdStr.isEmpty,
           let addrId = UUID(uuidString: addrIdStr) {
            let formatted = building.addressText ?? "\(building.houseNumber ?? "") \(building.streetName ?? "")".trimmingCharacters(in: .whitespaces)
            return MapLayerManager.AddressTapResult(
                addressId: addrId,
                formatted: formatted.isEmpty ? "Address" : formatted,
                gersId: building.gersId,
                buildingGersId: building.buildingId,
                houseNumber: building.houseNumber,
                streetName: building.streetName
            )
        }

        guard let addresses = featuresService.addresses?.features, !addresses.isEmpty else { return nil }

        // Collect all building IDs for matching (case-insensitive)
        var buildingIds: [String] = []
        if let g = building.gersId, !g.isEmpty { buildingIds.append(g.lowercased()) }
        if !building.id.isEmpty { buildingIds.append(building.id.lowercased()) }
        if let bid = building.buildingId, !bid.isEmpty { buildingIds.append(bid.lowercased()) }

        // Strategy 1: Match by building's addressId against address feature id
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
        let house = feature.properties.houseNumber ?? ""
        let street = feature.properties.streetName ?? ""
        let formatted = feature.properties.formatted ?? "\(house) \(street)".trimmingCharacters(in: .whitespaces)
        return MapLayerManager.AddressTapResult(
            addressId: uuid,
            formatted: formatted,
            gersId: feature.properties.gersId,
            buildingGersId: feature.properties.buildingGersId,
            houseNumber: feature.properties.houseNumber,
            streetName: feature.properties.streetName
        )
    }

    private func updateBuildingColorAfterComplete(gersId: String) {
        layerManager?.updateBuildingState(gersId: gersId, status: "visited", scansTotal: 0)
    }

    private func addressLabelsForTargets() -> [String: String] {
        guard let features = featuresService.buildings?.features else { return [:] }
        var labels: [String: String] = [:]
        for f in features {
            let gersId = f.properties.gersId ?? f.id ?? ""
            let addr = f.properties.addressText ?? "Building"
            labels[gersId] = addr
        }
        return labels
    }

    private func startBuildingSession(campaignId: UUID, features: [BuildingFeature]) {
        let targetIds = features.compactMap { f in f.properties.gersId ?? f.id }
        guard !targetIds.isEmpty else { return }
        var centroids: [String: CLLocationCoordinate2D] = [:]
        for f in features {
            guard let gersId = f.properties.gersId ?? f.id else { continue }
            guard let poly = f.geometry.asPolygon else { continue }
            var sumLat = 0.0, sumLon = 0.0, n = 0
            for ring in poly {
                for p in ring where p.count >= 2 {
                    sumLon += p[0]
                    sumLat += p[1]
                    n += 1
                }
            }
            if n > 0 {
                centroids[gersId] = CLLocationCoordinate2D(latitude: sumLat / Double(n), longitude: sumLon / Double(n))
            }
        }
        Task {
            try? await sessionManager.startBuildingSession(
                campaignId: campaignId,
                targetBuildings: targetIds,
                autoCompleteEnabled: false,
                centroids: centroids
            )
        }
    }
    
    // MARK: - Real-time Subscription
    
    private func setupRealTimeSubscription() {
        guard let campId = UUID(uuidString: campaignId) else { return }
        
        let subscriber = BuildingStatsSubscriber(supabase: SupabaseManager.shared.client)
        self.statsSubscriber = subscriber
        
        // Set up update callback before subscribing
        Task {
            await subscriber.setUpdateCallback { gersId, status, scansTotal, qrScanned in
                Task { @MainActor in
                    self.updateBuildingColor(gersId: gersId, status: status, scansTotal: scansTotal, qrScanned: qrScanned)
                }
            }
            await subscriber.subscribe(campaignId: campId)
        }
    }
    
    private func updateBuildingColor(gersId: String, status: String, scansTotal: Int, qrScanned: Bool) {
        guard let manager = layerManager else { return }
        print("📊 Building stats updated: GERS=\(gersId), status=\(status), scans=\(scansTotal)")
        manager.updateBuildingState(gersId: gersId, status: status, scansTotal: scansTotal)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Mapbox Map Representable

struct CampaignMapboxMapViewRepresentable: UIViewRepresentable {
    var preferredSize: CGSize = CGSize(width: 320, height: 260)
    var useDarkStyle: Bool = false
    var sessionLocation: CLLocation?
    var showSessionPuck: Bool = false
    let onMapReady: (MapView) -> Void
    let onTap: (CGPoint) -> Void

    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!
    private static let sessionPuckSourceId = "session-puck-source"

    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions()
        // Fallback when preferredSize is zero or invalid (e.g. fullscreen before layout) to avoid Mapbox "Invalid size" / content scale factor nan
        let size = (preferredSize.width <= 0 || preferredSize.height <= 0)
            ? CGSize(width: 320, height: 260)
            : CGSize(width: max(320, preferredSize.width), height: max(260, preferredSize.height))
        let initialFrame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let mapView = MapView(frame: initialFrame, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let styleURI = useDarkStyle ? Self.darkStyleURI : Self.lightStyleURI
        mapView.mapboxMap.loadStyle(styleURI)
        
        // Enable gestures
        mapView.gestures.options.pitchEnabled = true
        mapView.gestures.options.rotateEnabled = true
        
        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        context.coordinator.mapView = mapView
        
        DispatchQueue.main.async {
            onMapReady(mapView)
        }
        
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        context.coordinator.updateSessionPuck(location: sessionLocation, show: showSessionPuck)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }
    
    class Coordinator: NSObject {
        weak var mapView: MapView?
        let onTap: (CGPoint) -> Void

        init(onTap: @escaping (CGPoint) -> Void) {
            self.onTap = onTap
        }

        func updateSessionPuck(location: CLLocation?, show: Bool) {
            guard let map = mapView?.mapboxMap else { return }
            guard map.sourceExists(withId: CampaignMapboxMapViewRepresentable.sessionPuckSourceId) else { return }
            if show, let loc = location {
                let feature = Feature(geometry: .point(Point(loc.coordinate)))
                try? map.updateGeoJSONSource(withId: CampaignMapboxMapViewRepresentable.sessionPuckSourceId, geoJSON: .feature(feature))
            } else {
                try? map.updateGeoJSONSource(withId: CampaignMapboxMapViewRepresentable.sessionPuckSourceId, geoJSON: .featureCollection(FeatureCollection(features: [])))
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = gesture.location(in: mapView)
            onTap(point)
        }
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

// MARK: - Location Card View

struct LocationCardView: View {
    /// Overture GERS ID string (from map feature)
    let gersId: String
    let campaignId: UUID
    /// Campaign address ID from tapped building (used for direct lookup so card shows linked state)
    let addressId: UUID?
    /// Address from tapped building (shown immediately)
    let addressText: String?
    /// When multiple addresses exist, which one to show as primary; nil = show list or first
    var preferredAddressId: UUID?
    /// Per-address statuses for pill coloring in the multi-address list
    var addressStatuses: [UUID: AddressStatus] = [:]
    /// Called when user selects an address from the list (id) or taps "Back to list" (nil)
    var onSelectAddress: ((UUID?) -> Void)?
    /// Called once when addresses are resolved, with all address UUIDs for this building
    var onAddressesResolved: (([UUID]) -> Void)?
    let onClose: () -> Void
    /// Called after status is saved to Supabase so the map can update building color immediately
    var onStatusUpdated: ((UUID, AddressStatus) -> Void)?
    
    @EnvironmentObject private var entitlementsService: EntitlementsService
    @StateObject private var dataService: BuildingDataService
    /// Building details from GET /api/buildings/{gersId} (scan data gated by backend for non‑Pro).
    @State private var buildingDetails: BuildingDetailResponse?
    @StateObject private var voiceRecorder = VoiceRecorderManager()
    @StateObject private var transcriptionService = TranscriptionService()
    @State private var nameText: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var phoneText: String = ""
    @State private var emailText: String = ""
    @State private var notesText: String = ""
    @State private var manualAddressText: String = ""
    @State private var showAddResidentSheet = false
    @State private var addResidentAddress: ResolvedAddress?
    @State private var isUploadingVoiceNote = false
    @State private var voiceNoteError: String?
    @State private var showContactBlock = false
    @State private var showTaskBlock = false
    @State private var showAppointmentBlock = false
    @State private var showVoiceLogPreviewSheet = false
    @State private var taskTitle = ""
    @State private var taskDueText = ""
    @State private var appointmentTitle = ""
    @State private var appointmentStartText = ""
    @State private var appointmentEndText = ""
    @State private var appointmentLocationText = ""
    @State private var voiceLogPreviewResult: VoiceLogResponse?
    @State private var flyrEventIdForRecording: UUID?
    @State private var showPaywall = false

    init(gersId: String, campaignId: UUID, addressId: UUID? = nil, addressText: String? = nil, preferredAddressId: UUID? = nil, addressStatuses: [UUID: AddressStatus] = [:], onSelectAddress: ((UUID?) -> Void)? = nil, onAddressesResolved: (([UUID]) -> Void)? = nil, onClose: @escaping () -> Void, onStatusUpdated: ((UUID, AddressStatus) -> Void)? = nil) {
        self.gersId = gersId
        self.campaignId = campaignId
        self.addressId = addressId
        self.addressText = addressText
        self.preferredAddressId = preferredAddressId
        self.addressStatuses = addressStatuses
        self.onSelectAddress = onSelectAddress
        self.onAddressesResolved = onAddressesResolved
        self.onClose = onClose
        self.onStatusUpdated = onStatusUpdated
        _dataService = StateObject(wrappedValue: BuildingDataService(supabase: SupabaseManager.shared.client))
    }
    
    private var cardBackground: Color { .black }
    private var cardFieldBorder: Color { Color(white: 0.28) }
    private var cardPlaceholder: Color { Color(white: 0.5) }
    
    /// Street number/name only from a full address string (e.g. "74 MADDEN PL , BOWMANVILLE, ON" -> "74 MADDEN PL")
    private func streetOnly(from full: String) -> String {
        if let idx = full.range(of: " , ")?.lowerBound {
            return String(full[..<idx]).trimmingCharacters(in: .whitespaces)
        }
        return full.trimmingCharacters(in: .whitespaces)
    }

    /// Address string for the card header (same row as Save and X).
    private var headerAddress: String {
        if let address = dataService.buildingData.address {
            return streetOnly(from: address.displayStreet).uppercased()
        }
        if let addr = addressText, !addr.isEmpty {
            return streetOnly(from: addr).uppercased()
        }
        if dataService.buildingData.isLoading {
            return "Loading..."
        }
        return "BUILDING"
    }

    private var needsScroll: Bool {
        showContactBlock || showTaskBlock || showAppointmentBlock || dataService.buildingData.error != nil
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
            universalCardContent(displayAddress: addressText, address: nil)
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
                let isVisited = addrStatus?.mapLayerStatus == "visited"
                let isHot = addrStatus?.mapLayerStatus == "hot"
                Button {
                    onSelectAddress?(addr.id)
                } label: {
                    HStack {
                        Text(streetOnly(from: addr.displayStreet))
                            .font(.system(size: 14))
                            .foregroundColor(isVisited ? .green : (isHot ? Color(UIColor(hex: "#3b82f6")!) : .white))
                        Spacer()
                        if isVisited {
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
                        isVisited
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
        VStack(alignment: .leading, spacing: 0) {
            // Header: address (leading) + Save + X (trailing)
            HStack(alignment: .center, spacing: 8) {
                Text(headerAddress)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Button("Save") {
                    onSaveForm()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.red)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            cardContentBody
        }
        .frame(maxWidth: 400)
        .background(cardBackground)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 20)
        .task {
            await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId, preferredAddressId: preferredAddressId)
            buildingDetails = try? await BuildingDetailsAPI.shared.fetchBuildingDetails(gersId: gersId, campaignId: campaignId)
        }
        .onChange(of: preferredAddressId) { _, newId in
            Task {
                await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId, preferredAddressId: newId)
            }
        }
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
        .alert("Voice note", isPresented: .init(get: { voiceNoteError != nil }, set: { if !$0 { voiceNoteError = nil } })) {
            Button("OK", role: .cancel) { voiceNoteError = nil }
        } message: {
            if let msg = voiceNoteError { Text(msg) }
        }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
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
                universalFormFields
            }
            if showTaskBlock {
                taskFieldsBlock
            }
            if showAppointmentBlock {
                appointmentFieldsBlock
            }
            twoRowActionButtons(address: nil)
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
                universalFormFields
            }
            if showTaskBlock {
                taskFieldsBlock
            }
            if showAppointmentBlock {
                appointmentFieldsBlock
            }
            twoRowActionButtons(address: nil)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Universal card content (dark layout like screenshot)
    
    private func universalCardContent(displayAddress: String, address: ResolvedAddress?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if showContactBlock {
                universalFormFields
            }
            if showTaskBlock {
                taskFieldsBlock
            }
            if showAppointmentBlock {
                appointmentFieldsBlock
            }
            twoRowActionButtons(address: address)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var universalFormFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person")
                        .foregroundColor(cardPlaceholder)
                        .frame(width: 20)
                    universalTextField(placeholder: "First name", text: $firstName)
                }
                universalTextField(placeholder: "Last name", text: $lastName)
            }
            HStack(spacing: 8) {
                Image(systemName: "phone")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Phone", text: $phoneText)
            }
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Email", text: $emailText)
            }
            Text("Add notes")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
            TextField("Add notes", text: $notesText, axis: .vertical)
                .lineLimit(3...5)
                .padding(10)
                .foregroundColor(.white)
                .background(Color.black)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
        }
    }

    private var taskFieldsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Task title", text: $taskTitle)
            }
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Due (e.g. Tomorrow 6pm)", text: $taskDueText)
            }
        }
    }

    private var appointmentFieldsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Appointment title", text: $appointmentTitle)
            }
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Start (e.g. Fri 2pm)", text: $appointmentStartText)
            }
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "End (e.g. Fri 3pm)", text: $appointmentEndText)
            }
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle")
                    .foregroundColor(cardPlaceholder)
                    .frame(width: 20)
                universalTextField(placeholder: "Location", text: $appointmentLocationText)
            }
        }
    }

    private func universalTextField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(10)
            .foregroundColor(.white)
            .background(Color.black)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(cardFieldBorder, lineWidth: 1))
    }

    private var actionButtonPillStyle: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.red)
    }

    /// Two rows: (Contact, Knock, Conversation) | (Task, Appointment, AI Summary)
    private func twoRowActionButtons(address: ResolvedAddress?) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: { showContactBlock.toggle() }) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(actionButtonPillStyle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Contact")
                Button(action: {
                    if let address = address {
                        onClose(); logVisitStatus(address, status: .delivered)
                    }
                }) {
                    Image(systemName: "door.left.hand.closed")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(actionButtonPillStyle)
                        .opacity(address != nil ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(address == nil)
                .accessibilityLabel("Knock")
                Button(action: {
                    if let address = address {
                        onClose(); logVisitStatus(address, status: .talked)
                    }
                }) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(actionButtonPillStyle)
                        .opacity(address != nil ? 1.0 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(address == nil)
                .accessibilityLabel("Conversation")
            }
            HStack(spacing: 8) {
                Button(action: { showTaskBlock.toggle() }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(actionButtonPillStyle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Task")
                Button(action: { showAppointmentBlock.toggle() }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(actionButtonPillStyle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Appointment")
                aiSummaryButton(address: address)
            }
        }
        .padding(.top, 8)
    }

    private func universalActionButtons(address: ResolvedAddress) -> some View {
        twoRowActionButtons(address: address)
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
                universalFormFields
            }
            if showTaskBlock {
                taskFieldsBlock
            }
            if showAppointmentBlock {
                appointmentFieldsBlock
            }
            twoRowActionButtons(address: address)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear {
            if firstName.isEmpty, lastName.isEmpty {
                if let resident = dataService.buildingData.primaryResident {
                    let parts = resident.displayName.split(separator: " ", maxSplits: 1)
                    firstName = String(parts.first ?? "")
                    lastName = parts.count > 1 ? String(parts[1]) : ""
                } else if let contact = dataService.buildingData.contactName, !contact.isEmpty {
                    let parts = contact.split(separator: " ", maxSplits: 1)
                    firstName = String(parts.first ?? "")
                    lastName = parts.count > 1 ? String(parts[1]) : ""
                }
            }
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
    
    private func aiSummaryButton(address: ResolvedAddress?) -> some View {
        Group {
            if voiceRecorder.isRecording {
                Button(action: { stopAndUploadVoiceLog(address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.black)
                        Text("\(Int(voiceRecorder.recordingDuration))s")
                            .font(.system(size: 12))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(actionButtonPillStyle)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingVoiceNote)
                .accessibilityLabel("Stop and send to Follow Up Boss")
            } else {
                Button(action: { startAISummaryRecording() }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(actionButtonPillStyle)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingVoiceNote || addressId == nil)
                .accessibilityLabel("AI Summary")
            }
        }
    }

    private func startAISummaryRecording() {
        flyrEventIdForRecording = UUID()
        Task {
            let granted = await voiceRecorder.requestPermission()
            guard granted else {
                voiceNoteError = "Microphone access is required for voice notes."
                return
            }
            await MainActor.run {
                _ = voiceRecorder.startRecording()
            }
        }
    }

    private func stopAndUploadVoiceLog(address: ResolvedAddress?) {
        guard let url = voiceRecorder.stopRecording(),
              let eventId = flyrEventIdForRecording,
              let addrId = address?.id ?? addressId else {
            flyrEventIdForRecording = nil
            return
        }
        let addressString = address?.displayFull ?? addressText ?? ""
        isUploadingVoiceNote = true
        Task {
            defer {
                Task { @MainActor in
                    isUploadingVoiceNote = false
                    flyrEventIdForRecording = nil
                }
            }
            do {
                let result = try await VoiceLogAPI.shared.submitVoiceLog(
                    audioURL: url,
                    flyrEventId: eventId,
                    addressId: addrId,
                    campaignId: campaignId,
                    address: addressString,
                    leadId: nil
                )
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    voiceLogPreviewResult = result
                    showVoiceLogPreviewSheet = true
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    voiceNoteError = error.localizedDescription
                }
            }
        }
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
    
    private func logVisitStatus(_ address: ResolvedAddress, status: AddressStatus) {
        Task {
            do {
                try await VisitsAPI.shared.updateStatus(
                    addressId: address.id,
                    campaignId: campaignId,
                    status: status,
                    notes: notesText.isEmpty ? nil : notesText
                )
                dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id, preferredAddressId: preferredAddressId ?? address.id)
                await MainActor.run {
                    onStatusUpdated?(address.id, status)
                }
            } catch {
                print("⚠️ [LocationCardView] Failed to update status: \(error.localizedDescription)")
            }
        }
    }
    
    private func addContact(_ address: ResolvedAddress) {
        showAddResidentSheet = true
        addResidentAddress = address
    }

    /// Save form and close. If we have a linked address, persist notes/status then close; otherwise just close.
    private func onSaveForm() {
        if let address = dataService.buildingData.address {
            logVisitStatus(address, status: .delivered)
        }
        onClose()
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
                    .disabled(fullName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .disabled(isSaving)
        }
    }
    
    private func saveResident() {
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
                let contact = Contact(
                    fullName: name,
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    address: address.displayFull,
                    campaignId: campaignId,
                    status: .new
                )
                _ = try await ContactsService.shared.addContact(contact, userID: userId, addressId: address.id)
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

// MARK: - Preview

#Preview {
    CampaignMapView(campaignId: "preview-campaign-id")
}
