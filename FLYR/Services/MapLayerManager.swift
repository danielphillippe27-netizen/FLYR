import Foundation
import MapboxMaps
import UIKit
import CoreLocation

// MARK: - Status Colors

/// Map status color configuration. Purple = QR scanned (align with web).
enum MapStatusColor {
    static let qrScanned = UIColor(hex: "#8b5cf6")!      // Purple (QR codes)
    static let conversations = UIColor(hex: "#3b82f6")!   // Blue
    static let touched = UIColor(hex: "#22c55e")!         // Green
    static let untouched = UIColor(hex: "#ef4444")!       // Red
    static let orphan = UIColor(hex: "#9ca3af")!          // Gray
    
    static let roadPrimary = UIColor(hex: "#64748b")!     // Slate
    static let roadSecondary = UIColor(hex: "#94a3b8")!   // Light Slate
    static let addressMarker = UIColor(hex: "#8b5cf6")!   // Purple
}

// MARK: - Map Layer Manager

/// Manages Mapbox layers for buildings, addresses, and roads
/// Mirrors FLYR-PRO's MapBuildingsLayer.tsx functionality
@MainActor
final class MapLayerManager {
    
    // MARK: - Layer IDs
    
    static let buildingsSourceId = "buildings-source"
    static let buildingsLayerId = "buildings-extrusion"
    
    /// Web-aligned IDs (campaign-address-points, campaign-address-points-extrusion)
    static let addressesSourceId = "campaign-address-points"
    static let addressesLayerId = "campaign-address-points-extrusion"
    
    static let roadsSourceId = "roads-source"
    static let roadsLayerId = "roads-line"
    
    // MARK: - Properties
    
    private weak var mapView: MapView?
    private let featuresService = MapFeaturesService.shared
    
    /// When false, 3D building extrusion layer is not added (campaign map shows flat map + addresses/roads only).
    var includeBuildingsLayer: Bool = true

    /// When false, address circle layer (purple pins) is not added; addresses source is still created and updated for logic.
    var includeAddressesLayer: Bool = true

    // Status filters
    var showQrScanned = true
    var showConversations = true
    var showTouched = true
    var showUntouched = true
    var showOrphans = true
    
    // MARK: - Init
    
    init(mapView: MapView) {
        self.mapView = mapView
    }
    
    // MARK: - Setup All Layers
    
    /// Set up all map layers (buildings if enabled, addresses, roads)
    func setupLayers() {
        if includeBuildingsLayer {
            setupBuildingsLayer()
        }
        setupRoadsLayer()
        setupAddressesLayer()
        setupLighting()
    }
    
    // MARK: - Buildings Layer (Fill Extrusion)
    
    /// Set up the 3D buildings fill-extrusion layer
    func setupBuildingsLayer() {
        guard let mapView = mapView else { return }
        
        // Add empty GeoJSON source
        var source = GeoJSONSource(id: Self.buildingsSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        
        // Enable promoteId for setFeatureState (real-time updates)
        source.promoteId = .string("gers_id")
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added buildings source")
        } catch {
            print("❌ [MapLayer] Error adding buildings source: \(error)")
            return
        }
        
        // Create fill-extrusion layer
        var layer = FillExtrusionLayer(id: Self.buildingsLayerId, source: Self.buildingsSourceId)
        
        // Color expression based on status priority
        // Priority: QR_SCANNED (purple) > CONVERSATIONS (blue) > TOUCHED (green) > UNTOUCHED (red)
        layer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                // QR Scanned: scans_total > 0 (purple)
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "scans_total" }
                        Exp(.get) { "scans_total" }
                        0
                    }
                    0
                }
                MapStatusColor.qrScanned
                
                // Conversations: status == "hot"
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot"
                }
                MapStatusColor.conversations
                
                // Touched: status == "visited" (includes do_not_knock)
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "visited"
                }
                MapStatusColor.touched
                
                // Default: Untouched (red)
                MapStatusColor.untouched
            }
        )
        
        // Height from properties (default 10m)
        layer.fillExtrusionHeight = .expression(
            Exp(.coalesce) {
                Exp(.get) { "height" }
                Exp(.get) { "height_m" }
                10
            }
        )
        
        // Base at ground level
        layer.fillExtrusionBase = .constant(0)
        
        // Full opacity
        layer.fillExtrusionOpacity = .constant(1.0)
        
        // Vertical gradient for depth
        layer.fillExtrusionVerticalGradient = .constant(true)
        
        // Min zoom (only show when zoomed in)
        layer.minZoom = 12
        
        // Only polygons (defense in depth: avoid FillBucket LineString errors)
        layer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        do {
            try mapView.mapboxMap.addLayer(layer)
            print("✅ [MapLayer] Added buildings fill-extrusion layer")
        } catch {
            print("❌ [MapLayer] Error adding buildings layer: \(error)")
        }
    }
    
    // MARK: - Roads Layer (Line)
    
    /// Set up the roads line layer
    func setupRoadsLayer() {
        guard let mapView = mapView else { return }
        
        // Add empty GeoJSON source
        var source = GeoJSONSource(id: Self.roadsSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added roads source")
        } catch {
            print("❌ [MapLayer] Error adding roads source: \(error)")
            return
        }
        
        // Create line layer
        var layer = LineLayer(id: Self.roadsLayerId, source: Self.roadsSourceId)
        
        // Road color based on class
        layer.lineColor = .expression(
            Exp(.match) {
                Exp(.get) { "class" }
                // Primary roads
                ["primary", "secondary", "tertiary"]
                MapStatusColor.roadPrimary
                // Default
                MapStatusColor.roadSecondary
            }
        )
        
        // Road width based on class
        layer.lineWidth = .expression(
            Exp(.match) {
                Exp(.get) { "class" }
                ["primary"]
                4.0
                ["secondary"]
                3.0
                ["tertiary"]
                2.5
                // Default
                2.0
            }
        )
        
        layer.lineCap = .constant(.round)
        layer.lineJoin = .constant(.round)
        layer.minZoom = 12
        
        do {
            if includeBuildingsLayer {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .below(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added roads line layer")
        } catch {
            print("❌ [MapLayer] Error adding roads layer: \(error)")
        }
    }

    // MARK: - Addresses Layer (Circle Fill Extrusions)
    
    /// Set up the addresses layer as 3D circle fill extrusions (web-aligned: campaign-address-points-extrusion)
    func setupAddressesLayer() {
        guard let mapView = mapView else { return }
        
        // Add empty GeoJSON source (promoteId so we can use setFeatureState for status colors)
        var source = GeoJSONSource(id: Self.addressesSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        source.promoteId = .string("id")
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added addresses source (\(Self.addressesSourceId))")
        } catch {
            print("❌ [MapLayer] Error adding addresses source: \(error)")
            return
        }
        
        guard includeAddressesLayer else { return }
        
        // Create fill-extrusion layer for address points (small 3D pillars); color by feature-state (status / scans_total)
        // Support both normalized layer status (hot, visited, not_visited) and raw API status (talked, no_answer, etc.)
        var layer = FillExtrusionLayer(id: Self.addressesLayerId, source: Self.addressesSourceId)
        layer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "scans_total" }
                        Exp(.get) { "scans_total" }
                        0
                    }
                    0
                }
                MapStatusColor.qrScanned
                // Blue: conversation / talked / appointment / hot_lead (normalized "hot" or raw)
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot"
                }
                MapStatusColor.conversations
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "talked"
                }
                MapStatusColor.conversations
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "appointment"
                }
                MapStatusColor.conversations
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot_lead"
                }
                MapStatusColor.conversations
                // Green: touched / visited / no_answer / delivered / do_not_knock / future_seller
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "visited"
                }
                MapStatusColor.touched
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "no_answer"
                }
                MapStatusColor.touched
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "delivered"
                }
                MapStatusColor.touched
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "do_not_knock"
                }
                MapStatusColor.touched
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "future_seller"
                }
                MapStatusColor.touched
                MapStatusColor.untouched
            }
        )
        layer.fillExtrusionHeight = .expression(
            Exp(.coalesce) {
                Exp(.get) { "height" }
                8
            }
        )
        layer.fillExtrusionBase = .constant(0)
        layer.fillExtrusionOpacity = .constant(1.0)
        layer.fillExtrusionVerticalGradient = .constant(true)
        layer.minZoom = 12
        layer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        do {
            if includeBuildingsLayer {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .below(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added addresses fill-extrusion layer (\(Self.addressesLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding addresses layer: \(error)")
        }
    }
    
    // MARK: - Lighting
    
    /// Set up 3D lighting for fill-extrusions
    func setupLighting() {
        guard let mapView = mapView else { return }
        
        // Configure ambient light for 3D depth
        var ambientLight = AmbientLight()
        ambientLight.color = .constant(StyleColor(.white))
        ambientLight.intensity = .constant(0.5)
        
        // Configure directional light
        var directionalLight = DirectionalLight()
        directionalLight.color = .constant(StyleColor(.white))
        directionalLight.intensity = .constant(0.6)
        directionalLight.direction = .constant([210, 30]) // Azimuth, Altitude
        directionalLight.castShadows = .constant(true)
        
        do {
            try mapView.mapboxMap.setLights(ambient: ambientLight, directional: directionalLight)
            print("✅ [MapLayer] Configured 3D lighting")
        } catch {
            print("❌ [MapLayer] Error setting lights: \(error)")
        }
    }
    
    // MARK: - Update Data
    
    /// Update buildings source with new GeoJSON data (polygon-only or empty to avoid FillBucket LineString errors).
    /// When `data` is nil, clears the source with an empty FeatureCollection. No-op when buildings layer is disabled.
    func updateBuildings(_ data: Data?) {
        guard includeBuildingsLayer, let mapView = mapView else { return }
        
        let dataToUse: Data
        if let data = data {
            dataToUse = data
        } else {
            dataToUse = Self.encodedEmptyBuildings()
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let collection = try decoder.decode(BuildingFeatureCollection.self, from: dataToUse)
            let polygonOnly = collection.features.filter { f in
                f.geometry.type == "Polygon" || f.geometry.type == "MultiPolygon"
            }
            let filtered = BuildingFeatureCollection(type: "FeatureCollection", features: polygonOnly)
            let filteredData = try JSONEncoder().encode(filtered)
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: filteredData)
            try mapView.mapboxMap.updateGeoJSONSource(withId: Self.buildingsSourceId, geoJSON: geoJSON)
            if polygonOnly.count < collection.features.count {
                print("✅ [MapLayer] Updated buildings source (\(polygonOnly.count) polygons, filtered \(collection.features.count - polygonOnly.count) non-polygons)")
            } else {
                print("✅ [MapLayer] Updated buildings source (\(polygonOnly.count) features)")
            }
        } catch {
            print("❌ [MapLayer] Error updating buildings: \(error)")
        }
    }
    
    private static func encodedEmptyBuildings() -> Data {
        (try? JSONEncoder().encode(BuildingFeatureCollection(type: "FeatureCollection", features: []))) ?? Data()
    }
    
    /// Update addresses source: convert Point features to circle-polygon features (fill extrusions) then update source
    func updateAddresses(_ data: Data) {
        guard let mapView = mapView else { return }
        
        do {
            let polygonData = try Self.convertAddressPointsToCirclePolygons(data, radiusMeters: 2.5, height: 8, segments: 20)
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: polygonData)
            try mapView.mapboxMap.updateGeoJSONSource(withId: Self.addressesSourceId, geoJSON: geoJSON)
            print("✅ [MapLayer] Updated addresses source (\(Self.addressesSourceId))")
        } catch {
            print("❌ [MapLayer] Error updating addresses: \(error)")
        }
    }
    
    /// Convert GeoJSON FeatureCollection of Point features to Polygon features (circle rings) for fill extrusion
    private static func convertAddressPointsToCirclePolygons(_ pointGeoJSONData: Data, radiusMeters: Double = 2.5, height: Double = 8, segments: Int = 20) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: pointGeoJSONData) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return pointGeoJSONData
        }
        
        let earth = 6_378_137.0
        var polygonFeatures: [[String: Any]] = []
        
        for feature in features {
            guard let geom = feature["geometry"] as? [String: Any],
                  geom["type"] as? String == "Point",
                  let coords = geom["coordinates"] as? [Double], coords.count >= 2 else { continue }
            let lon = coords[0]
            let lat = coords[1]
            guard lon.isFinite, lat.isFinite, abs(lat) < 89 else { continue }
            let latRad = lat * .pi / 180
            let cosLat = max(cos(latRad), 1e-10)
            var ring: [[Double]] = []
            for i in 0...segments {
                let theta = 2 * .pi * Double(i) / Double(segments)
                let dx = radiusMeters * cos(theta)
                let dy = radiusMeters * sin(theta)
                let dLat = (dy / earth) * 180 / .pi
                let dLon = (dx / (earth * cosLat)) * 180 / .pi
                let x = lon + dLon
                let y = lat + dLat
                guard x.isFinite, y.isFinite else { continue }
                ring.append([x, y])
            }
            guard ring.count == segments + 1 else { continue }
            var props = (feature["properties"] as? [String: Any]) ?? [:]
            props["height"] = height.isFinite ? height : 8
            // promoteId is "id" – ensure id is in properties and at root so setFeatureState can match
            var featureId: String?
            if let existing = props["id"] as? String, !existing.isEmpty {
                featureId = existing
            } else if let rootId = feature["id"] as? String, !rootId.isEmpty {
                featureId = rootId
                props["id"] = rootId
            } else if let rootId = feature["id"] as? Int {
                featureId = String(rootId)
                props["id"] = featureId
            }
            // Normalize UUID strings to lowercase so they match Postgres JSON and setFeatureState lookup
            if let idStr = featureId {
                let normalizedId = idStr.contains("-") ? idStr.lowercased() : idStr
                props["id"] = normalizedId
                featureId = normalizedId
            }
            var polygonFeature: [String: Any] = [
                "type": "Feature",
                "geometry": ["type": "Polygon", "coordinates": [ring]],
                "properties": props
            ]
            if let idStr = featureId {
                polygonFeature["id"] = idStr
            }
            polygonFeatures.append(polygonFeature)
        }
        
        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": polygonFeatures
        ]
        return try JSONSerialization.data(withJSONObject: collection)
    }
    
    /// Update roads source with new GeoJSON data
    func updateRoads(_ data: Data) {
        guard let mapView = mapView else { return }
        
        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            try mapView.mapboxMap.updateGeoJSONSource(withId: Self.roadsSourceId, geoJSON: geoJSON)
            print("✅ [MapLayer] Updated roads source")
        } catch {
            print("❌ [MapLayer] Error updating roads: \(error)")
        }
    }
    
    // MARK: - Real-time Feature State Updates
    
    /// Update a building's feature state for instant color change (no re-render).
    /// Uses lowercase featureId so it matches promoteId values in the source (buildings use lowercase gers_id).
    func updateBuildingState(gersId: String, status: String, scansTotal: Int) {
        guard let mapView = mapView else { return }
        let featureId = gersId.lowercased()

        let state: [String: Any] = [
            "status": status,
            "scans_total": scansTotal,
            "qr_scanned": scansTotal > 0
        ]

        mapView.mapboxMap.setFeatureState(
            sourceId: Self.buildingsSourceId,
            sourceLayerId: nil,
            featureId: featureId,
            state: state
        ) { result in
            switch result {
            case .success:
                print("✅ [MapLayer] Updated feature state for \(gersId)")
            case .failure(let error):
                print("❌ [MapLayer] Error updating feature state: \(error)")
            }
        }
    }

    /// Update an address circle's feature state (for 3D address pillars). Use addressId (UUID string) as featureId.
    /// Normalizes addressId to lowercase so it matches Postgres JSON (UUIDs are lowercase there).
    func updateAddressState(addressId: String, status: String, scansTotal: Int) {
        guard let mapView = mapView else { return }
        let normalizedId = addressId.lowercased()

        let state: [String: Any] = [
            "status": status,
            "scans_total": scansTotal,
            "qr_scanned": scansTotal > 0
        ]

        mapView.mapboxMap.setFeatureState(
            sourceId: Self.addressesSourceId,
            sourceLayerId: nil,
            featureId: normalizedId,
            state: state
        ) { result in
            switch result {
            case .success:
                print("✅ [MapLayer] Updated address feature state for \(addressId)")
            case .failure(let error):
                print("❌ [MapLayer] Error updating address feature state: \(error)")
            }
        }
    }
    
    // MARK: - Status Filters
    
    /// Update layer filter based on status toggles
    func updateStatusFilter() {
        guard let mapView = mapView else { return }
        
        // Build filter conditions
        var conditions: [Exp] = []
        
        if showQrScanned {
            conditions.append(
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "scans_total" }
                        Exp(.get) { "scans_total" }
                        0
                    }
                    0
                }
            )
        }
        
        if showConversations {
            conditions.append(
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot"
                }
            )
        }
        
        if showTouched {
            conditions.append(
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "visited"
                }
            )
        }
        
        if showUntouched {
            conditions.append(
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "not_visited"
                }
            )
        }
        
        // Combine with OR
        let filter: Exp
        if conditions.isEmpty {
            // Hide all
            filter = Exp(.eq) { 1; 0 }
        } else if conditions.count == 4 {
            // Show all - no filter needed
            filter = Exp(.eq) { 1; 1 }
        } else {
            filter = Exp(.any) { conditions }
        }
        
        do {
            try mapView.mapboxMap.updateLayer(withId: Self.buildingsLayerId, type: FillExtrusionLayer.self) { layer in
                layer.filter = filter
            }
            print("✅ [MapLayer] Updated status filter")
        } catch {
            print("❌ [MapLayer] Error updating filter: \(error)")
        }
    }
    
    // MARK: - Address Tap Result
    
    /// Result of tapping the addresses layer (3D circles). Decodes from feature properties.
    struct AddressTapResult: Codable {
        let addressId: UUID
        let formatted: String
        let gersId: String?
        let buildingGersId: String?
        let houseNumber: String?
        let streetName: String?
        
        enum CodingKeys: String, CodingKey {
            case addressId = "id"
            case formatted
            case gersId = "gers_id"
            case buildingGersId = "building_gers_id"
            case houseNumber = "house_number"
            case streetName = "street_name"
        }
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let idString = try c.decode(String.self, forKey: .addressId)
            guard let uuid = UUID(uuidString: idString) else {
                throw DecodingError.dataCorruptedError(forKey: .addressId, in: c, debugDescription: "Invalid UUID string")
            }
            addressId = uuid
            formatted = try c.decodeIfPresent(String.self, forKey: .formatted) ?? ""
            gersId = try c.decodeIfPresent(String.self, forKey: .gersId)
            buildingGersId = try c.decodeIfPresent(String.self, forKey: .buildingGersId)
            houseNumber = try c.decodeIfPresent(String.self, forKey: .houseNumber)
            streetName = try c.decodeIfPresent(String.self, forKey: .streetName)
        }
    }
    
    // MARK: - Click Handling
    
    /// Unwrap Turf JSONValue properties to [String: Any] so SafeJSON/JSONDecoder get real types (not description strings).
    private func unwrapTurfProperties(_ properties: [String: JSONValue?]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, val) in properties {
            if let j = val {
                result[key] = unwrapTurfValue(j)
            } else {
                result[key] = NSNull()
            }
        }
        return result
    }
    
    private func unwrapTurfValue(_ value: JSONValue) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .object(let o): return unwrapTurfProperties(o)
        case .array(let a): return a.map { elem in elem.map { unwrapTurfValue($0) } ?? NSNull() }
        }
    }
    
    /// Get building at tap location (async via completion)
    func getBuildingAt(point: CGPoint, completion: @escaping (BuildingProperties?) -> Void) {
        guard let mapView = mapView else { completion(nil); return }
        
        let options = RenderedQueryOptions(layerIds: [Self.buildingsLayerId], filter: nil)
        mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { result in
            switch result {
            case .success(let features):
                if let first = features.first,
                   let properties = first.queriedFeature.feature.properties {
                    
                    // Unwrap Turf JSONValue to [String: Any] so numbers stay numbers (SafeJSON would turn them into description strings)
                    let converted = self.unwrapTurfProperties(properties)
                    let sanitized = SafeJSON.sanitize(converted)
                    
                    guard JSONSerialization.isValidJSONObject(sanitized) else {
                        print("❌ [MapLayer] Sanitized properties are still not valid JSON")
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    
                    guard let data = SafeJSON.data(from: sanitized) else {
                        print("❌ [MapLayer] Failed to serialize sanitized properties to JSON")
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    
                    do {
                        let building = try JSONDecoder().decode(BuildingProperties.self, from: data)
                        DispatchQueue.main.async { completion(building) }
                    } catch {
                        print("❌ [MapLayer] Failed to decode BuildingProperties: \(error)")
                        print("🔍 [MapLayer] JSON data: \(String(data: data, encoding: .utf8) ?? "invalid UTF-8")")
                        DispatchQueue.main.async { completion(nil) }
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            case .failure(let error):
                print("❌ [MapLayer] Error querying features: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    /// Get address at tap location (async via completion). Use when display mode is Addresses (3D circles).
    func getAddressAt(point: CGPoint, completion: @escaping (AddressTapResult?) -> Void) {
        guard let mapView = mapView else { completion(nil); return }
        
        let options = RenderedQueryOptions(layerIds: [Self.addressesLayerId], filter: nil)
        mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let features):
                if let first = features.first,
                   let properties = first.queriedFeature.feature.properties {
                    let converted = self.unwrapTurfProperties(properties)
                    let sanitized = SafeJSON.sanitize(converted)
                    guard JSONSerialization.isValidJSONObject(sanitized),
                          let data = SafeJSON.data(from: sanitized) else {
                        DispatchQueue.main.async { completion(nil) }
                        return
                    }
                    do {
                        let addressResult = try JSONDecoder().decode(AddressTapResult.self, from: data)
                        DispatchQueue.main.async { completion(addressResult) }
                    } catch {
                        print("❌ [MapLayer] Failed to decode AddressTapResult: \(error)")
                        DispatchQueue.main.async { completion(nil) }
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            case .failure(let error):
                print("❌ [MapLayer] Error querying address features: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    // MARK: - Cleanup
    
    /// Remove all layers and sources
    func cleanup() {
        guard let mapView = mapView else { return }
        
        // Remove layers
        try? mapView.mapboxMap.removeLayer(withId: Self.buildingsLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressesLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.roadsLayerId)
        
        // Remove sources
        try? mapView.mapboxMap.removeSource(withId: Self.buildingsSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.addressesSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.roadsSourceId)
        
        print("✅ [MapLayer] Cleaned up all layers and sources")
    }
}

// MARK: - UIColor Hex Extension

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
