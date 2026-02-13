import SwiftUI
import UIKit
import MapboxMaps
import Combine
import CoreLocation

// MARK: - Display Mode
/// Controls what's visible on the campaign map
enum DisplayMode: String, CaseIterable, Identifiable {
    case buildings = "Buildings"
    case addresses = "Addresses"
    case both = "Both"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .buildings: return "building.2"
        case .addresses: return "mappin"
        case .both: return "square.stack.3d.up"
        }
    }
    
    var description: String {
        switch self {
        case .buildings: return "3D building footprints"
        case .addresses: return "Address pin locations"
        case .both: return "Buildings and addresses"
        }
    }
}

// MARK: - Display Mode Toggle
struct DisplayModeToggle: View {
    @Binding var mode: DisplayMode
    var onChange: ((DisplayMode) -> Void)?
    
    var body: some View {
        VStack(spacing: 4) {
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
            
            Text(mode.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
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
    @State private var showGestureInfoSheet = false
    
    // Display mode (Buildings/Addresses/Both)
    @State private var displayMode: DisplayMode = .both

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                mapLayer(geometry: geometry)
                sessionStatsOverlay
                overlayUI
                legendAndInfoOverlay
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
        .onAppear {
            loadCampaignData()
            setupRealTimeSubscription()
        }
        .onChange(of: campaignId) { _, _ in
            hasFlownToCampaign = false
        }
        .onDisappear {
            Task {
                await statsSubscriber?.unsubscribe()
            }
        }
        .onChange(of: featuresService.buildings?.features.count ?? 0) { _, _ in
            updateMapData()
        }
        .onChange(of: featuresService.addresses?.features.count ?? 0) { _, _ in
            updateMapData()
        }
        .onChange(of: sessionManager.pathCoordinates.count) { _, _ in
            updateSessionPathOnMap()
        }
        .sheet(isPresented: $showGestureInfoSheet) {
            MapGestureInfoSheet()
        }
        .sheet(isPresented: $showTargetsSheet) {
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
                    Task {
                        try? await sessionManager.undoCompletion(buildingId)
                    }
                }
            )
        }
        .sheet(isPresented: $showLeadCaptureSheet, onDismiss: { selectedBuilding = nil }) {
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
                        try? await sessionManager.completeBuilding(gersIdString)
                        await MainActor.run {
                            updateBuildingColorAfterComplete(gersId: gersIdString)
                        }
                        HapticManager.success()
                    },
                    onJustMark: {
                        HapticManager.soft()
                        try? await sessionManager.completeBuilding(gersIdString)
                        await MainActor.run {
                            updateBuildingColorAfterComplete(gersId: gersIdString)
                        }
                    },
                    onDismiss: {
                        showLeadCaptureSheet = false
                        selectedBuilding = nil
                    }
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
    private var sessionStatsOverlay: some View {
        if sessionManager.sessionId != nil {
            VStack(spacing: 0) {
                StatsCardView(
                    sessionManager: sessionManager,
                    isExpanded: $statsExpanded,
                    dragOffset: $dragOffset
                )
                .padding(.top, 8)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 100 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    statsExpanded = false
                                    dragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                Spacer()
            }
            .transition(.move(edge: .top))
        }
    }

    @ViewBuilder
    private var overlayUI: some View {
        VStack {
            // Display mode toggle at top
            DisplayModeToggle(mode: $displayMode) { newMode in
                updateLayerVisibility(for: newMode)
            }
            .padding(.top, 8)
            
            Spacer()
            
            if sessionManager.sessionId == nil,
               let features = featuresService.buildings?.features,
               !features.isEmpty,
               let campId = UUID(uuidString: campaignId) {
                Button {
                    HapticManager.medium()
                    startBuildingSession(campaignId: campId, features: features)
                } label: {
                    Label("Start session", systemImage: "play.circle.fill")
                        .font(.flyrSubheadline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 8)
            }
        }
    }
    
    /// Update layer visibility based on display mode
    private func updateLayerVisibility(for mode: DisplayMode) {
        guard let manager = layerManager else { return }
        
        switch mode {
        case .buildings:
            manager.includeBuildingsLayer = true
            manager.includeAddressesLayer = false
            try? mapView?.mapboxMap.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            try? mapView?.mapboxMap.updateLayer(withId: MapLayerManager.addressesLayerId, type: CircleLayer.self) { $0.visibility = .constant(.none) }
        case .addresses:
            manager.includeBuildingsLayer = false
            manager.includeAddressesLayer = true
            try? mapView?.mapboxMap.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.none) }
            try? mapView?.mapboxMap.updateLayer(withId: MapLayerManager.addressesLayerId, type: CircleLayer.self) { $0.visibility = .constant(.visible) }
        case .both:
            manager.includeBuildingsLayer = true
            manager.includeAddressesLayer = true
            try? mapView?.mapboxMap.updateLayer(withId: MapLayerManager.buildingsLayerId, type: FillExtrusionLayer.self) { $0.visibility = .constant(.visible) }
            try? mapView?.mapboxMap.updateLayer(withId: MapLayerManager.addressesLayerId, type: CircleLayer.self) { $0.visibility = .constant(.visible) }
        }
        
        print("🗺️ [CampaignMap] Display mode changed to: \(mode)")
    }

    @ViewBuilder
    private var legendAndInfoOverlay: some View {
        if sessionManager.sessionId == nil {
            VStack(alignment: .trailing, spacing: 8) {
                MapLegendView(
                    showQrScanned: $showQrScanned,
                    showConversations: $showConversations,
                    showTouched: $showTouched,
                    showUntouched: $showUntouched,
                    onFilterChanged: updateFilters
                )
                Button {
                    showGestureInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    @ViewBuilder
    private var locationCardOverlay: some View {
        if showLocationCard,
           let building = selectedBuilding,
           let gersIdString = building.gersId,
           let gersId = UUID(uuidString: gersIdString),
           let campId = UUID(uuidString: campaignId) {
            VStack {
                Spacer()
                LocationCardView(
                    gersId: gersId,
                    campaignId: campId,
                    addressId: building.addressId.flatMap { UUID(uuidString: $0) },
                    addressText: building.addressText,
                    onClose: {
                        showLocationCard = false
                        selectedBuilding = nil
                    },
                    onStatusUpdated: { addressId, status in
                        if let map = mapView {
                            MapController.shared.applyStatusFeatureState(statuses: [addressId.uuidString: status], mapView: map)
                        }
                        let layerStatus: String = (status == .talked || status == .appointment) ? "hot" : "visited"
                        layerManager?.updateBuildingState(gersId: gersIdString, status: layerStatus, scansTotal: 0)
                    }
                )
                .padding()
            }
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
        manager.includeAddressesLayer = false  // Hide purple pins; keep buildings and address data/logic
        self.layerManager = manager

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
        
        if let addressesData = featuresService.addressesAsGeoJSONData() {
            manager.updateAddresses(addressesData)
        }
        
        if let roadsData = featuresService.roadsAsGeoJSONData() {
            manager.updateRoads(roadsData)
        }
        
        // Apply current display mode visibility
        updateLayerVisibility(for: displayMode)
        
        if let map = mapView {
            flyToCampaignCenterIfNeeded(map: map)
        }
    }

    private static let sessionLineSourceId = "session-line-source"
    private static let sessionLineLayerId = "session-line-layer"

    /// Add session path source and red line layer (breadcrumb trail during building session).
    private func addSessionPathLayersIfNeeded(map: MapView) {
        guard let mapboxMap = map.mapboxMap else { return }
        do {
            var source = GeoJSONSource(id: Self.sessionLineSourceId)
            source.data = .featureCollection(FeatureCollection(features: []))
            try mapboxMap.addSource(source)
            var lineLayer = LineLayer(id: Self.sessionLineLayerId, source: Self.sessionLineSourceId)
            lineLayer.lineColor = .constant(StyleColor(.red))
            lineLayer.lineWidth = .constant(5.0)
            lineLayer.lineOpacity = .constant(1.0)
            lineLayer.lineJoin = .constant(.round)
            lineLayer.lineCap = .constant(.round)
            try mapboxMap.addLayer(lineLayer)
        } catch {
            print("⚠️ [CampaignMap] Failed to add session path layer: \(error)")
        }
    }

    /// Update the session path line from current pathCoordinates (so red breadcrumb shows during building session).
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

        manager.getBuildingAt(point: point) { building in
            guard let building = building else { return }

            selectedBuilding = building
            withAnimation {
                showLocationCard = true
            }
        }
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
    
    private func updateBuildingColor(gersId: UUID, status: String, scansTotal: Int, qrScanned: Bool) {
        guard layerManager != nil else { return }
        // TODO: Update the building's feature state in MapLayerManager
        print("📊 Building stats updated: GERS=\(gersId), status=\(status), scans=\(scansTotal)")
        
        // TODO: Implement feature state update in MapLayerManager
        // manager.updateFeatureState(gersId: gersId, status: status, scansTotal: scansTotal)
    }
    
    @State private var cancellables = Set<AnyCancellable>()
}

// MARK: - Mapbox Map Representable

struct CampaignMapboxMapViewRepresentable: UIViewRepresentable {
    var preferredSize: CGSize = CGSize(width: 320, height: 260)
    var useDarkStyle: Bool = false
    let onMapReady: (MapView) -> Void
    let onTap: (CGPoint) -> Void

    private static let lightStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6z0dhg002301qo9xxc08k4")!
    private static let darkStyleURI = StyleURI(rawValue: "mapbox://styles/fliper27/cml6zc5pq002801qo4lh13o19")!

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
        // Force layout so map renders when size is set (e.g. inside ScrollView)
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
                color: Color(UIColor(hex: "#eab308")!),
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
    let gersId: UUID
    let campaignId: UUID
    /// Campaign address ID from tapped building (used for direct lookup so card shows linked state)
    let addressId: UUID?
    /// Address from tapped building (shown immediately)
    let addressText: String?
    let onClose: () -> Void
    /// Called after status is saved to Supabase so the map can update building color immediately
    var onStatusUpdated: ((UUID, AddressStatus) -> Void)?
    
    @StateObject private var dataService: BuildingDataService
    @StateObject private var voiceRecorder = VoiceRecorderManager()
    @State private var nameText: String = ""
    @State private var notesText: String = ""
    @State private var showAddResidentSheet = false
    @State private var addResidentAddress: ResolvedAddress?
    @State private var isUploadingVoiceNote = false
    @State private var voiceNoteError: String?
    
    init(gersId: UUID, campaignId: UUID, addressId: UUID? = nil, addressText: String? = nil, onClose: @escaping () -> Void, onStatusUpdated: ((UUID, AddressStatus) -> Void)? = nil) {
        self.gersId = gersId
        self.campaignId = campaignId
        self.addressId = addressId
        self.addressText = addressText
        self.onClose = onClose
        self.onStatusUpdated = onStatusUpdated
        _dataService = StateObject(wrappedValue: BuildingDataService(supabase: SupabaseManager.shared.client))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Close button at top
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            
            // Address from tap (shown immediately until we have resolved content)
            if let address = addressText, !address.isEmpty,
               dataService.buildingData.isLoading || dataService.buildingData.error != nil || !dataService.buildingData.addressLinked {
                Text(address)
                    .font(.flyrSubheadline)
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            
            if dataService.buildingData.isLoading {
                loadingView
            } else if let error = dataService.buildingData.error {
                errorView(error: error)
            } else if !dataService.buildingData.addressLinked {
                unlinkedBuildingView
            } else if let address = dataService.buildingData.address {
                mainContentView(address: address)
            }
        }
        .frame(width: 320)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 20)
        .task {
            await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId)
        }
        .sheet(isPresented: $showAddResidentSheet, onDismiss: { addResidentAddress = nil }) {
            if let address = addResidentAddress {
                AddResidentSheetView(
                    address: address,
                    campaignId: campaignId,
                    onSave: {
                        dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                        dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
                        await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id)
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
    }
    
    // MARK: - Loading State
    
    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView()
            Text("Loading...")
                .foregroundColor(.gray)
            nameRow
        }
        .frame(minHeight: 200)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Error State
    
    private func errorView(error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.flyrTitle2)
                VStack(alignment: .leading) {
                    Text("Error loading data")
                        .fontWeight(.semibold)
                    Text(error.localizedDescription)
                        .font(.flyrCaption)
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            
            nameRow
            
            Button("Retry") {
                Task {
                    await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: addressId)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    // MARK: - Unlinked Building State
    
    private var unlinkedBuildingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.slash")
                    .foregroundColor(.gray)
                    .font(.flyrTitle2)
                VStack(alignment: .leading) {
                    Text("Unlinked Building")
                        .fontWeight(.semibold)
                    Text("No address data found for this building")
                        .font(.flyrCaption)
                        .foregroundColor(.gray)
                }
            }
            
            Text("GERS: \(gersId.uuidString)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.middle)
            
            nameRow
        }
        .padding()
    }
    
    // MARK: - Name Row (spot to add a name)
    
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
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(address.displayStreet)
                    .font(.flyrHeadline)
                    .lineLimit(1)
                
                Text([address.locality, address.region, address.postalCode]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", "))
                    .font(.flyrCaption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                statusBadge
                if let lead = dataService.buildingData.leadStatus, !lead.isEmpty {
                    Text(leadStatusDisplay(lead))
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 12)
            
            // Content Rows
            VStack(spacing: 12) {
                nameRow
                    .onAppear {
                        if nameText.isEmpty {
                            if let resident = dataService.buildingData.primaryResident {
                                nameText = resident.displayName
                            } else if let contact = dataService.buildingData.contactName, !contact.isEmpty {
                                nameText = contact
                            }
                        }
                    }
                residentsRow(address: address)
                
                addNotesSection
                
                if let notes = dataService.buildingData.firstNotes {
                    notesSection(notes: notes)
                }
                
                qrStatusRow
            }
            .padding(.horizontal)
            
            // Action Footer
            Divider()
                .padding(.top)
            
            HStack(spacing: 8) {
                Button(action: { onClose(); logVisitStatus(address, status: .delivered) }) {
                    Image(systemName: "door.left.hand.closed")
                        .font(.flyrSubheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Knocked")
                
                Button(action: { onClose(); logVisitStatus(address, status: .talked) }) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.flyrSubheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Conversation")
                
                Button(action: { onClose(); logVisitStatus(address, status: .appointment) }) {
                    Image(systemName: "calendar")
                        .font(.flyrSubheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Appointment")
                
                voiceNoteButton(address: address)
            }
            .padding()
        }
    }
    
    private func voiceNoteButton(address: ResolvedAddress) -> some View {
        Group {
            if voiceRecorder.isRecording {
                Button(action: { stopAndUploadVoiceNote(address: address) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                        Text("\(Int(voiceRecorder.recordingDuration))s")
                            .font(.flyrCaption)
                            .foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isUploadingVoiceNote)
                .accessibilityLabel("Stop and save voice note")
            } else {
                Button(action: { startVoiceNote() }) {
                    Image(systemName: "mic.fill")
                        .font(.flyrSubheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isUploadingVoiceNote)
                .accessibilityLabel("Record voice note")
            }
        }
    }
    
    private func startVoiceNote() {
        Task {
            let granted = await voiceRecorder.requestPermission()
            guard granted else {
                voiceNoteError = "Microphone access is required for voice notes."
                return
            }
            _ = voiceRecorder.startRecording()
        }
    }
    
    private func stopAndUploadVoiceNote(address: ResolvedAddress) {
        guard let url = voiceRecorder.stopRecording() else { return }
        isUploadingVoiceNote = true
        Task {
            defer { Task { @MainActor in isUploadingVoiceNote = false } }
            do {
                let result = try await VoiceNoteAPI.processVoiceNote(
                    audioFileURL: url,
                    addressId: address.id,
                    campaignId: campaignId
                )
                try? FileManager.default.removeItem(at: url)
                let mappedStatus = mapLeadStatusToAddressStatus(result.leadStatus ?? "follow_up")
                dataService.clearCacheEntry(gersId: gersId, campaignId: campaignId)
                dataService.clearCacheEntry(addressId: address.id, campaignId: campaignId)
                await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id)
                await MainActor.run {
                    onStatusUpdated?(address.id, mappedStatus)
                }
            } catch {
                voiceNoteError = error.localizedDescription
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
    
    private var qrStatusRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(getQRStatusColor().opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "qrcode")
                    .foregroundColor(getQRStatusColor())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dataService.buildingData.qrStatus.statusText)
                    .fontWeight(.medium)
                
                Text(dataService.buildingData.qrStatus.subtext)
                    .font(.flyrCaption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if dataService.buildingData.qrStatus.isScanned {
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
    
    // MARK: - Helper Methods
    
    private func getResidentsText() -> String {
        let residents = dataService.buildingData.residents
        if residents.isEmpty { return "No residents" }
        if residents.count == 1 { return residents[0].displayName }
        return "\(residents[0].displayName) + \(residents.count - 1) other\(residents.count > 2 ? "s" : "")"
    }
    
    private func getStatusText() -> String {
        let qrStatus = dataService.buildingData.qrStatus
        if qrStatus.totalScans > 0 { return "Scanned" }
        if qrStatus.hasFlyer { return "Target" }
        return "New"
    }
    
    private func getStatusColor() -> Color {
        let qrStatus = dataService.buildingData.qrStatus
        if qrStatus.totalScans > 0 { return .blue }
        if qrStatus.hasFlyer { return .gray.opacity(0.6) }
        return .gray.opacity(0.4)
    }
    
    private func getQRStatusColor() -> Color {
        let qrStatus = dataService.buildingData.qrStatus
        if qrStatus.hasFlyer {
            return qrStatus.totalScans > 0 ? .green : .flyrPrimary
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
                await dataService.fetchBuildingData(gersId: gersId, campaignId: campaignId, addressId: address.id)
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

struct BuildingStatusBadge: View {
    let status: String
    let scansTotal: Int
    
    var color: Color {
        if scansTotal > 0 {
            return Color(UIColor(hex: "#eab308")!)
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
