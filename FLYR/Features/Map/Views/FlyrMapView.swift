import SwiftUI
import MapboxMaps
import CoreLocation
import Supabase

/// Main FLYR map view with 4 visual modes and 3D building support
struct FlyrMapView: View {
    @State private var mode: MapMode = .light
    @State private var mapView: MapView?
    @StateObject private var locationManager = LocationManager()
    @State private var hasCenteredOnLocation = false
    
    /// Optional campaign polygon for Campaign 3D mode (legacy)
    var campaignPolygon: [CLLocationCoordinate2D]? = nil
    
    /// Optional campaign ID for Campaign 3D mode (preferred - shows buildings for campaign addresses)
    var campaignId: UUID? = nil
    
    /// Optional initial center coordinate
    var centerCoordinate: CLLocationCoordinate2D? = nil
    
    /// Optional initial zoom level
    var zoomLevel: Double = 14
    
    var body: some View {
        ZStack(alignment: .top) {
            // Map view
            if let mapView = mapView {
                MapboxMapViewRepresentable(
                    mapView: mapView,
                    mode: mode,
                    campaignPolygon: campaignPolygon,
                    campaignId: campaignId
                )
            } else {
                // Placeholder while map initializes
                Color(.systemBackground)
                    .onAppear {
                        initializeMap()
                    }
            }
            
            // Mode toggle overlay
            VStack {
                MapModeToggle(mode: $mode)
                    .padding(.top, 50)
                Spacer()
            }
        }
        .onChange(of: mode) { oldMode, newMode in
            if let mapView = mapView {
                MapController.shared.applyMode(newMode, to: mapView, campaignPolygon: campaignPolygon, campaignId: campaignId)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            handleLocationChange(newLocation)
        }
    }
    
    private func initializeMap() {
        let frame = UIScreen.main.bounds
        let newMapView = MapView(frame: frame)
        
        // Configure map ornaments
        newMapView.ornaments.options.scaleBar.visibility = .hidden
        newMapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
        newMapView.ornaments.options.compass.visibility = .adaptive
        
        // Load initial style immediately (use default Mapbox style based on current mode)
        if let map = newMapView.mapboxMap {
            let initialStyle = MapTheme.styleURI(for: mode)
            map.loadStyle(initialStyle)
        }
        
        // Set initial camera position
        // If centerCoordinate is provided, use it; otherwise use default (will be updated when location is available)
        let defaultCenter = centerCoordinate ?? CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)
        let cameraOptions = CameraOptions(
            center: defaultCenter,
            zoom: zoomLevel
        )
        newMapView.mapboxMap?.setCamera(to: cameraOptions)
        
        self.mapView = newMapView
        
        // Request user location if centerCoordinate is not provided
        if centerCoordinate == nil {
            locationManager.requestLocation()
        } else {
            // If centerCoordinate is provided, mark as centered so we don't override it
            hasCenteredOnLocation = true
        }
        
        // Apply initial mode after map loads (to add 3D layers if needed)
        newMapView.mapboxMap?.onMapLoaded.observeNext { _ in
            Task { @MainActor in
                MapController.shared.applyMode(mode, to: newMapView, campaignPolygon: campaignPolygon, campaignId: campaignId)
            }
        }
    }
    
    private func handleLocationChange(_ newLocation: CLLocation?) {
        // Only center on location once, and only if centerCoordinate was not provided
        guard let location = newLocation,
              !hasCenteredOnLocation,
              centerCoordinate == nil,
              let mapView = mapView else {
            return
        }
        
        // Center map on user's location
        let cameraOptions = CameraOptions(
            center: location.coordinate,
            zoom: zoomLevel
        )
        mapView.mapboxMap?.setCamera(to: cameraOptions)
        hasCenteredOnLocation = true
        
        print("📍 [FlyrMapView] Centered map on user location: \(location.coordinate)")
    }
}

/// UIViewRepresentable wrapper for Mapbox MapView
struct MapboxMapViewRepresentable: UIViewRepresentable {
    let mapView: MapView
    var mode: MapMode
    var campaignPolygon: [CLLocationCoordinate2D]? = nil
    var campaignId: UUID? = nil
    
    func makeUIView(context: Context) -> MapView {
        // Set up coordinator with map view reference and campaign ID
        context.coordinator.mapView = mapView
        context.coordinator.campaignId = campaignId
        
        // Add tap gesture recognizer for building detection
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        mapView.addGestureRecognizer(tapGesture)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        // Update campaign ID if it changed
        context.coordinator.campaignId = campaignId
        
        // Mode changes are handled by FlyrMapView's onChange
        // This method is called when the view updates, but we handle mode changes
        // through the parent view's state management
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        weak var mapView: MapView?
        var campaignId: UUID? = nil
        private var currentlySelectedBuildingId: String?
        private var currentlySelectedSourceId: String?
        private var currentlySelectedSourceLayerId: String?
        
        @objc func handleMapTap(_ sender: UITapGestureRecognizer) {
            guard let mapView = self.mapView else { return }
            
            let point = sender.location(in: mapView)
            
            // Query for building features at tap point (use a small box around the point)
            let box = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
            
            // Query layers in priority order to determine which layer was hit
            let layerPriority = [
                ("campaign-3d", "campaign-buildings", nil),
                ("flyr-3d-buildings", "composite", "building"),
                ("crushed-buildings", "composite", "building"),
                ("session-3d-buildings", "composite", "building"),
                ("building", "composite", "building")
            ]
            
            // Try each layer in priority order
            func queryNextLayer(index: Int) {
                guard index < layerPriority.count else { return }
                
                let (layerId, sourceId, sourceLayerId) = layerPriority[index]
                let options = RenderedQueryOptions(layerIds: [layerId], filter: nil)
                
                mapView.mapboxMap.queryRenderedFeatures(with: box, options: options) { [weak self] result in
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let features):
                        if let firstFeature = features.first {
                            // Found a building in this layer
                            let feature = firstFeature.queriedFeature.feature
                            self.handleBuildingTap(
                                feature: feature,
                                sourceId: sourceId,
                                sourceLayerId: sourceLayerId
                            )
                        } else {
                            // No building in this layer, try next
                            queryNextLayer(index: index + 1)
                        }
                    case .failure:
                        // Error querying this layer, try next
                        queryNextLayer(index: index + 1)
                    }
                }
            }
            
            // Start querying from the first layer
            queryNextLayer(index: 0)
        }
        
        private func determineSourceInfo(for layerId: String) -> (sourceId: String, sourceLayerId: String?) {
            switch layerId {
            case "flyr-3d-buildings", "crushed-buildings", "building":
                return ("composite", "building")
            case "campaign-3d":
                return ("campaign-buildings", nil)
            case "session-3d-buildings":
                return ("composite", "building")
            default:
                return ("composite", "building")
            }
        }
        
        private func handleBuildingTap(feature: Feature, sourceId: String, sourceLayerId: String?) {
            // Extract building ID from feature properties
            var buildingId: String?
            var addressId: UUID?
            
            if let props = feature.properties {
                // Try "id" as string
                if case let .string(idValue)? = props["id"] {
                    buildingId = idValue
                }
                // Try "id" as number
                else if case let .number(idNum)? = props["id"] {
                    buildingId = String(Int(idNum))
                }
                // Try "building_id"
                else if case let .string(buildingIdValue)? = props["building_id"] {
                    buildingId = buildingIdValue
                }
                
                // Extract address_id (UUID from campaign_addresses.id)
                if case let .string(addressIdString)? = props["address_id"] {
                    addressId = UUID(uuidString: addressIdString)
                }
            }
            
            guard let buildingId = buildingId else {
                print("⚠️ [BuildingTap] No building ID found on tapped feature (source: \(sourceId), has properties: \(feature.properties != nil))")
                return
            }
            
            print("🏗️ [BuildingTap] Building tapped: \(buildingId) from source: \(sourceId), sourceLayer: \(sourceLayerId ?? "none")")
            
            // Update building color using feature-state
            setBuildingSelectedState(
                buildingId: buildingId,
                sourceId: sourceId,
                sourceLayerId: sourceLayerId
            )
            
            // Log visit to Supabase if this is a campaign building with address_id
            if let addressId = addressId, let campaignId = campaignId {
                // This is a campaign building - log the visit
                // TODO: Get sessionId from SessionManager when active session tracking is implemented
                // For now, sessions are only saved at the end, so we pass nil
                VisitsAPI.shared.logBuildingTouch(
                    addressId: addressId,
                    campaignId: campaignId,
                    buildingId: buildingId,
                    sessionId: nil
                )
                
                // Mark address as visited
                VisitsAPI.shared.markAddressVisited(addressId: addressId)
            } else if addressId == nil {
                // Log warning if address_id is missing for a campaign building
                if campaignId != nil {
                    print("⚠️ [BuildingTap] Campaign building tapped but address_id not found in feature properties")
                }
            }
        }
        
        private func setBuildingSelectedState(buildingId: String, sourceId: String, sourceLayerId: String?) {
            guard let mapView = self.mapView else { return }
            
            // Clear previous selection
            if let previousId = currentlySelectedBuildingId,
               let previousSourceId = currentlySelectedSourceId,
               let previousSourceLayerId = currentlySelectedSourceLayerId {
                let prevState: [String: Any] = ["selected": false]
                mapView.mapboxMap.setFeatureState(
                    sourceId: previousSourceId,
                    sourceLayerId: previousSourceLayerId,
                    featureId: previousId,
                    state: prevState
                ) { result in
                    if case .failure(let error) = result {
                        print("⚠️ [BuildingTap] Error clearing previous selection: \(error)")
                    }
                }
            }
            
            // Set new selection
            let newState: [String: Any] = ["selected": true]
            if let sourceLayerId = sourceLayerId {
                mapView.mapboxMap.setFeatureState(
                    sourceId: sourceId,
                    sourceLayerId: sourceLayerId,
                    featureId: buildingId,
                    state: newState
                ) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.currentlySelectedBuildingId = buildingId
                        self.currentlySelectedSourceId = sourceId
                        self.currentlySelectedSourceLayerId = sourceLayerId
                        print("✅ [BuildingTap] Building \(buildingId) highlighted")
                    case .failure(let error):
                        print("❌ [BuildingTap] Error setting building feature state: \(error)")
                    }
                }
            } else {
                // For GeoJSON sources without sourceLayer, use feature ID directly
                mapView.mapboxMap.setFeatureState(
                    sourceId: sourceId,
                    sourceLayerId: nil,
                    featureId: buildingId,
                    state: newState
                ) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        self.currentlySelectedBuildingId = buildingId
                        self.currentlySelectedSourceId = sourceId
                        self.currentlySelectedSourceLayerId = sourceLayerId
                        print("✅ [BuildingTap] Building \(buildingId) highlighted")
                    case .failure(let error):
                        print("❌ [BuildingTap] Error setting building feature state: \(error)")
                    }
                }
            }
        }
        
    }
}

