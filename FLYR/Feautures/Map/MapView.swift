import MapboxMaps
import SwiftUI
import CoreLocation
import Combine
import UIKit

// Extracted view to reduce compiler complexity (ultra-minimal: search, campaigns, info, optional toast)
private struct MapContentView: View {
    @Binding var searchText: String
    var colorScheme: ColorScheme
    var campaignPolygon: [CLLocationCoordinate2D]?
    var campaignMarkers: [CampaignMarker]
    var farmMarkers: [FarmMarker]
    var selectedCampaignId: UUID?
    var selectedCampaignName: String?
    var campaigns: [CampaignListItem]
    var isLoadingCampaign: Bool
    var onMarkerTap: (UUID) -> Void
    var onClearCampaign: () -> Void
    var onStartSession: () -> Void
    var onShowGestureInfo: () -> Void
    var isLocationDenied: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Map (full screen)
            SimpleMapViewRepresentable(
                colorScheme: colorScheme,
                campaignPolygon: campaignPolygon,
                campaignMarkers: campaignMarkers,
                farmMarkers: farmMarkers,
                selectedCampaignId: selectedCampaignId,
                onMarkerTap: onMarkerTap
            )
            .ignoresSafeArea()

            // Top: Search, Info, locate
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    MapSearchBar(
                        searchText: $searchText,
                        campaigns: campaigns,
                        onSelectCampaign: onMarkerTap,
                        isLoading: isLoadingCampaign
                    )
                    .frame(maxWidth: .infinity)

                    // Legend/info button removed – legend hidden from every map per design
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Pill card: address/campaign name (left), red Start session button (right)
                if let name = selectedCampaignName, !name.isEmpty {
                    HStack {
                        Text(name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        Button {
                            onStartSession()
                        } label: {
                            Text("Start session")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Gentle prompt when location permission denied
                if isLocationDenied {
                    Text("Location access helps center the map. Enable in Settings if you’d like.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct FullScreenMapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var uiState: AppUIState

    @State private var showCampaignPicker = false
    @State private var selectedCampaignId: UUID?
    @State private var selectedFarmId: UUID?
    @State private var campaignPolygon: [CLLocationCoordinate2D]? = nil
    @State private var mapSearchText = ""
    @State private var showGestureInfoSheet = false
    @StateObject private var viewModel = MapCampaignPickerViewModel()
    @ObservedObject private var sessionManager = SessionManager.shared

    @State private var showSessionSummary = false
    @State private var sessionSummaryData: SessionSummaryData?

    @State private var showSessionStartSheet = false
    @State private var sessionStartPreselectedCampaign: CampaignV2?
    @State private var isPreparingSessionStart = false

    @StateObject private var locationManager = LocationManager()
    @State private var hasCenteredOnLocation = false

    @State private var campaignMarkers: [CampaignMarker] = []
    @State private var farmMarkers: [FarmMarker] = []
    @State private var isLoadingSelectedCampaign = false

    private var selectedCampaignName: String? {
        guard let id = selectedCampaignId else { return nil }
        return viewModel.campaigns.first { $0.id == id }?.name
    }

    private func handleShowCampaignPicker() {
        showCampaignPicker = true
    }

    private var mapContentView: some View {
        MapContentView(
            searchText: $mapSearchText,
            colorScheme: colorScheme,
            campaignPolygon: campaignPolygon,
            campaignMarkers: campaignMarkers,
            farmMarkers: farmMarkers,
            selectedCampaignId: selectedCampaignId,
            selectedCampaignName: selectedCampaignName,
            campaigns: viewModel.campaigns,
            isLoadingCampaign: isLoadingSelectedCampaign,
            onMarkerTap: { id in
                selectedCampaignId = id
                syncSelectionToUIState()
            },
            onClearCampaign: {
                selectedCampaignId = nil
                selectedFarmId = nil
                syncSelectionToUIState()
                Task { await loadSelectedCampaignOrFarm() }
            },
            onStartSession: { startSessionFromMap() },
            onShowGestureInfo: { showGestureInfoSheet = true },
            isLocationDenied: locationManager.isLocationDenied
        )
        .sheet(isPresented: $showGestureInfoSheet) {
            MapGestureInfoSheet()
        }
    }

    private func syncSelectionToUIState() {
        uiState.selectedMapCampaignId = selectedCampaignId
        uiState.selectedMapCampaignName = selectedCampaignName
    }
    
    private var sessionMapContentView: some View {
        SessionMapView()
            .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var mainContentView: some View {
        if sessionManager.isActive {
            sessionMapContentView
        } else {
            mapContentView
        }
    }
    
    private func applySheets<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .sheet(isPresented: $showCampaignPicker) {
                    campaignPickerSheet
                }
                .sheet(isPresented: $showSessionSummary) {
                    sessionSummarySheet
                }
                .sheet(isPresented: $showSessionStartSheet) {
                    SessionStartView(
                        showCancelButton: true,
                        preselectedCampaign: sessionStartPreselectedCampaign
                    )
                    .onDisappear {
                        sessionStartPreselectedCampaign = nil
                    }
                }
        )
    }

    private func applySelectionChanges<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .onChange(of: selectedCampaignId) { _, newId in
                    syncSelectionToUIState()
                    if newId != nil {
                        isLoadingSelectedCampaign = true
                    } else {
                        isLoadingSelectedCampaign = false
                    }
                    handleCampaignIdChange()
                }
                .onChange(of: selectedFarmId) { _, _ in
                    syncSelectionToUIState()
                    handleFarmIdChange()
                }
        )
    }
    
    private func applyTask<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .task(id: "mapCampaigns") {
                    await viewModel.loadCampaignsAndFarms()
                    await loadMapMarkers()
                    locationManager.requestLocation()
                }
        )
    }
    
    private func applyViewModelChanges<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .onChange(of: viewModel.campaigns) { _, _ in
                    handleCampaignsChange()
                }
                .onChange(of: viewModel.farms) { _, _ in
                    handleFarmsChange()
                }
        )
    }
    
    private func applyLocationChanges<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .onChange(of: locationManager.currentLocation) { _, newLocation in
                    handleLocationChange(newLocation)
                }
        )
    }
    
    private func applyNotifications<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .onReceive(NotificationCenter.default.publisher(for: .sessionEnded)) { _ in
                    handleSessionEnded()
                }
        )
    }
    
    private func buildBody() -> AnyView {
        let step1 = applySheets(to: mainContentView)
        let step2 = applySelectionChanges(to: step1)
        let step3 = applyTask(to: step2)
        let step4 = applyViewModelChanges(to: step3)
        let step5 = applyLocationChanges(to: step4)
        return applyNotifications(to: step5)
    }
    
    var body: some View {
        buildBody()
    }
    
    private var campaignPickerSheet: some View {
        MapCampaignPickerSheet(
            selectedCampaignId: $selectedCampaignId,
            selectedFarmId: $selectedFarmId,
            viewModel: viewModel
        ) {
            showCampaignPicker = false
            Task {
                await loadSelectedCampaignOrFarm()
            }
        }
    }
    
    private var sessionSummarySheet: some View {
        Group {
            if let summaryData = sessionSummaryData {
                EndSessionSummaryView(
                    data: summaryData,
                    userName: AuthManager.shared.user?.email
                )
            }
        }
    }
    
    private func startSessionFromMap() {
        guard let campaignId = selectedCampaignId else { return }
        isPreparingSessionStart = true
        Task {
            do {
                let campaign = try await sharedV2API.fetchCampaign(id: campaignId)
                await MainActor.run {
                    sessionStartPreselectedCampaign = campaign
                    isPreparingSessionStart = false
                    showSessionStartSheet = true
                }
            } catch {
                await MainActor.run {
                    isPreparingSessionStart = false
                    print("⚠️ [Map] Failed to load campaign for session: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleCampaignIdChange() {
        Task {
            await loadSelectedCampaignOrFarm()
            await MainActor.run {
                isLoadingSelectedCampaign = false
            }
        }
    }
    
    private func handleFarmIdChange() {
        Task {
            await loadSelectedCampaignOrFarm()
            await MainActor.run {
                isLoadingSelectedCampaign = false
            }
        }
    }
    
    private func handleCampaignsChange() {
        Task {
            await loadMapMarkers()
        }
    }
    
    private func handleFarmsChange() {
        Task {
            await loadMapMarkers()
        }
    }
    
    private func handleLocationChange(_ newLocation: CLLocation?) {
        if let location = newLocation, !hasCenteredOnLocation {
            centerMapOnLocation(location.coordinate)
            hasCenteredOnLocation = true
        }
    }
    
    /// Building sessions set lastEndedSummary; use it when present. Otherwise build summary from current manager state (SessionMapView / non-building flow).
    private func handleSessionEnded() {
        if let data = SessionManager.lastEndedSummary {
            sessionSummaryData = data
            showSessionSummary = true
            return
        }
        if sessionManager.startTime != nil {
            sessionSummaryData = SessionSummaryData(
                distance: sessionManager.distanceMeters,
                time: sessionManager.elapsedTime,
                goalType: sessionManager.goalType,
                goalAmount: sessionManager.goalAmount,
                pathCoordinates: sessionManager.pathCoordinates,
                completedCount: nil,
                startTime: sessionManager.startTime
            )
            showSessionSummary = true
        }
    }
    
    private func loadSelectedCampaignOrFarm() async {
        campaignPolygon = nil

        if let campaignId = selectedCampaignId {
            if let mapView = SimpleMapViewRepresentable.currentMapView {
                let preferLight = (colorScheme != .dark)
                MapController.shared.applyMode(.campaign3D, to: mapView, campaignPolygon: nil, campaignId: campaignId, preferLightStyle: preferLight)
                // Fly to selected campaign marker when selected from search or pin tap
                if let marker = campaignMarkers.first(where: { $0.id == campaignId }) {
                    mapView.camera.fly(to: CameraOptions(center: marker.coordinate, zoom: 15), duration: 0.5)
                }
            }
        } else if selectedFarmId != nil {
            // TODO: Fetch farm addresses when farm polygon support is added
            print("⚠️ [Map] Farm polygon support coming soon")
        } else {
            if let mapView = SimpleMapViewRepresentable.currentMapView {
                let mode: MapMode = colorScheme == .dark ? .dark : .light
                MapController.shared.applyMode(mode, to: mapView, campaignPolygon: nil, campaignId: nil)
            }
        }
    }
    
    private func loadMapMarkers() async {
        // Load campaign markers
        var newCampaignMarkers: [CampaignMarker] = []
        for campaign in viewModel.campaigns {
            do {
                // Fetch addresses for this campaign
                let addresses = try await CampaignsAPI.shared.fetchAddresses(campaignId: campaign.id)
                if let marker = CampaignMarker.fromCampaign(campaign, addresses: addresses) {
                    newCampaignMarkers.append(marker)
                }
            } catch {
                print("⚠️ [Map] Failed to fetch addresses for campaign \(campaign.id): \(error)")
            }
        }
        campaignMarkers = newCampaignMarkers
        
        // Load farm markers
        var newFarmMarkers: [FarmMarker] = []
        for farmItem in viewModel.farms {
            do {
                // Fetch full farm data to get polygon
                if let farm = try await FarmService.shared.fetchFarm(id: farmItem.id) {
                    if let marker = FarmMarker.fromFarm(farm) {
                        newFarmMarkers.append(marker)
                    }
                }
            } catch {
                print("⚠️ [Map] Failed to fetch farm \(farmItem.id): \(error)")
            }
        }
        farmMarkers = newFarmMarkers
        
        print("✅ [Map] Loaded \(campaignMarkers.count) campaign markers and \(farmMarkers.count) farm markers")
    }
    
    private func centerMapOnLocation(_ coordinate: CLLocationCoordinate2D) {
        guard let mapView = SimpleMapViewRepresentable.currentMapView,
              let map = mapView.mapboxMap else {
            // If map isn't ready yet, try again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [coordinate] in
                // Retry centering
                if let mapView = SimpleMapViewRepresentable.currentMapView,
                   let map = mapView.mapboxMap {
                    let cameraOptions = CameraOptions(
                        center: coordinate,
                        zoom: 15
                    )
                    map.setCamera(to: cameraOptions)
                    print("📍 [Map] Centered map on current location (retry): \(coordinate)")
                }
            }
            return
        }
        
        // Wait for map to be loaded before centering
        if map.isStyleLoaded {
            let cameraOptions = CameraOptions(
                center: coordinate,
                zoom: 15
            )
            map.setCamera(to: cameraOptions)
            print("📍 [Map] Centered map on current location: \(coordinate)")
        } else {
            // Wait for map to load, then center
            map.onMapLoaded.observeNext { _ in
                let cameraOptions = CameraOptions(
                    center: coordinate,
                    zoom: 15
                )
                map.setCamera(to: cameraOptions)
                print("📍 [Map] Centered map on current location after load: \(coordinate)")
            }
        }
    }
}

// MARK: - Location Manager

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?
    @Published var isLocationDenied: Bool = false
    private let manager = CLLocationManager()
    private var hasRequestedLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        guard !hasRequestedLocation else { return }
        hasRequestedLocation = true
        updateDeniedState()
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    private func updateDeniedState() {
        let status = manager.authorizationStatus
        isLocationDenied = (status == .denied || status == .restricted)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        isLocationDenied = false
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ [LocationManager] Failed to get location: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateDeniedState()
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if isLocationDenied {
            print("⚠️ [LocationManager] Location permission denied")
        }
    }
}

struct SimpleMapViewRepresentable: UIViewRepresentable {
    var colorScheme: ColorScheme
    var campaignPolygon: [CLLocationCoordinate2D]?
    var campaignMarkers: [CampaignMarker]
    var farmMarkers: [FarmMarker]
    var selectedCampaignId: UUID?
    var onMarkerTap: (UUID) -> Void

    static weak var currentMapView: MapView?

    private var mapStyleFromScheme: MapStyle {
        colorScheme == .dark ? .dark : .light
    }

    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)

        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 24)
        mapView.ornaments.options.compass.visibility = .hidden

        mapView.mapboxMap?.loadStyle(mapStyleFromScheme.mapboxStyleURI)

        context.coordinator.mapView = mapView
        Self.currentMapView = mapView

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        mapView.addGestureRecognizer(tapGesture)

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.onMarkerTap = onMarkerTap
        context.coordinator.selectedCampaignId = selectedCampaignId
        context.coordinator.updateStyle(mapStyleFromScheme)

        if let polygon = campaignPolygon {
            let preferLight = (colorScheme != .dark)
            MapController.shared.applyMode(.campaign3D, to: mapView, campaignPolygon: polygon, campaignId: nil, preferLightStyle: preferLight)
        }

        context.coordinator.updateMarkers(campaignMarkers: campaignMarkers, farmMarkers: farmMarkers, selectedCampaignId: selectedCampaignId, on: mapView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMarkerTap: onMarkerTap)
    }

    class Coordinator: NSObject {
        weak var mapView: MapView?
        var onMarkerTap: (UUID) -> Void
        var selectedCampaignId: UUID?
        private let campaignLayerIds = ["campaign-markers-layer", "campaign-markers-layer-inner", "campaign-markers-layer-text"]
        private var currentStyle: MapStyle?
        private var hasLoadedTargetIcon = false

        init(onMarkerTap: @escaping (UUID) -> Void) {
            self.onMarkerTap = onMarkerTap
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView, gesture.state == .ended else { return }
            let point = gesture.location(in: mapView)
            let options = RenderedQueryOptions(layerIds: campaignLayerIds, filter: nil)
            mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let features):
                    if let first = features.first {
                        let props = first.queriedFeature.feature.properties
                        if let idVal = props?["id"], case .string(let idStr) = idVal, let uuid = UUID(uuidString: idStr) {
                            DispatchQueue.main.async { self.onMarkerTap(uuid) }
                        }
                    }
                case .failure:
                    break
                }
            }
        }

        func updateMarkers(campaignMarkers: [CampaignMarker], farmMarkers: [FarmMarker], selectedCampaignId: UUID?, on mapView: MapView) {
            if !hasLoadedTargetIcon, let map = mapView.mapboxMap {
                loadTargetIcon(to: map)
            }
            MapMarkersManager.shared.addCampaignMarkers(campaigns: campaignMarkers, to: mapView, selectedCampaignId: selectedCampaignId)
            MapMarkersManager.shared.addFarmMarkers(farms: farmMarkers, to: mapView)
        }

        private func loadTargetIcon(to map: MapboxMap) {
            hasLoadedTargetIcon = true
        }

        func updateStyle(_ style: MapStyle) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap,
                  currentStyle != style else { return }
            currentStyle = style
            map.loadStyle(style.mapboxStyleURI)
        }
    }
}
