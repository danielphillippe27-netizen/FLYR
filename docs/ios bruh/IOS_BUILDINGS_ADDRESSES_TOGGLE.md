# iOS Buildings & Addresses with Toggle

Complete implementation for fetching buildings from S3, addresses from Supabase, and toggling between them on the map.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         iOS MAP VIEW ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────┐         ┌─────────────────┐                          │
│   │  BUILDINGS MODE │         │  ADDRESSES MODE │                          │
│   │  (3D Footprints)│◄───────►│  (Pin Points)   │                          │
│   └────────┬────────┘ Toggle  └────────┬────────┘                          │
│            │                           │                                    │
│            ▼                           ▼                                    │
│   ┌─────────────────┐         ┌─────────────────┐                          │
│   │ GET /buildings  │         │ GET /addresses  │                          │
│   │ Returns GeoJSON │         │ Returns GeoJSON │                          │
│   │ (from S3)       │         │ (from Supabase) │                          │
│   └────────┬────────┘         └────────┬────────┘                          │
│            │                           │                                    │
│            ▼                           ▼                                    │
│   ┌─────────────────┐         ┌─────────────────┐                          │
│   │ FillExtrusion   │         │ SymbolLayer     │                          │
│   │ (3D Buildings)  │         │ (Address Pins)  │                          │
│   │ - height from   │         │ - bearing from  │                          │
│   │   properties    │         │   properties    │                          │
│   └─────────────────┘         └─────────────────┘                          │
│                                                                             │
│   SHARED: Realtime subscription to building_stats for color updates        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Complete Swift Implementation

### 1. Models

```swift
import Foundation
import CoreLocation

// MARK: - Building Models (from S3 via API)

struct BuildingFeature: Codable {
    let type: String
    let id: String           // GERS ID
    let geometry: PolygonGeometry
    let properties: BuildingProperties
}

struct PolygonGeometry: Codable {
    let type: String
    let coordinates: [[[[Double]]]]  // GeoJSON: [[[lon, lat]]]
}

struct BuildingProperties: Codable {
    let gersId: String
    let heightM: Double
    let levels: Int?
    let addressText: String?
    let featureStatus: String  // "linked" or "orphan_building"
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case heightM = "height_m"
        case levels
        case addressText = "address_text"
        case featureStatus = "feature_status"
    }
}

struct BuildingsResponse: Codable {
    let type: String
    let features: [BuildingFeature]
}

// MARK: - Address Models (from Supabase via API)

struct AddressFeature: Codable {
    let type: String
    let geometry: PointGeometry
    let properties: AddressProperties
}

struct PointGeometry: Codable {
    let type: String
    let coordinates: [Double]  // [lon, lat]
}

struct AddressProperties: Codable {
    let id: String
    let formatted: String
    let visited: Bool
    let houseBearing: Double?   // For rotating house icon to face street
    let roadBearing: Double?
    
    enum CodingKeys: String, CodingKey {
        case id, formatted, visited
        case houseBearing = "house_bearing"
        case roadBearing = "road_bearing"
    }
}

struct AddressesResponse: Codable {
    let type: String
    let features: [AddressFeature]
}

// MARK: - Building Stats (from Supabase Realtime)

struct BuildingStats: Codable {
    let gersId: String
    let status: String
    let scansTotal: Int
    
    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case status
        case scansTotal = "scans_total"
    }
}

// MARK: - Map Mode Enum

enum MapDisplayMode {
    case buildings   // 3D building footprints
    case addresses   // Address pins with rotation
    case both        // Show both (buildings + addresses)
}
```

### 2. Service Layer

```swift
import Foundation

class CampaignMapService {
    static let shared = CampaignMapService()
    private let baseURL = "https://flyrpro.app/api"
    
    // MARK: - Fetch Buildings (from S3 via API)
    
    func fetchBuildings(campaignId: String) async throws -> [BuildingFeature] {
        let url = URL(string: "\(baseURL)/campaigns/\(campaignId)/buildings")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MapError.fetchFailed("Buildings request failed")
        }
        
        // The API returns a FeatureCollection or just an array of features
        // Try both formats
        if let featureCollection = try? JSONDecoder().decode(BuildingsResponse.self, from: data) {
            return featureCollection.features
        }
        
        // Try decoding as array directly
        return try JSONDecoder().decode([BuildingFeature].self, from: data)
    }
    
    // MARK: - Fetch Addresses (from Supabase via API)
    
    func fetchAddresses(campaignId: String) async throws -> [AddressFeature] {
        let url = URL(string: "\(baseURL)/campaigns/\(campaignId)/addresses")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MapError.fetchFailed("Addresses request failed")
        }
        
        // Try FeatureCollection first
        if let featureCollection = try? JSONDecoder().decode(AddressesResponse.self, from: data) {
            return featureCollection.features
        }
        
        // Try array directly
        return try JSONDecoder().decode([AddressFeature].self, from: data)
    }
    
    // MARK: - Fetch Roads (for routing visualization)
    
    func fetchRoads(campaignId: String) async throws -> Data {
        let url = URL(string: "\(baseURL)/campaigns/\(campaignId)/roads")!
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MapError.fetchFailed("Roads request failed")
        }
        
        return data
    }
}

enum MapError: Error {
    case fetchFailed(String)
    case decodingFailed
    case invalidGeometry
}
```

### 3. Map View Controller with Toggle

```swift
import UIKit
import MapboxMaps
import Supabase

class CampaignMapViewController: UIViewController {
    
    // MARK: - UI Components
    
    var mapView: MapView!
    
    lazy var modeToggle: UISegmentedControl = {
        let items = ["Buildings", "Addresses", "Both"]
        let control = UISegmentedControl(items: items)
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.backgroundColor = .systemBackground
        return control
    }()
    
    lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    // MARK: - Data
    
    var campaignId: String!
    var currentMode: MapDisplayMode = .buildings
    
    var buildingFeatures: [BuildingFeature] = []
    var addressFeatures: [AddressFeature] = []
    
    // Cached Mapbox sources
    var buildingSourceId = "campaign-buildings"
    var addressSourceId = "campaign-addresses"
    var buildingLayerId = "buildings-3d"
    var addressLayerId = "address-pins"
    
    // Supabase realtime
    var supabase: SupabaseClient!
    var realtimeChannel: RealtimeChannel?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupMap()
        setupSupabase()
        loadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        realtimeChannel?.unsubscribe()
    }
    
    // MARK: - Setup
    
    func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(modeToggle)
        view.addSubview(loadingIndicator)
        
        NSLayoutConstraint.activate([
            modeToggle.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            modeToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            modeToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            modeToggle.heightAnchor.constraint(equalToConstant: 36),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    func setupMap() {
        let options = MapInitOptions(
            cameraOptions: CameraOptions(zoom: 15, pitch: 45)
        )
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(mapView, at: 0)
        
        // Configure 3D light for building extrusion
        var light = Light()
        light.anchor = .map
        light.position = .constant([1.5, 90, 80])
        light.intensity = .constant(0.5)
        try? mapView.mapboxMap.style.setLight(light)
    }
    
    func setupSupabase() {
        supabase = SupabaseClient(
            supabaseURL: URL(string: "https://kfnsnwqylsdsbgnwgxva.supabase.co")!,
            supabaseKey: "your-anon-key"
        )
    }
    
    // MARK: - Data Loading
    
    func loadData() {
        loadingIndicator.startAnimating()
        
        Task {
            do {
                // Fetch both in parallel
                async let buildingsTask = CampaignMapService.shared.fetchBuildings(campaignId: campaignId)
                async let addressesTask = CampaignMapService.shared.fetchAddresses(campaignId: campaignId)
                
                buildingFeatures = try await buildingsTask
                addressFeatures = try await addressesTask
                
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    self.updateMapForCurrentMode()
                    self.setupRealtimeSubscription()
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    self.showError(error)
                }
            }
        }
    }
    
    // MARK: - Mode Toggle Handler
    
    @objc func modeChanged() {
        switch modeToggle.selectedSegmentIndex {
        case 0:
            currentMode = .buildings
        case 1:
            currentMode = .addresses
        case 2:
            currentMode = .both
        default:
            currentMode = .buildings
        }
        
        updateMapForCurrentMode()
    }
    
    func updateMapForCurrentMode() {
        switch currentMode {
        case .buildings:
            showBuildingsOnly()
        case .addresses:
            showAddressesOnly()
        case .both:
            showBoth()
        }
    }
    
    // MARK: - Map Layer Management
    
    func showBuildingsOnly() {
        removeAddressLayers()
        addBuildingLayers()
    }
    
    func showAddressesOnly() {
        removeBuildingLayers()
        addAddressLayers()
    }
    
    func showBoth() {
        addBuildingLayers()
        addAddressLayers()
    }
    
    // MARK: - Building Layers (3D Extrusion)
    
    func addBuildingLayers() {
        guard !buildingFeatures.isEmpty else { return }
        
        // Remove existing if any
        removeBuildingLayers()
        
        // Convert to Mapbox features
        var features: [Feature] = []
        
        for building in buildingFeatures {
            guard let geometry = convertPolygonToMapbox(building.geometry) else { continue }
            
            var properties = JSONObject()
            properties["gers_id"] = .string(building.properties.gersId)
            properties["height_m"] = .number(building.properties.heightM)
            properties["levels"] = building.properties.levels.map { .number(Double($0)) } ?? .null
            properties["address_text"] = building.properties.addressText.map { .string($0) } ?? .null
            properties["scans_total"] = .number(0)
            properties["status"] = .string("not_visited")
            
            features.append(Feature(geometry: geometry, properties: properties))
        }
        
        // Add source
        var source = GeoJSONSource()
        source.data = .featureCollection(FeatureCollection(features: features))
        source.promoteId = .string("gers_id")  // CRITICAL for feature state
        
        do {
            try mapView.mapboxMap.style.addSource(source, id: buildingSourceId)
            
            // Add 3D fill-extrusion layer
            var layer = FillExtrusionLayer(id: buildingLayerId)
            layer.source = buildingSourceId
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height_m" })
            layer.fillExtrusionBase = .constant(0)
            layer.fillExtrusionOpacity = .constant(0.85)
            layer.fillExtrusionColor = .expression(buildingColorExpression())
            layer.fillExtrusionAmbientOcclusionIntensity = .constant(0.3)
            layer.fillExtrusionAmbientOcclusionRadius = .constant(3.0)
            
            try mapView.mapboxMap.style.addLayer(layer)
            
            // Zoom to buildings
            zoomToFeatures(features)
            
        } catch {
            print("Error adding building layers: \(error)")
        }
    }
    
    func removeBuildingLayers() {
        do {
            if mapView.mapboxMap.style.layerExists(withId: buildingLayerId) {
                try mapView.mapboxMap.style.removeLayer(withId: buildingLayerId)
            }
            if mapView.mapboxMap.style.sourceExists(withId: buildingSourceId) {
                try mapView.mapboxMap.style.removeSource(withId: buildingSourceId)
            }
        } catch {
            print("Error removing building layers: \(error)")
        }
    }
    
    // MARK: - Address Layers (Pins with Rotation)
    
    func addAddressLayers() {
        guard !addressFeatures.isEmpty else { return }
        
        removeAddressLayers()
        
        var features: [Feature] = []
        
        for address in addressFeatures {
            let coordinate = CLLocationCoordinate2D(
                latitude: address.geometry.coordinates[1],
                longitude: address.geometry.coordinates[0]
            )
            
            var properties = JSONObject()
            properties["id"] = .string(address.properties.id)
            properties["formatted"] = .string(address.properties.formatted)
            properties["visited"] = .boolean(address.properties.visited)
            properties["house_bearing"] = address.properties.houseBearing.map { .number($0) } ?? .null
            properties["road_bearing"] = address.properties.roadBearing.map { .number($0) } ?? .null
            
            let feature = Feature(
                geometry: .point(Point(coordinate)),
                properties: properties
            )
            features.append(feature)
        }
        
        // Add source
        var source = GeoJSONSource()
        source.data = .featureCollection(FeatureCollection(features: features))
        
        do {
            try mapView.mapboxMap.style.addSource(source, id: addressSourceId)
            
            // Add symbol layer for address pins
            var layer = SymbolLayer(id: addressLayerId)
            layer.source = addressSourceId
            
            // Use house icon (you need to add this to your style)
            layer.iconImage = .constant(.name("house-icon"))
            layer.iconSize = .constant(0.5)
            layer.iconAllowOverlap = .constant(true)
            layer.iconIgnorePlacement = .constant(true)
            
            // Rotate icon to face the street (house_bearing)
            layer.iconRotation = .expression(
                Exp(.switchCase) {
                    Exp(.has) { "house_bearing" }
                    Exp(.get) { "house_bearing" }
                    Exp(.has) { "road_bearing" }
                    Exp(.get) { "road_bearing" }
                    0
                }
            )
            
            // Color based on visited status
            layer.iconColor = .expression(
                Exp(.switchCase) {
                    Exp(.eq) { Exp(.get) { "visited" }; true }
                    UIColor.green
                    UIColor.red
                }
            )
            
            // Add text label
            layer.textField = .expression(Exp(.get) { "formatted" })
            layer.textSize = .constant(12)
            layer.textOffset = .constant([0, 1.5])
            layer.textAnchor = .constant(.top)
            
            try mapView.mapboxMap.style.addLayer(layer)
            
        } catch {
            print("Error adding address layers: \(error)")
        }
    }
    
    func removeAddressLayers() {
        do {
            if mapView.mapboxMap.style.layerExists(withId: addressLayerId) {
                try mapView.mapboxMap.style.removeLayer(withId: addressLayerId)
            }
            if mapView.mapboxMap.style.sourceExists(withId: addressSourceId) {
                try mapView.mapboxMap.style.removeSource(withId: addressSourceId)
            }
        } catch {
            print("Error removing address layers: \(error)")
        }
    }
    
    // MARK: - Color Expression for Buildings
    
    func buildingColorExpression() -> Exp {
        return Exp(.switchCase) {
            // Priority 1: QR Scanned (YELLOW)
            Exp(.gt) { Exp(.get) { "scans_total" }; 0 }
            UIColor(hex: "#facc15")
            
            // Priority 2: Hot lead (BLUE)
            Exp(.eq) { Exp(.get) { "status" }; "hot" }
            UIColor(hex: "#3b82f6")
            
            // Priority 3: Visited (GREEN)
            Exp(.eq) { Exp(.get) { "status" }; "visited" }
            UIColor(hex: "#22c55e")
            
            // Default: Not visited (RED)
            UIColor(hex: "#ef4444")
        }
    }
    
    // MARK: - Realtime Updates
    
    func setupRealtimeSubscription() {
        realtimeChannel = supabase.channel("building-stats-\(campaignId)")
        
        realtimeChannel?
            .on(
                "postgres_changes",
                filter: ChannelFilter(
                    event: "*",
                    schema: "public",
                    table: "building_stats",
                    filter: "campaign_id=eq.\(campaignId)"
                )
            ) { [weak self] payload in
                self?.handleBuildingStatUpdate(payload: payload)
            }
            .subscribe()
    }
    
    func handleBuildingStatUpdate(payload: SupabaseRealtimePayload) {
        guard let newData = payload.new else { return }
        
        let gersId = newData["gers_id"] as? String
        let scansTotal = newData["scans_total"] as? Int ?? 0
        let status = newData["status"] as? String ?? "not_visited"
        
        guard let gersId = gersId else { return }
        
        DispatchQueue.main.async {
            // Update feature state for instant color change
            try? self.mapView.mapboxMap.setFeatureState(
                sourceId: self.buildingSourceId,
                featureId: gersId,
                state: [
                    "scans_total": scansTotal,
                    "status": status
                ]
            )
        }
    }
    
    // MARK: - Helpers
    
    func convertPolygonToMapbox(_ geometry: PolygonGeometry) -> MapboxMaps.Geometry? {
        guard geometry.type == "Polygon" || geometry.type == "MultiPolygon" else { return nil }
        
        // Handle Polygon
        if geometry.type == "Polygon" {
            guard let ringCoords = geometry.coordinates.first?.first else { return nil }
            
            var coordinates: [CLLocationCoordinate2D] = []
            for point in ringCoords {
                guard point.count >= 2 else { continue }
                coordinates.append(CLLocationCoordinate2D(
                    latitude: point[1],
                    longitude: point[0]
                ))
            }
            
            return .polygon(Polygon([Ring(coordinates: coordinates)]))
        }
        
        // Handle MultiPolygon (use first polygon)
        if geometry.type == "MultiPolygon" {
            guard let polygonCoords = geometry.coordinates.first?.first else { return nil }
            
            var coordinates: [CLLocationCoordinate2D] = []
            for point in polygonCoords {
                guard point.count >= 2 else { continue }
                coordinates.append(CLLocationCoordinate2D(
                    latitude: point[1],
                    longitude: point[0]
                ))
            }
            
            return .polygon(Polygon([Ring(coordinates: coordinates)]))
        }
        
        return nil
    }
    
    func zoomToFeatures(_ features: [Feature]) {
        guard !features.isEmpty else { return }
        
        var coordinates: [CLLocationCoordinate2D] = []
        
        for feature in features {
            if case .polygon(let polygon) = feature.geometry {
                for ring in polygon.coordinates {
                    coordinates.append(contentsOf: ring.coordinates)
                }
            }
        }
        
        guard !coordinates.isEmpty else { return }
        
        let bounds = coordinates.reduce(into: (south: 90.0, west: 180.0, north: -90.0, east: -180.0)) { result, coord in
            result.south = min(result.south, coord.latitude)
            result.west = min(result.west, coord.longitude)
            result.north = max(result.north, coord.latitude)
            result.east = max(result.east, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (bounds.south + bounds.north) / 2,
            longitude: (bounds.west + bounds.east) / 2
        )
        
        let camera = CameraOptions(
            center: center,
            padding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50)
        )
        
        mapView.mapboxMap.setCamera(to: camera)
    }
    
    func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}
```

### 4. SwiftUI Version (Modern)

```swift
import SwiftUI
import MapboxMaps
import Supabase

struct CampaignMapView: View {
    let campaignId: String
    
    @State private var displayMode: MapDisplayMode = .buildings
    @State private var buildingFeatures: [BuildingFeature] = []
    @State private var addressFeatures: [AddressFeature] = []
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        ZStack {
            MapboxMapView(
                campaignId: campaignId,
                displayMode: $displayMode,
                buildingFeatures: $buildingFeatures,
                addressFeatures: $addressFeatures
            )
            .ignoresSafeArea()
            
            VStack {
                Picker("Display Mode", selection: $displayMode) {
                    Text("Buildings").tag(MapDisplayMode.buildings)
                    Text("Addresses").tag(MapDisplayMode.addresses)
                    Text("Both").tag(MapDisplayMode.both)
                }
                .pickerStyle(.segmented)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding()
                
                Spacer()
            }
            
            if isLoading {
                ProgressView("Loading...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }
        }
        .task {
            await loadData()
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Unknown error")
        }
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            async let buildings = CampaignMapService.shared.fetchBuildings(campaignId: campaignId)
            async let addresses = CampaignMapService.shared.fetchAddresses(campaignId: campaignId)
            
            buildingFeatures = try await buildings
            addressFeatures = try await addresses
        } catch {
            self.error = error
        }
    }
}

// UIViewRepresentable wrapper for Mapbox
struct MapboxMapView: UIViewRepresentable {
    let campaignId: String
    @Binding var displayMode: MapDisplayMode
    @Binding var buildingFeatures: [BuildingFeature]
    @Binding var addressFeatures: [AddressFeature]
    
    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions(cameraOptions: CameraOptions(zoom: 15, pitch: 45))
        let mapView = MapView(frame: .zero, mapInitOptions: options)
        
        context.coordinator.mapView = mapView
        context.coordinator.setupMap()
        
        return mapView
    }
    
    func updateUIView(_ mapView: MapView, context: Context) {
        context.coordinator.updateDisplayMode(displayMode)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: MapboxMapView
        var mapView: MapView?
        
        init(_ parent: MapboxMapView) {
            self.parent = parent
        }
        
        func setupMap() {
            // Configure map
        }
        
        func updateDisplayMode(_ mode: MapDisplayMode) {
            // Update layers based on mode
        }
    }
}
```

---

## API Endpoints Summary

| Endpoint | Method | Description | Returns |
|----------|--------|-------------|---------|
| `/api/campaigns/{id}/buildings` | GET | 3D building footprints | GeoJSON Polygons |
| `/api/campaigns/{id}/addresses` | GET | Address points with rotation | GeoJSON Points |
| `/api/campaigns/{id}/roads` | GET | Road network (optional) | GeoJSON LineStrings |

### Buildings Response Format

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "08a2b4c5d6e7f8g9",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[-79.5, 43.6], [-79.4, 43.6], [-79.4, 43.7], [-79.5, 43.7], [-79.5, 43.6]]]
      },
      "properties": {
        "gers_id": "08a2b4c5d6e7f8g9",
        "height_m": 8.5,
        "levels": 2,
        "address_text": "123 Main St",
        "feature_status": "linked"
      }
    }
  ]
}
```

### Addresses Response Format

```json
[
  {
    "type": "Feature",
    "geometry": {
      "type": "Point",
      "coordinates": [-79.45, 43.65]
    },
    "properties": {
      "id": "uuid-address-123",
      "formatted": "123 Main St, Toronto, ON",
      "visited": false,
      "house_bearing": 90,
      "road_bearing": 90
    }
  }
]
```

---

## Key Implementation Notes

1. **Building Heights**: Use `height_m` property for 3D extrusion
2. **Address Rotation**: `house_bearing` rotates the icon to face the street
3. **Feature State**: Always set `promoteId: "gers_id"` for building color updates
4. **Color Priority**: Yellow (scanned) → Blue (hot) → Green (visited) → Red (default)
5. **Toggle Performance**: Remove/add layers rather than hiding (better memory usage)

---

## Required Assets

Add these images to your Mapbox style:
- `house-icon`: House-shaped marker for addresses

Or use system SF Symbols as fallback.
