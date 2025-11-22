import MapboxMaps
import SwiftUI
import CoreLocation
import Combine

// Extracted view to reduce compiler complexity
private struct MapContentView: View {
    @Binding var is3DMode: Bool
    var mapStyleMode: Binding<MapStyle>
    var campaignPolygon: [CLLocationCoordinate2D]?
    var campaignMarkers: [CampaignMarker]
    var farmMarkers: [FarmMarker]
    var selectedCampaignId: UUID?
    var selectedFarmId: UUID?
    var onToggle3D: () -> Void
    var onShowCampaignPicker: () -> Void
    var onShowSessionStart: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Simple map view wrapper
            SimpleMapViewRepresentable(
                is3DMode: $is3DMode,
                mapStyleMode: mapStyleMode,
                campaignPolygon: campaignPolygon,
                campaignMarkers: campaignMarkers,
                farmMarkers: farmMarkers
            )
            .ignoresSafeArea()
            
            // 3D Toggle, Map Style Toggle, and Campaign Picker Buttons
            VStack(spacing: 12) {
                // 3D Toggle Button
                Button(action: onToggle3D) {
                    Image(systemName: is3DMode ? "cube.fill" : "cube")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(is3DMode ? Color.red : Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                // Map Style Toggle Button
                MapStyleToggleButton(mapStyleMode: mapStyleMode)
                
                // Campaign/Farm Picker Button
                Button(action: onShowCampaignPicker) {
                    let isSelected = selectedCampaignId != nil || selectedFarmId != nil
                    Image(systemName: isSelected ? "map.fill" : "map")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(isSelected ? Color.red : Color.black.opacity(0.6))
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                
                Spacer()
            }
            .padding(.top, 60)
            .padding(.trailing, 16)
            
            // Start Session Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onShowSessionStart) {
                        Text("Start Session")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .shadow(radius: 10)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

struct FullScreenMapView: View {
    @State private var is3DMode = false
    @State private var showCampaignPicker = false
    @State private var selectedCampaignId: UUID?
    @State private var selectedFarmId: UUID?
    @State private var campaignPolygon: [CLLocationCoordinate2D]? = nil
    @StateObject private var viewModel = MapCampaignPickerViewModel()
    @ObservedObject private var sessionManager = SessionManager.shared
    
    @State private var showSessionStartSheet = false
    @State private var showSessionSummary = false
    @State private var sessionSummaryData: SessionSummaryData?
    
    @StateObject private var locationManager = LocationManager()
    @State private var hasCenteredOnLocation = false
    
    @State private var campaignMarkers: [CampaignMarker] = []
    @State private var farmMarkers: [FarmMarker] = []
    
    @AppStorage("mapStyleMode") private var mapStyleModeRaw: String = MapStyle.standard.rawValue
    
    var mapStyleMode: MapStyle {
        get { MapStyle(rawValue: mapStyleModeRaw) ?? .standard }
        set { mapStyleModeRaw = newValue.rawValue }
    }
    
    // Helper functions to reduce body complexity
    private func makeToggle3DButton() -> some View {
        let iconName = is3DMode ? "cube.fill" : "cube"
        let bgColor: Color = is3DMode ? .red : .black.opacity(0.6)
        return AnyView(
            Button(action: { is3DMode.toggle() }) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(bgColor)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
        )
    }
    
    private func makeCampaignPickerButton() -> some View {
        let isSelected = selectedCampaignId != nil || selectedFarmId != nil
        let iconName = isSelected ? "map.fill" : "map"
        let bgColor: Color = isSelected ? .red : .black.opacity(0.6)
        return AnyView(
            Button(action: { showCampaignPicker = true }) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(bgColor)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
        )
    }
    
    private var mapStyleBinding: Binding<MapStyle> {
        Binding(
            get: { mapStyleMode },
            set: { mapStyleModeRaw = $0.rawValue }
        )
    }
    
    private func handleToggle3D() {
        is3DMode.toggle()
    }
    
    private func handleShowCampaignPicker() {
        showCampaignPicker = true
    }
    
    private func handleShowSessionStart() {
        showSessionStartSheet = true
    }
    
    private var mapContentView: some View {
        MapContentView(
            is3DMode: $is3DMode,
            mapStyleMode: mapStyleBinding,
            campaignPolygon: campaignPolygon,
            campaignMarkers: campaignMarkers,
            farmMarkers: farmMarkers,
            selectedCampaignId: selectedCampaignId,
            selectedFarmId: selectedFarmId,
            onToggle3D: handleToggle3D,
            onShowCampaignPicker: handleShowCampaignPicker,
            onShowSessionStart: handleShowSessionStart
        )
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
                .sheet(isPresented: $showSessionStartSheet) {
                    SessionStartView()
                }
                .sheet(isPresented: $showSessionSummary) {
                    sessionSummarySheet
                }
        )
    }
    
    private func applySelectionChanges<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .onChange(of: selectedCampaignId) { _, _ in
                    handleCampaignIdChange()
                }
                .onChange(of: selectedFarmId) { _, _ in
                    handleFarmIdChange()
                }
        )
    }
    
    private func applyTask<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .task {
                    handleTask()
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
    
    private func applyStyleChanges<V: View>(to view: V) -> AnyView {
        AnyView(
            view
                .onChange(of: mapStyleMode) { oldValue, newValue in
                    handleMapStyleChange(newValue)
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
        let step6 = applyStyleChanges(to: step5)
        return applyNotifications(to: step6)
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
                SessionSummaryView(
                    distance: summaryData.distance,
                    time: summaryData.time,
                    goalType: summaryData.goalType,
                    goalAmount: summaryData.goalAmount
                )
            }
        }
    }
    
    private func handleCampaignIdChange() {
        Task {
            await loadSelectedCampaignOrFarm()
        }
    }
    
    private func handleFarmIdChange() {
        Task {
            await loadSelectedCampaignOrFarm()
        }
    }
    
    private func handleTask() {
        Task {
            await viewModel.loadCampaignsAndFarms()
            await loadMapMarkers()
            locationManager.requestLocation()
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
    
    private func handleMapStyleChange(_ newValue: MapStyle) {
        if let mapView = SimpleMapViewRepresentable.currentMapView {
            mapView.mapboxMap?.loadStyle(newValue.mapboxStyleURI)
        }
    }
    
    private func handleSessionEnded() {
        if let startTime = sessionManager.startTime {
            sessionSummaryData = SessionSummaryData(
                distance: sessionManager.distanceMeters,
                time: sessionManager.elapsedTime,
                goalType: sessionManager.goalType,
                goalAmount: sessionManager.goalAmount,
                pathCoordinates: sessionManager.pathCoordinates
            )
            showSessionSummary = true
        }
    }
    
    private func loadSelectedCampaignOrFarm() async {
        campaignPolygon = nil
        
        if let campaignId = selectedCampaignId {
            // Update map to show campaign buildings in white (using campaign ID)
            if let mapView = SimpleMapViewRepresentable.currentMapView {
                MapController.shared.applyMode(.campaign3D, to: mapView, campaignPolygon: nil, campaignId: campaignId)
            }
        } else if selectedFarmId != nil {
            // TODO: Fetch farm addresses when farm polygon support is added
            print("⚠️ [Map] Farm polygon support coming soon")
        } else {
            // Clear polygon
            if let mapView = SimpleMapViewRepresentable.currentMapView {
                MapController.shared.applyMode(is3DMode ? .black3D : .light, to: mapView, campaignPolygon: nil, campaignId: nil)
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
        
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        // Stop updating after getting location once
        manager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ [LocationManager] Failed to get location: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else if status == .denied || status == .restricted {
            print("⚠️ [LocationManager] Location permission denied")
        }
    }
}

struct SimpleMapViewRepresentable: UIViewRepresentable {
    @Binding var is3DMode: Bool
    @Binding var mapStyleMode: MapStyle
    var campaignPolygon: [CLLocationCoordinate2D]?
    var campaignMarkers: [CampaignMarker]
    var farmMarkers: [FarmMarker]
    
    static weak var currentMapView: MapView?
    
    func makeUIView(context: Context) -> MapView {
        let mapView = MapView(frame: .zero)
        
        // Configure ornaments
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
        mapView.ornaments.options.compass.visibility = .adaptive
        
        // Load initial style from mapStyleMode
        mapView.mapboxMap?.loadStyle(mapStyleMode.mapboxStyleURI)
        
        // Store coordinator and map view reference
        context.coordinator.mapView = mapView
        Self.currentMapView = mapView
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        // Only update 3D if no campaign is selected (MapController handles campaign mode)
        // We need to check if MapController is managing the map by checking if campaign3D mode is active
        // For now, we'll let MapController handle 3D when campaigns are involved
        // SimpleMapViewRepresentable handles 3D for non-campaign cases
        context.coordinator.update3D(enabled: is3DMode)
        
        // Update map style if it changed
        context.coordinator.updateStyle(mapStyleMode)
        
        // Update campaign polygon if provided (legacy support)
        if let polygon = campaignPolygon {
            MapController.shared.applyMode(.campaign3D, to: mapView, campaignPolygon: polygon, campaignId: nil)
        }
        
        // Update markers
        context.coordinator.updateMarkers(campaignMarkers: campaignMarkers, farmMarkers: farmMarkers, on: mapView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(is3DMode: $is3DMode, mapStyleMode: $mapStyleMode)
    }
    
    class Coordinator {
        @Binding var is3DMode: Bool
        @Binding var mapStyleMode: MapStyle
        weak var mapView: MapView?
        private let layerId = "flyr-3d-buildings"
        private var currentStyle: MapStyle?
        private var hasLoadedTargetIcon = false
        
        init(is3DMode: Binding<Bool>, mapStyleMode: Binding<MapStyle>) {
            _is3DMode = is3DMode
            _mapStyleMode = mapStyleMode
        }
        
        func updateMarkers(campaignMarkers: [CampaignMarker], farmMarkers: [FarmMarker], on mapView: MapView) {
            // Load target icon if not already loaded
            if !hasLoadedTargetIcon, let map = mapView.mapboxMap {
                loadTargetIcon(to: map)
            }
            
            // Update markers
            MapMarkersManager.shared.addCampaignMarkers(campaigns: campaignMarkers, to: mapView)
            MapMarkersManager.shared.addFarmMarkers(farms: farmMarkers, to: mapView)
        }
        
        private func loadTargetIcon(to map: MapboxMap) {
            // Markers now use circle layers instead of icon images
            // No need to load custom icons
            hasLoadedTargetIcon = true
        }
        
        func updateStyle(_ style: MapStyle) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap,
                  currentStyle != style else { return }
            
            currentStyle = style
            map.loadStyle(style.mapboxStyleURI)
            
            // If 3D mode is enabled, re-add the 3D layer with the correct color after style loads
            if is3DMode {
                map.onMapLoaded.observeNext { [weak self] _ in
                    guard let self = self else { return }
                    self.add3DLayer(to: map, mapView: mapView)
                }
            }
        }
        
        func update3D(enabled: Bool) {
            guard let mapView = mapView,
                  let map = mapView.mapboxMap else { return }
            
            // Remove existing layer if it exists
            if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                try? map.removeLayer(withId: layerId)
            }
            
            if enabled {
                // Wait for map to be ready
                if map.isStyleLoaded {
                    add3DLayer(to: map, mapView: mapView)
                } else {
                    map.onMapLoaded.observeNext { [weak self] _ in
                        self?.add3DLayer(to: map, mapView: mapView)
                    }
                }
            } else {
                // Reset camera pitch to 0
                let currentCamera = map.cameraState
                let cameraOptions = CameraOptions(
                    center: currentCamera.center,
                    zoom: currentCamera.zoom,
                    pitch: 0
                )
                map.setCamera(to: cameraOptions)
            }
        }
        
        private func add3DLayer(to map: MapboxMap, mapView: MapView) {
            // Remove existing layer if it exists
            if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                try? map.removeLayer(withId: layerId)
            }
            
            do {
                var layer = FillExtrusionLayer(id: layerId, source: "composite")
                layer.sourceLayer = "building"
                layer.minZoom = 13
                layer.fillExtrusionOpacity = .constant(0.9)
                layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
                layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
                // Use black for dark mode, white for light mode
                let buildingColor: UIColor = mapStyleMode == .dark ? .black : .white
                layer.fillExtrusionColor = .constant(StyleColor(buildingColor))
                
                try map.addLayer(layer)
                
                // Tilt camera for 3D view
                let currentCamera = map.cameraState
                let cameraOptions = CameraOptions(
                    center: currentCamera.center,
                    zoom: currentCamera.zoom,
                    pitch: 60
                )
                map.setCamera(to: cameraOptions)
            } catch {
                print("❌ [3D] Failed to add 3D buildings: \(error)")
            }
        }
    }
}
