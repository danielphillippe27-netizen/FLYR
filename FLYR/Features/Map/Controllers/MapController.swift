import Foundation
import MapboxMaps
import CoreLocation
import UIKit

/// Controller for managing map modes, 3D extrusions, and style switching
@MainActor
final class MapController {
    static let shared = MapController()
    
    private init() {}
    
    // Layer IDs for tracking
    private let layer3DBuildings = "flyr-3d-buildings"
    private let layerCampaign3D = "campaign-3d"
    private let layerCrushedBuildings = "crushed-buildings"
    private let sourceCampaignGeo = "campaign-geo"
    private let sourceCampaignBuildings = "campaign-buildings"
    
    /// Apply a map mode to the map view. When mode is campaign3D, pass preferLightStyle: true to keep light base in light view.
    func applyMode(_ mode: MapMode, to mapView: MapView, campaignPolygon: [CLLocationCoordinate2D]? = nil, campaignId: UUID? = nil, preferLightStyle: Bool = false) {
        guard let map = mapView.mapboxMap else { return }
        
        // Wait for map to be loaded before applying changes
        map.onMapLoaded.observeNext { [weak self] _ in
            Task { @MainActor in
                await self?.applyModeInternal(mode, to: mapView, campaignPolygon: campaignPolygon, campaignId: campaignId, preferLightStyle: preferLightStyle)
            }
        }
        
        // If map is already loaded, apply immediately
        if map.isStyleLoaded {
            Task { @MainActor in
                await applyModeInternal(mode, to: mapView, campaignPolygon: campaignPolygon, campaignId: campaignId, preferLightStyle: preferLightStyle)
            }
        }
    }
    
    private func applyModeInternal(_ mode: MapMode, to mapView: MapView, campaignPolygon: [CLLocationCoordinate2D]?, campaignId: UUID?, preferLightStyle: Bool = false) async {
        guard let map = mapView.mapboxMap else { return }
        
        // Load style first (campaign3D uses light base when preferLightStyle is true)
        await loadStyle(for: mode, to: mapView, preferLightStyle: preferLightStyle)
        
        // Wait a bit for style to load
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Clean up existing layers
        cleanupLayers(from: map)
        
        // Apply mode-specific layers
        switch mode {
        case .light, .dark:
            // No 3D layers for flat modes
            break
            
        case .black3D:
            add3DBuildings(to: mapView)
            
        case .campaign3D:
            // Only show campaign (my) buildings — no Mapbox base 3D buildings layer
            if let campaignId = campaignId {
                await addCampaignAddressBuildings(to: mapView, campaignId: campaignId)
            } else if let polygon = campaignPolygon {
                await addCampaignExtrusions(to: mapView, polygon: polygon)
            } else {
                // Fallback to regular 3D if no campaign data
                add3DBuildings(to: mapView)
            }
        }
        
        // Apply camera settings
        applyCamera(for: mode, to: mapView)
    }
    
    /// Load style JSON for a map mode (campaign3D uses light base when preferLightStyle is true)
    private func loadStyle(for mode: MapMode, to mapView: MapView, preferLightStyle: Bool = false) async {
        guard let map = mapView.mapboxMap else { return }
        
        let styleURI = MapTheme.styleURI(for: mode, preferLightStyle: preferLightStyle)
        map.loadStyle(styleURI)
        print("✅ [MapController] Loading style: \(mode.rawValue) preferLight: \(preferLightStyle)")
    }
    
    /// Add 3D building extrusions (all buildings, black in dark mode, white in light mode)
    func add3DBuildings(to mapView: MapView) {
        guard let map = mapView.mapboxMap else { return }
        
        guard !map.allLayerIdentifiers.contains(where: { $0.id == layer3DBuildings }) else {
            print("⚠️ [MapController] 3D buildings layer already exists")
            return
        }
        
        do {
            var layer = FillExtrusionLayer(id: layer3DBuildings, source: "composite")
            layer.sourceLayer = "building"
            layer.minZoom = 13
            layer.fillExtrusionOpacity = .constant(0.9)
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
            layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
            
            // Use feature-state to support building selection highlighting
            // Check if current style is dark by checking the style URI
            let isDarkMode = map.styleURI == .dark
            let defaultBuildingColor: UIColor = isDarkMode ? .black : .white
            let selectedColor: UIColor = .systemRed
            
            // Expression: if feature-state("selected") is true, use red, otherwise use default color
            // Use match with boolean converted to string for matching
            layer.fillExtrusionColor = .expression(
                Exp(.match) {
                    Exp(.toString) {
                        Exp(.eq) {
                            Exp(.featureState) { "selected" }
                            true
                        }
                    }
                    "true"  // label for true
                    selectedColor  // output if true
                    defaultBuildingColor  // fallback if false
                }
            )
            
            try map.addLayer(layer)
            print("✅ [MapController] Added 3D buildings layer with feature-state support (color: \(isDarkMode ? "black" : "white"), selected: red)")
        } catch {
            print("❌ [MapController] Failed to add 3D buildings: \(error)")
        }
    }
    
    /// Add white buildings for campaign addresses
    /// Fetches building polygons for campaign addresses and displays them in white
    /// 
    /// In 3D campaign mode, this creates a visual distinction:
    /// - Campaign buildings (with pins/addresses): White, fully opaque, highlighted
    /// - Non-campaign buildings: Black, dimmed (via crushSurroundings), lower opacity
    /// This makes campaign buildings stand out clearly against the dimmed surroundings.
    func addCampaignAddressBuildings(to mapView: MapView, campaignId: UUID) async {
        guard let map = mapView.mapboxMap else { return }
        
        do {
            // Fetch building polygons from buildings + building_address_links (rpc_get_campaign_full_features)
            let geoJSONCollection = try await BuildingsAPI.shared.fetchBuildingPolygons(campaignId: campaignId)
            
            // Filter to only polygon geometries
            let polygonFeatures = geoJSONCollection.features.filter { feature in
                feature.geometry.type == "Polygon" || feature.geometry.type == "MultiPolygon"
            }
            
            guard !polygonFeatures.isEmpty else {
                print("⚠️ [MapController] No building polygons found for campaign \(campaignId)")
                return
            }
            
            // Fetch address statuses for this campaign
            let statuses = try? await VisitsAPI.shared.fetchStatuses(campaignId: campaignId)
            print("📊 [MapController] Loaded \(statuses?.count ?? 0) statuses for campaign \(campaignId)")
            
            // Convert GeoJSON features to Mapbox features
            var mapboxFeatures: [Feature] = []
            var gersIdByAddressId: [String: String] = [:]
            for geoFeature in polygonFeatures {
                guard let geometry = convertGeoJSONToMapboxGeometry(geoFeature.geometry) else {
                    continue
                }
                
                // Extract gers_id for feature-state identity; map address_id -> gers_id for status hydration.
                var gersIdString: String? = nil
                if let gersIdValue = geoFeature.properties["gers_id"]?.value as? String, !gersIdValue.isEmpty {
                    gersIdString = gersIdValue
                } else if let idValue = geoFeature.id, !idValue.isEmpty {
                    gersIdString = idValue
                }

                var addressIdString: String? = nil
                if let addressIdValue = geoFeature.properties["address_id"] {
                    addressIdString = addressIdValue.value as? String
                }
                if let addressIdString, let gersIdString {
                    gersIdByAddressId[addressIdString] = gersIdString
                }
                
                var mapboxFeature = Feature(geometry: geometry)
                // Feature state is keyed by gers_id.
                if let gersIdString {
                    mapboxFeature.identifier = .string(gersIdString)
                }
                
                // Convert properties
                var props: [String: JSONValue] = [:]
                for (key, anyCodable) in geoFeature.properties {
                    if let stringValue = anyCodable.value as? String {
                        props[key] = .string(stringValue)
                    } else if let numberValue = anyCodable.value as? Double {
                        props[key] = .number(numberValue)
                    } else if let intValue = anyCodable.value as? Int {
                        props[key] = .number(Double(intValue))
                    } else if let boolValue = anyCodable.value as? Bool {
                        props[key] = .boolean(boolValue)
                    }
                }
                // Ensure height properties exist for 3D extrusion
                if props["height"] == nil {
                    props["height"] = .number(10.0) // Default height
                }
                if props["min_height"] == nil {
                    props["min_height"] = .number(0.0)
                }
                if let gersIdString {
                    props["gers_id"] = .string(gersIdString)
                }
                mapboxFeature.properties = props
                mapboxFeatures.append(mapboxFeature)
            }
            
            // Create or update buildings source
            if map.allSourceIdentifiers.contains(where: { $0.id == sourceCampaignBuildings }) {
                try map.removeSource(withId: sourceCampaignBuildings)
            }
            
            var buildingsSource = GeoJSONSource(id: sourceCampaignBuildings)
            buildingsSource.data = .featureCollection(FeatureCollection(features: mapboxFeatures))
            buildingsSource.promoteId2 = .constant("gers_id")
            try map.addSource(buildingsSource)
            
            // Add white buildings layer (only buildings for campaign addresses)
            if map.allLayerIdentifiers.contains(where: { $0.id == layerCampaign3D }) {
                try map.removeLayer(withId: layerCampaign3D)
            }
            
            var layer = FillExtrusionLayer(id: layerCampaign3D, source: sourceCampaignBuildings)
            layer.minZoom = 13
            // Full opacity for campaign buildings - they should stand out clearly
            layer.fillExtrusionOpacity = .constant(1.0)
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
            layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
            
            // Use feature-state to support building selection highlighting and status-based coloring
            // Color priority: selected (red) > status (color by status) > default (white)
            let selectedColor: UIColor = .systemRed
            let defaultColor: UIColor = .white // Campaign buildings default to white
            
            // Status color mapping (knock → green, conversation → blue)
            let statusColors: [String: UIColor] = [
                "none": .white,
                "no_answer": .gray,
                "delivered": .systemGreen,
                "talked": .systemBlue,
                "appointment": .systemBlue,
                "do_not_knock": .systemPurple,
                "future_seller": .systemOrange,
                "hot_lead": .systemRed
            ]
            
            // Build color expression with priority: selected > status > default
            // Use match with boolean converted to string for boolean condition, match for string status
            layer.fillExtrusionColor = .expression(
                Exp(.match) {
                    Exp(.toString) {
                        Exp(.eq) {
                            Exp(.featureState) { "selected" }
                            true
                        }
                    }
                    "true"  // label for true
                    selectedColor  // output if true (red)
                    // If not selected, check status and return status color
                    Exp(.match) {
                        Exp(.featureState) { "status" }
                        "none"
                        statusColors["none"] ?? defaultColor
                        "no_answer"
                        statusColors["no_answer"] ?? defaultColor
                        "delivered"
                        statusColors["delivered"] ?? defaultColor
                        "talked"
                        statusColors["talked"] ?? defaultColor
                        "appointment"
                        statusColors["appointment"] ?? defaultColor
                        "do_not_knock"
                        statusColors["do_not_knock"] ?? defaultColor
                        "future_seller"
                        statusColors["future_seller"] ?? defaultColor
                        "hot_lead"
                        statusColors["hot_lead"] ?? defaultColor
                        // Default fallback if status doesn't match
                        defaultColor
                    }
                }
            )
            
            try map.addLayer(layer)
            print("✅ [MapController] Added white buildings layer with feature-state support (\(mapboxFeatures.count) buildings) for campaign \(campaignId)")
            
            // Apply feature-state for each building based on status
            if let statuses = statuses {
                // Convert [address_id: status] to [gers_id: status] to match feature IDs/promoteId.
                let statusesDict: [String: AddressStatus] = Dictionary(uniqueKeysWithValues: statuses.compactMap {
                    let addressId = $0.key.uuidString
                    guard let gersId = gersIdByAddressId[addressId] else { return nil }
                    return (gersId, $0.value.status)
                })
                applyStatusFeatureState(statuses: statusesDict, mapView: mapView)
            }
        } catch {
            print("❌ [MapController] Failed to add campaign address buildings: \(error)")
        }
    }
    
    /// Convert GeoJSON geometry to Mapbox Geometry
    private func convertGeoJSONToMapboxGeometry(_ geoGeometry: GeoJSONGeometry) -> Geometry? {
        switch geoGeometry.type {
        case "Polygon":
            guard let coords = geoGeometry.coordinates.value as? [[[Double]]] else { return nil }
            let polygonCoords = coords.map { ring in
                ring.map { coord in
                    LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }
            return .polygon(Polygon(polygonCoords))
            
        case "MultiPolygon":
            guard let coords = geoGeometry.coordinates.value as? [[[[Double]]]] else { return nil }
            let multiPolygonCoords = coords.map { polygon in
                polygon.map { ring in
                    ring.map { coord in
                        LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    }
                }
            }
            return .multiPolygon(MultiPolygon(multiPolygonCoords))
            
        default:
            return nil
        }
    }
    
    /// Add campaign-only 3D extrusions with polygon filter
    /// Queries buildings within the polygon and displays them in white
    func addCampaignExtrusions(to mapView: MapView, polygon: [CLLocationCoordinate2D]) async {
        guard let map = mapView.mapboxMap else { return }
        
        // Convert polygon to Mapbox format
        let polygonCoords = polygon.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let shape = Polygon([polygonCoords])
        let feature = Feature(geometry: .polygon(shape))
        
        // Add or update campaign polygon source (for polygon outline)
        do {
            if map.allSourceIdentifiers.contains(where: { $0.id == sourceCampaignGeo }) {
                try map.removeSource(withId: sourceCampaignGeo)
            }
            
            var source = GeoJSONSource(id: sourceCampaignGeo)
            source.data = .feature(feature)
            try map.addSource(source)
            
            // Add campaign polygon outline (FLYR red border)
            let outlineLayerId = "campaign-polygon-outline"
            if map.allLayerIdentifiers.contains(where: { $0.id == outlineLayerId }) {
                try map.removeLayer(withId: outlineLayerId)
            }
            
            var outlineLayer = LineLayer(id: outlineLayerId, source: sourceCampaignGeo)
            outlineLayer.lineColor = .constant(StyleColor(.red))
            outlineLayer.lineWidth = .constant(3.0)
            outlineLayer.lineOpacity = .constant(1.0)
            try map.addLayer(outlineLayer)
            
            // Query buildings within polygon and create GeoJSON source
            let buildingsInPolygon = await queryBuildingsInPolygon(polygon: polygon)
            
            // Create or update buildings source
            if map.allSourceIdentifiers.contains(where: { $0.id == sourceCampaignBuildings }) {
                try map.removeSource(withId: sourceCampaignBuildings)
            }
            
            var buildingsSource = GeoJSONSource(id: sourceCampaignBuildings)
            buildingsSource.data = .featureCollection(buildingsInPolygon)
            try map.addSource(buildingsSource)
            
            // Add white buildings layer (only buildings inside polygon)
            if map.allLayerIdentifiers.contains(where: { $0.id == layerCampaign3D }) {
                try map.removeLayer(withId: layerCampaign3D)
            }
            
            var layer = FillExtrusionLayer(id: layerCampaign3D, source: sourceCampaignBuildings)
            layer.minZoom = 13
            layer.fillExtrusionOpacity = .constant(1.0)
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
            layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
            
            // Use feature-state to support building selection highlighting
            let selectedColor: UIColor = .systemRed
            let defaultColor: UIColor = .white
            
            // Expression: if feature-state("selected") is true, use red, otherwise use white
            // Use match with boolean converted to string for matching
            layer.fillExtrusionColor = .expression(
                Exp(.match) {
                    Exp(.toString) {
                        Exp(.eq) {
                            Exp(.featureState) { "selected" }
                            true
                        }
                    }
                    "true"  // label for true
                    selectedColor  // output if true (red)
                    defaultColor  // fallback if false (white)
                }
            )
            
            try map.addLayer(layer)
            print("✅ [MapController] Added white buildings layer with feature-state support (\(buildingsInPolygon.features.count) buildings)")
        } catch {
            print("❌ [MapController] Failed to add campaign extrusions: \(error)")
        }
    }
    
    /// Query buildings within a polygon by sampling points and using Tilequery API
    private func queryBuildingsInPolygon(polygon: [CLLocationCoordinate2D]) async -> FeatureCollection {
        let polygonShape = Polygon([polygon.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }])
        
        // Calculate bounding box and sample points
        let bbox = calculateBoundingBox(polygon: polygon)
        
        // Use adaptive spacing based on polygon size to limit API calls
        let polygonArea = estimatePolygonArea(bbox: bbox)
        let spacing: Double = polygonArea > 1_000_000 ? 100.0 : 50.0 // Larger spacing for bigger polygons
        
        var samplePoints = generateSamplePoints(bbox: bbox, polygon: polygonShape, spacing: spacing)
        
        // Also add polygon vertices and centroid for better coverage
        samplePoints.append(contentsOf: polygon)
        if let centroid = BuildingGeometryHelpers.polygonCentroid(polygonShape) {
            samplePoints.append(centroid)
        }
        
        // Limit total sample points to avoid too many API calls
        if samplePoints.count > 100 {
            // Take evenly distributed subset
            let step = samplePoints.count / 100
            samplePoints = stride(from: 0, to: samplePoints.count, by: step).map { samplePoints[$0] }
        }
        
        print("🔍 [MapController] Sampling \(samplePoints.count) points within polygon (spacing: \(spacing)m)")
        
        var allBuildings: [String: Feature] = [:] // Deduplicate by building ID
        let token = MapboxManager.shared.accessToken
        
        // Query buildings at each sample point
        for point in samplePoints {
            do {
                let radiusMeters = spacing.isFinite ? Int(spacing) : 50
                if let (buildingId, geometry) = try await MapboxBuildingsAPI.shared.fetchBestBuildingPolygon(
                    coord: point,
                    radiusMeters: radiusMeters,
                    token: token
                ) {
                    // Check if building centroid is inside polygon
                    if let centroid = extractCentroid(from: geometry),
                       BuildingGeometryHelpers.pointInPolygon(centroid, polygon: polygonShape) {
                        // Create feature if not already added
                        if allBuildings[buildingId] == nil {
                            if let feature = createFeature(from: geometry, buildingId: buildingId) {
                                allBuildings[buildingId] = feature
                            }
                        }
                    }
                }
            } catch {
                print("⚠️ [MapController] Failed to query building at \(point): \(error)")
            }
        }
        
        print("✅ [MapController] Found \(allBuildings.count) unique buildings in polygon")
        return FeatureCollection(features: Array(allBuildings.values))
    }
    
    /// Estimate polygon area in square meters (rough approximation)
    private func estimatePolygonArea(bbox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)) -> Double {
        let latDiff = bbox.maxLat - bbox.minLat
        let lonDiff = bbox.maxLon - bbox.minLon
        let avgLat = (bbox.minLat + bbox.maxLat) / 2.0
        
        // Convert to meters (rough approximation)
        let latMeters = latDiff * 111000.0
        let lonMeters = lonDiff * 111000.0 * cos(avgLat * .pi / 180.0)
        
        return latMeters * lonMeters
    }
    
    /// Calculate bounding box of a polygon
    private func calculateBoundingBox(polygon: [CLLocationCoordinate2D]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        
        for coord in polygon {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        
        return (minLat, maxLat, minLon, maxLon)
    }
    
    /// Generate sample points within polygon bounding box, filtered to only points inside polygon
    private func generateSamplePoints(bbox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double), polygon: Polygon, spacing: Double) -> [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        
        // Convert spacing from meters to approximate degrees (rough approximation)
        let latSpacing = spacing / 111000.0 // ~111km per degree latitude
        let lonSpacing = spacing / (111000.0 * cos(bbox.minLat * .pi / 180.0))
        
        var lat = bbox.minLat
        while lat <= bbox.maxLat {
            var lon = bbox.minLon
            while lon <= bbox.maxLon {
                let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if BuildingGeometryHelpers.pointInPolygon(point, polygon: polygon) {
                    points.append(point)
                }
                lon += lonSpacing
            }
            lat += latSpacing
        }
        
        return points
    }
    
    /// Extract centroid from building geometry dictionary
    private func extractCentroid(from geometry: [String: Any]) -> CLLocationCoordinate2D? {
        guard let coordinates = geometry["coordinates"] as? [[[Double]]],
              let firstRing = coordinates.first,
              firstRing.count >= 3 else {
            return nil
        }
        
        var sumLat = 0.0
        var sumLon = 0.0
        var count = 0
        
        for coord in firstRing {
            if coord.count >= 2 {
                sumLon += coord[0]
                sumLat += coord[1]
                count += 1
            }
        }
        
        guard count > 0 else { return nil }
        return CLLocationCoordinate2D(latitude: sumLat / Double(count), longitude: sumLon / Double(count))
    }
    
    /// Create a Mapbox Feature from building geometry
    private func createFeature(from geometry: [String: Any], buildingId: String) -> Feature? {
        guard let type = geometry["type"] as? String,
              let coordinates = geometry["coordinates"] else {
            return nil
        }
        
        var mapboxGeometry: Geometry?
        
        switch type {
        case "Polygon":
            guard let coords = coordinates as? [[[Double]]] else { return nil }
            let polygonCoords = coords.map { ring in
                ring.map { coord in
                    LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                }
            }
            mapboxGeometry = .polygon(Polygon(polygonCoords))
            
        case "MultiPolygon":
            guard let coords = coordinates as? [[[[Double]]]] else { return nil }
            let multiPolygonCoords = coords.map { polygon in
                polygon.map { ring in
                    ring.map { coord in
                        LocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    }
                }
            }
            mapboxGeometry = .multiPolygon(MultiPolygon(multiPolygonCoords))
            
        default:
            return nil
        }
        
        guard let geometry = mapboxGeometry else { return nil }
        
        var feature = Feature(geometry: geometry)
        feature.properties = [
            "id": .string(buildingId),
            "height": .number(10.0), // Default height if not in properties
            "min_height": .number(0.0)
        ]
        
        return feature
    }
    
    /// Show all buildings in black/dimmed (for campaign mode - buildings outside target)
    /// 
    /// This dims all non-campaign buildings to create visual contrast:
    /// - Non-campaign buildings: Black color, reduced opacity (0.7) for dimming effect
    /// - Campaign buildings: White, full opacity (rendered above this layer)
    /// The reduced opacity helps campaign buildings stand out more clearly.
    func crushSurroundings(to mapView: MapView) {
        guard let map = mapView.mapboxMap else { return }
        
        guard !map.allLayerIdentifiers.contains(where: { $0.id == layerCrushedBuildings }) else {
            print("⚠️ [MapController] Black buildings layer already exists")
            return
        }
        
        do {
            var layer = FillExtrusionLayer(id: layerCrushedBuildings, source: "composite")
            layer.sourceLayer = "building"
            layer.minZoom = 13
            layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
            layer.fillExtrusionBase = .expression(Exp(.get) { "min_height" })
            // Dimmed opacity (0.3) to dim non-campaign buildings for better contrast
            layer.fillExtrusionOpacity = .constant(0.3)
            
            // Use feature-state to support building selection highlighting
            // Color priority: selected (red) > default (black for dimmed buildings)
            let selectedColor: UIColor = .systemRed
            let defaultColor: UIColor = .black // Non-campaign buildings are black and dimmed
            
            // Expression: if feature-state("selected") is true, use red, otherwise use black
            // Use match with boolean converted to string for matching
            layer.fillExtrusionColor = .expression(
                Exp(.match) {
                    Exp(.toString) {
                        Exp(.eq) {
                            Exp(.featureState) { "selected" }
                            true
                        }
                    }
                    "true"  // label for true
                    selectedColor  // output if true (red)
                    defaultColor  // fallback if false (black)
                }
            )
            
            // Add layer first (campaign buildings layer will be added above it later)
            // This ensures campaign buildings appear on top of dimmed surroundings
            try map.addLayer(layer)
            print("✅ [MapController] Added dimmed buildings layer (opacity 0.7) with feature-state support")
        } catch {
            print("❌ [MapController] Failed to add black buildings: \(error)")
        }
    }
    
    /// Apply camera settings for a map mode
    func applyCamera(for mode: MapMode, to mapView: MapView) {
        let pitch: CGFloat = mode.is3DMode ? 60 : 0
        
        let currentCamera = mapView.mapboxMap.cameraState
        let cameraOptions = CameraOptions(
            center: currentCamera.center,
            zoom: currentCamera.zoom,
            pitch: pitch
        )
        
        mapView.mapboxMap.setCamera(to: cameraOptions)
        print("✅ [MapController] Applied camera: pitch=\(pitch)° for mode \(mode.rawValue)")
    }
    
    /// Apply status feature-state to mapbox features
    /// - Parameters:
    ///   - statuses: Dictionary mapping address_id (String) to AddressStatus
    ///   - mapView: MapView to apply feature-state to
    func applyStatusFeatureState(
        statuses: [String: AddressStatus],
        mapView: MapView
    ) {
        guard let map = mapView.mapboxMap else { return }
        guard map.allSourceIdentifiers.contains(where: { $0.id == sourceCampaignBuildings }) else {
            // Session/campaign map may use MapLayerManager (campaign-address-points), not campaign-buildings
            return
        }
        
        for (addressId, status) in statuses {
            let state: [String: Any] = [
                "status": status.rawValue,
                "selected": false
            ]
            
            map.setFeatureState(
                sourceId: sourceCampaignBuildings,
                sourceLayerId: nil,
                featureId: addressId,
                state: state
            ) { result in
                if case .failure(let error) = result {
                    print("⚠️ [MapController] Failed to set feature-state for \(addressId): \(error)")
                }
            }
        }
        print("✅ [MapController] Applied feature-state for \(statuses.count) buildings")
    }
    
    /// Update address status and immediately apply feature-state to map
    /// - Parameters:
    ///   - addressId: UUID of the address
    ///   - campaignId: UUID of the campaign
    ///   - status: New status value
    ///   - notes: Optional notes
    ///   - mapView: MapView to update feature-state on
    /// - Returns: Updated AddressStatusRow
    func updateAddressStatus(
        addressId: UUID,
        campaignId: UUID,
        status: AddressStatus,
        notes: String? = nil,
        mapView: MapView
    ) async throws -> AddressStatusRow {
        print("🔄 [MapController] Updating status for address \(addressId) to \(status.rawValue)")
        
        // Update in Supabase
        try await VisitsAPI.shared.updateStatus(
            addressId: addressId,
            campaignId: campaignId,
            status: status,
            notes: notes
        )
        
        // Immediately update feature-state for instant visual feedback
        let addressIdString = addressId.uuidString
        let statusesDict = [addressIdString: status]
        applyStatusFeatureState(statuses: statusesDict, mapView: mapView)
        
        // Fetch updated status row to return
        let statusRows = try await VisitsAPI.shared.fetchStatuses(campaignId: campaignId)
        guard let updatedStatusRow = statusRows[addressId] else {
            throw NSError(domain: "MapController", code: 404, userInfo: [NSLocalizedDescriptionKey: "Status not found after update"])
        }
        
        return updatedStatusRow
    }
    
    /// Clean up all custom layers
    private func cleanupLayers(from map: MapboxMap) {
        let layerIds = [layer3DBuildings, layerCampaign3D, layerCrushedBuildings, "campaign-polygon-outline"]
        
        for layerId in layerIds {
            if map.allLayerIdentifiers.contains(where: { $0.id == layerId }) {
                try? map.removeLayer(withId: layerId)
            }
        }
        
        // Clean up campaign polygon source
        if map.allSourceIdentifiers.contains(where: { $0.id == sourceCampaignGeo }) {
            try? map.removeSource(withId: sourceCampaignGeo)
        }
        
        // Clean up campaign buildings source
        if map.allSourceIdentifiers.contains(where: { $0.id == sourceCampaignBuildings }) {
            try? map.removeSource(withId: sourceCampaignBuildings)
        }
        
        print("✅ [MapController] Cleaned up layers")
    }
}

