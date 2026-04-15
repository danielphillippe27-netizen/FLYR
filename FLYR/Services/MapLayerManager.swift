import Foundation
import MapboxMaps
import UIKit
import CoreLocation

// MARK: - Status Colors

/// Map status color configuration. Purple = QR scanned (align with web).
enum MapStatusColor {
    static let qrScanned = UIColor(hex: "#8b5cf6")!      // Purple (QR codes)
    static let conversations = UIColor(hex: "#3b82f6")!   // Blue
    static let pendingVisited = UIColor(hex: "#f59e0b")!   // Amber
    static let touched = UIColor(hex: "#22c55e")!         // Green
    static let doNotKnock = UIColor(hex: "#9ca3af")!      // Gray (do not knock)
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
    static let townhomeOverlaySourceId = "townhome-status-source"
    static let townhomeOverlayLayerId = "townhome-status-extrusion"
    
    /// Web-aligned IDs (campaign-address-points, campaign-address-points-extrusion)
    static let addressesSourceId = "campaign-address-points"
    static let addressesLayerId = "campaign-address-points-extrusion"
    static let addressNumbersSourceId = "campaign-address-numbers"
    static let addressNumbersLayerId = "campaign-address-numbers-layer"
    static let manualAddressPreviewSourceId = "manual-address-preview-source"
    static let manualAddressPreviewLayerId = "manual-address-preview-extrusion"
    
    static let roadsSourceId = "roads-source"
    static let roadsLayerId = "roads-line"
    
    // MARK: - Address markers zoom (3D circles + house number labels)
    
    /// Shared layer min zoom — labels and circle extrusions stay off until zoomed in past typical block overview.
    private static let addressMarkersLayerMinZoom: Double = 15.0
    
    /// Opacity vs camera zoom; used for both house number symbols and address circle extrusions so they appear together.
    private static var addressMarkersZoomOpacityExpression: Exp {
        Exp(.interpolate) {
            Exp(.linear)
            Exp(.zoom)
            15.0
            0.0
            15.4
            0.28
            15.9
            0.62
            16.4
            0.9
            17.0
            1.0
        }
    }
    
    // MARK: - Properties
    
    private weak var mapView: MapView?
    private let featuresService = MapFeaturesService.shared
    
    /// When false, 3D building extrusion layer is not added (campaign map shows flat map + addresses/roads only).
    var includeBuildingsLayer: Bool = true

    /// When false, address circle layer (purple pins) is not added; addresses source is still created and updated for logic.
    var includeAddressesLayer: Bool = true

    /// When false, campaign roads are still loaded into the source but we skip the visual overlay so
    /// the base map's native road styling stays unchanged.
    var showRoadOverlay: Bool = true

    // Status filters
    var showQrScanned = true
    var showConversations = true
    var showTouched = true
    var showUntouched = true
    var showOrphans = true
    private var lastBuildingsSourceSignature: Int?
    private var lastTownhomeOverlaySignature: Int?
    private var lastAddressesSourceSignature: Int?
    private var lastRoadsSourceSignature: Int?
    private var cachedAddressPointSignature: Int?
    private var cachedAddressPolygonData: Data?
    private var lastAddressNumbersSourceSignature: Int?
    private var lastAddressNumbersVisible: Bool?
    
    // MARK: - Init
    
    init(mapView: MapView) {
        self.mapView = mapView
    }
    
    // MARK: - Setup All Layers
    
    /// Set up all map layers (buildings if enabled, addresses, roads)
    func setupLayers() {
        if includeBuildingsLayer {
            setupBuildingsLayer()
            setupTownhomeStatusLayer()
        }
        setupRoadsLayer()
        setupAddressesLayer()
        setupAddressNumbersLayer()
        setupManualAddressPreviewLayer()
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
        source.promoteId2 = .constant("gers_id")
        
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
                
                // Do not knock: gray (distinct from visited green)
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "do_not_knock"
                }
                MapStatusColor.doNotKnock

                // Pending local confirmation.
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "pending_visited"
                }
                MapStatusColor.pendingVisited

                // Touched: status == "visited"
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

    /// Set up a townhouse-only overlay layer that can render mixed per-unit statuses
    /// on top of a single building footprint.
    func setupTownhomeStatusLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.townhomeOverlaySourceId)
        source.data = .featureCollection(FeatureCollection(features: []))

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding townhouse overlay source: \(error)")
            return
        }

        var layer = FillExtrusionLayer(id: Self.townhomeOverlayLayerId, source: Self.townhomeOverlaySourceId)
        layer.fillExtrusionColor = .expression(
            Exp(.switchCase) {
                Exp(.eq) {
                    Exp(.get) { "segment_status" }
                    "hot"
                }
                MapStatusColor.conversations

                Exp(.eq) {
                    Exp(.get) { "segment_status" }
                    "do_not_knock"
                }
                MapStatusColor.doNotKnock

                Exp(.eq) {
                    Exp(.get) { "segment_status" }
                    "visited"
                }
                MapStatusColor.touched

                MapStatusColor.untouched
            }
        )
        layer.fillExtrusionHeight = .expression(
            Exp(.coalesce) {
                Exp(.get) { "overlay_height" }
                Exp(.get) { "height" }
                Exp(.get) { "height_m" }
                10.2
            }
        )
        layer.fillExtrusionBase = .expression(
            Exp(.coalesce) {
                Exp(.get) { "overlay_base" }
                0.2
            }
        )
        layer.fillExtrusionOpacity = .constant(1.0)
        layer.fillExtrusionVerticalGradient = .constant(true)
        layer.minZoom = 12
        layer.filter = Exp(.eq) {
            Exp(.geometryType)
            "Polygon"
        }

        do {
            try mapView.mapboxMap.addLayer(layer)
            print("✅ [MapLayer] Added townhouse overlay layer")
        } catch {
            print("❌ [MapLayer] Error adding townhouse overlay layer: \(error)")
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
        
        guard showRoadOverlay else {
            print("ℹ️ [MapLayer] Road overlay hidden; campaign roads remain loaded in source only")
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
        source.promoteId2 = .constant("id")
        
        do {
            try mapView.mapboxMap.addSource(source)
            print("✅ [MapLayer] Added addresses source (\(Self.addressesSourceId))")
        } catch {
            print("❌ [MapLayer] Error adding addresses source: \(error)")
            return
        }
        
        // Always add the layer so it exists for visibility toggling (includeAddressesLayer is only for default visibility;
        // if we skip adding when false, the layer can be missing if updateLayerVisibility ran before style loaded).
        
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
                // Do not knock: gray (distinct from visited green)
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "do_not_knock"
                }
                MapStatusColor.doNotKnock
                Exp(.eq) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "pending_visited"
                }
                MapStatusColor.pendingVisited
                // Green: touched / visited / no_answer / delivered / future_seller
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
        layer.fillExtrusionOpacity = .expression(Self.addressMarkersZoomOpacityExpression)
        layer.fillExtrusionVerticalGradient = .constant(true)
        layer.minZoom = Self.addressMarkersLayerMinZoom
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

    private func setupAddressNumbersLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.addressNumbersSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))
        source.promoteId2 = .constant("id")

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding address numbers source: \(error)")
            return
        }

        var layer = SymbolLayer(id: Self.addressNumbersLayerId, source: Self.addressNumbersSourceId)
        layer.textField = .expression(Exp(.get) { "house_number_label" })
        layer.textSize = .expression(
            Exp(.interpolate) {
                Exp(.linear)
                Exp(.zoom)
                17
                10
                20
                13
            }
        )
        layer.textColor = .constant(StyleColor(.white))
        layer.textHaloColor = .constant(StyleColor(.black))
        layer.textHaloWidth = .constant(1.4)
        layer.textHaloBlur = .constant(0.4)
        layer.textAnchor = .constant(.center)
        layer.textJustify = .constant(.center)
        layer.textOffset = .constant([0, 0])
        layer.textPitchAlignment = .constant(.map)
        layer.textVariableAnchor = .constant([.center, .top, .bottom, .left, .right])
        layer.symbolSortKey = .expression(
            Exp(.coalesce) {
                Exp(.get) { "label_priority" }
                100
            }
        )
        layer.symbolSpacing = .constant(32)
        layer.symbolAvoidEdges = .constant(true)
        layer.symbolZElevate = .constant(true)
        layer.textAllowOverlap = .constant(false)
        layer.textIgnorePlacement = .constant(false)
        layer.textOptional = .constant(false)
        layer.textOpacity = .expression(Self.addressMarkersZoomOpacityExpression)
        layer.minZoom = Self.addressMarkersLayerMinZoom
        layer.visibility = .constant(.none)
        layer.filter = Exp(.all) {
            Exp(.eq) {
                Exp(.geometryType)
                "Point"
            }
            Exp(.neq) {
                Exp(.coalesce) {
                    Exp(.get) { "house_number_label" }
                    ""
                }
                ""
            }
        }

        do {
            let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))
            if layerIds.contains(Self.manualAddressPreviewLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.manualAddressPreviewLayerId))
            } else if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.buildingsLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
            print("✅ [MapLayer] Added address numbers symbol layer (\(Self.addressNumbersLayerId))")
        } catch {
            print("❌ [MapLayer] Error adding address numbers layer: \(error)")
        }
    }

    func setupManualAddressPreviewLayer() {
        guard let mapView = mapView else { return }

        var source = GeoJSONSource(id: Self.manualAddressPreviewSourceId)
        source.data = .featureCollection(FeatureCollection(features: []))

        do {
            try mapView.mapboxMap.addSource(source)
        } catch {
            print("❌ [MapLayer] Error adding manual address preview source: \(error)")
            return
        }

        var layer = FillExtrusionLayer(id: Self.manualAddressPreviewLayerId, source: Self.manualAddressPreviewSourceId)
        layer.fillExtrusionColor = .constant(StyleColor(UIColor(hex: "#f59e0b")!))
        layer.fillExtrusionHeight = .expression(
            Exp(.coalesce) {
                Exp(.get) { "height" }
                9
            }
        )
        layer.fillExtrusionBase = .constant(0)
        layer.fillExtrusionOpacity = .constant(0.92)
        layer.fillExtrusionVerticalGradient = .constant(true)
        layer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }

        let layerIds = Set(mapView.mapboxMap.allLayerIdentifiers.map(\.id))

        do {
            if layerIds.contains(Self.buildingsLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.buildingsLayerId))
            } else if layerIds.contains(Self.addressesLayerId) {
                try mapView.mapboxMap.addLayer(layer, layerPosition: .above(Self.addressesLayerId))
            } else {
                try mapView.mapboxMap.addLayer(layer)
            }
        } catch {
            print("❌ [MapLayer] Error adding manual address preview layer: \(error)")
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
    /// When `data` is nil, clears the source with an empty FeatureCollection.
    /// Always updates the source when map is available so switching display mode shows correct data.
    func updateBuildings(_ data: Data?) {
        guard let mapView = mapView else { return }
        
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
            let signature = Self.sourceSignature(for: filteredData)
            guard lastBuildingsSourceSignature != signature else { return }
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: filteredData)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.buildingsSourceId, geoJSON: geoJSON)
            lastBuildingsSourceSignature = signature
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

    private static func sourceSignature(for data: Data) -> Int {
        var hasher = Hasher()
        hasher.combine(data.count)
        hasher.combine(data)
        return hasher.finalize()
    }

    func updateTownhomeStatusOverlay(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]],
        addressStatuses: [UUID: AddressStatus]
    ) {
        guard let mapView = mapView else { return }

        let data = Self.buildTownhomeStatusOverlayGeoJSON(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding,
            addressStatuses: addressStatuses
        ) ?? Self.encodedEmptyTownhomeOverlay()
        let signature = Self.sourceSignature(for: data)
        guard lastTownhomeOverlaySignature != signature else { return }

        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.townhomeOverlaySourceId, geoJSON: geoJSON)
            lastTownhomeOverlaySignature = signature
            let overlayCount = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["features"] as? [[String: Any]] }?
                .count ?? 0
            print("✅ [MapLayer] Updated townhouse overlay source (\(overlayCount) features)")
        } catch {
            print("❌ [MapLayer] Error updating townhouse overlay: \(error)")
        }
    }

    private static func encodedEmptyTownhomeOverlay() -> Data {
        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": [] as [[String: Any]]
        ]
        return (try? JSONSerialization.data(withJSONObject: collection)) ?? Data()
    }

    static func buildTownhomeStatusOverlayGeoJSON(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]],
        addressStatuses: [UUID: AddressStatus]
    ) -> Data? {
        let addressContextsById = Dictionary(
            uniqueKeysWithValues: addresses.compactMap { feature -> (UUID, OverlayAddressContext)? in
                guard let idString = feature.properties.id ?? feature.id,
                      let id = UUID(uuidString: idString) else { return nil }
                return (
                    id,
                    OverlayAddressContext(
                        id: id,
                        buildingGersId: (feature.properties.buildingGersId ?? feature.properties.gersId ?? "").lowercased(),
                        houseNumber: feature.properties.houseNumber,
                        streetName: feature.properties.streetName,
                        formatted: feature.properties.formatted
                    )
                )
            }
        )

        var featureDictionaries: [[String: Any]] = []

        for building in buildings {
            let gersId = (building.properties.canonicalBuildingIdentifier ?? building.id ?? "").lowercased()
            guard !gersId.isEmpty else { continue }

            let linkedAddresses = orderedAddressesForTownhome(
                gersId: gersId,
                fallbackAddressId: building.properties.addressId,
                addressesById: addressContextsById,
                orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
            )

            guard linkedAddresses.count > 1 else { continue }
            guard building.properties.isTownhome || building.properties.unitsCount > 1 || (building.properties.addressCount ?? 0) > 1 else {
                continue
            }

            let orderedStatuses = linkedAddresses.map { overlaySegmentStatus(for: addressStatuses[$0.id]) }
            guard Set(orderedStatuses).count > 1 else { continue }

            let statusRuns = collapseStatusRuns(orderedStatuses)
            let polygons = polygonRings(from: building.geometry)
            guard !polygons.isEmpty else { continue }

            var runningCount = 0
            for (index, run) in statusRuns.enumerated() {
                let startFraction = Double(runningCount) / Double(linkedAddresses.count)
                runningCount += run.count
                let endFraction = Double(runningCount) / Double(linkedAddresses.count)

                guard let clippedPolygons = slicedPolygons(
                    polygons: polygons,
                    startFraction: startFraction,
                    endFraction: endFraction
                ), !clippedPolygons.isEmpty else {
                    continue
                }

                let height = max(building.properties.heightM ?? building.properties.height, 10)
                let properties: [String: Any] = [
                    "gers_id": gersId,
                    "segment_status": run.status,
                    "height": height,
                    "overlay_height": height + 0.15,
                    "overlay_base": 0.15
                ]

                var feature: [String: Any] = [
                    "type": "Feature",
                    "properties": properties,
                    "id": "\(gersId)-segment-\(index)"
                ]
                if clippedPolygons.count == 1 {
                    feature["geometry"] = [
                        "type": "Polygon",
                        "coordinates": [clippedPolygons[0]]
                    ]
                } else {
                    feature["geometry"] = [
                        "type": "MultiPolygon",
                        "coordinates": clippedPolygons.map { [$0] }
                    ]
                }
                featureDictionaries.append(feature)
            }
        }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": featureDictionaries
        ]
        return try? JSONSerialization.data(withJSONObject: collection)
    }
    
    /// Update addresses source: convert Point features to circle-polygon features (fill extrusions) then update source
    func updateAddressNumberLabels(
        addresses: [AddressFeature],
        buildings: [BuildingFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) {
        guard let mapView = mapView else { return }

        do {
            let labelPointData = try Self.smartAddressLabelPointCollection(
                addresses: addresses,
                buildings: buildings,
                orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
            )
            let labelSignature = Self.sourceSignature(for: labelPointData)
            guard lastAddressNumbersSourceSignature != labelSignature else { return }
            let labelGeoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: labelPointData)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.addressNumbersSourceId, geoJSON: labelGeoJSON)
            lastAddressNumbersSourceSignature = labelSignature
        } catch {
            print("❌ [MapLayer] Error updating address number labels: \(error)")
        }
    }

    func updateAddresses(_ data: Data) {
        guard let mapView = mapView else { return }
        
        do {
            let pointSignature = Self.sourceSignature(for: data)
            let pointCount = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { $0["features"] as? [[String: Any]] }?.count ?? 0
            let polygonData: Data
            if cachedAddressPointSignature == pointSignature, let cachedAddressPolygonData {
                polygonData = cachedAddressPolygonData
            } else {
                polygonData = try Self.convertAddressPointsToCirclePolygons(data, radiusMeters: 2.7, height: 10, segments: 20)
                cachedAddressPointSignature = pointSignature
                cachedAddressPolygonData = polygonData
            }
            let polygonSignature = Self.sourceSignature(for: polygonData)
            guard lastAddressesSourceSignature != polygonSignature else { return }
            let polygonCount = (try? JSONSerialization.jsonObject(with: polygonData) as? [String: Any]).flatMap { $0["features"] as? [[String: Any]] }?.count ?? 0
            print("🔍 [MapLayer] Address circles: \(pointCount) points → \(polygonCount) extrusion polygons")
            if polygonCount == 0, pointCount > 0 {
                print("⚠️ [MapLayer] No circle polygons produced; check Point geometry in address GeoJSON")
            }
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: polygonData)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.addressesSourceId, geoJSON: geoJSON)
            lastAddressesSourceSignature = polygonSignature
            if polygonCount > 0 {
                print("✅ [MapLayer] Updated addresses source (\(Self.addressesSourceId)) features=\(polygonCount) (layer minZoom=\(Self.addressMarkersLayerMinZoom))")
            } else {
                print("✅ [MapLayer] Updated addresses source (\(Self.addressesSourceId)) features=0")
            }
        } catch {
            print("❌ [MapLayer] Error updating addresses: \(error)")
        }
    }

    func updateManualAddressPreview(coordinate: CLLocationCoordinate2D?) {
        guard let mapView = mapView else { return }
        guard mapView.mapboxMap.sourceExists(withId: Self.manualAddressPreviewSourceId) else { return }

        let geoJSON: GeoJSONObject
        if let coordinate {
            do {
                let pointData = try Self.pointFeatureCollectionData(
                    coordinate: coordinate,
                    id: "manual-address-preview",
                    properties: [
                        "id": "manual-address-preview",
                        "height": 11
                    ]
                )
                let polygonData = try Self.convertAddressPointsToCirclePolygons(
                    pointData,
                    radiusMeters: 2.7,
                    height: 11,
                    segments: 24
                )
                geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: polygonData)
            } catch {
                print("❌ [MapLayer] Error updating manual address preview: \(error)")
                return
            }
        } else {
            geoJSON = .featureCollection(FeatureCollection(features: []))
        }

        mapView.mapboxMap.updateGeoJSONSource(
            withId: Self.manualAddressPreviewSourceId,
            geoJSON: geoJSON
        )
    }

    func clearManualAddressPreview() {
        updateManualAddressPreview(coordinate: nil)
    }

    func updateAddressNumberLabelVisibility(isVisible: Bool) {
        guard let mapView = mapView else { return }
        guard lastAddressNumbersVisible != isVisible else { return }
        guard mapView.mapboxMap.layerExists(withId: Self.addressNumbersLayerId) else { return }

        do {
            try mapView.mapboxMap.updateLayer(withId: Self.addressNumbersLayerId, type: SymbolLayer.self) {
                $0.visibility = .constant(isVisible ? .visible : .none)
            }
            lastAddressNumbersVisible = isVisible
        } catch {
            print("❌ [MapLayer] Error updating address number label visibility: \(error)")
        }
    }
    
    /// Extract centroid [lon, lat] from Polygon or MultiPolygon geometry coordinates (handles NSArray/NSNumber from JSONSerialization).
    private static func centroidFromGeometryCoordinates(_ coordsAny: Any?, geomType: String) -> [Double]? {
        guard let coordsAny = coordsAny else { return nil }
        let ring: [[Double]]?
        if geomType == "Polygon" {
            ring = firstRingFromPolygonCoords(coordsAny)
        } else if geomType == "MultiPolygon" {
            ring = firstRingFromMultiPolygonCoords(coordsAny)
        } else {
            return nil
        }
        guard let firstRing = ring, !firstRing.isEmpty else { return nil }
        var sumLon = 0.0, sumLat = 0.0
        for pt in firstRing {
            if pt.count >= 2 {
                sumLon += pt[0]
                sumLat += pt[1]
            }
        }
        let n = Double(firstRing.count)
        return [sumLon / n, sumLat / n]
    }
    
    private static func firstRingFromPolygonCoords(_ any: Any) -> [[Double]]? {
        guard let arr = any as? [Any], let first = arr.first else { return nil }
        return arrayOfDoublePairs(from: first)
    }
    
    private static func firstRingFromMultiPolygonCoords(_ any: Any) -> [[Double]]? {
        guard let polys = any as? [Any], let firstPoly = polys.first else { return nil }
        return firstRingFromPolygonCoords(firstPoly)
    }
    
    private static func arrayOfDoublePairs(from any: Any) -> [[Double]]? {
        guard let arr = any as? [Any] else { return nil }
        var out: [[Double]] = []
        for item in arr {
            if let pair = doublePair(from: item) { out.append(pair) }
        }
        return out.isEmpty ? nil : out
    }
    
    private static func doublePair(from any: Any) -> [Double]? {
        guard let arr = any as? [Any], arr.count >= 2 else { return nil }
        let a = numberToDouble(arr[0])
        let b = numberToDouble(arr[1])
        guard let x = a, let y = b else { return nil }
        return [x, y]
    }
    
    private static func numberToDouble(_ any: Any) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let i = any as? Int { return Double(i) }
        return nil
    }
    
    /// Extract [lon, lat] from Point geometry coordinates (handles NSArray/NSNumber from JSONSerialization).
    private static func pointCoordinatesFromAny(_ any: Any) -> [Double]? {
        guard let arr = any as? [Any], arr.count >= 2,
              let lon = numberToDouble(arr[0]), let lat = numberToDouble(arr[1]) else { return nil }
        return [lon, lat]
    }
    
    /// Build a Point FeatureCollection from building polygon centroids (fallback when campaign has no address points).
    /// Circle extrusions can then be drawn at each building center.
    private static func pointFeatureCollectionFromBuildingCentroids(_ buildingGeoJSONData: Data) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: buildingGeoJSONData) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return try JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": [] as [[String: Any]]])
        }
        var pointFeatures: [[String: Any]] = []
        for feature in features {
            guard let geom = feature["geometry"] as? [String: Any],
                  let geomType = geom["type"] as? String else { continue }
            guard let coords = centroidFromGeometryCoordinates(geom["coordinates"], geomType: geomType),
                  coords[0].isFinite, coords[1].isFinite, abs(coords[1]) < 89 else { continue }
            var props = (feature["properties"] as? [String: Any]) ?? [:]
            // Prefer address_id so setFeatureState(addressId) matches; fall back to building_id/gers_id/id.
            var idStr: String?
            if let s = props["address_id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = props["building_id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = props["gers_id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = props["id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let s = feature["id"] as? String, !s.isEmpty { idStr = s }
            if idStr == nil, let idInt = feature["id"] as? Int { idStr = String(idInt) }
            if idStr == nil, let idNum = feature["id"] as? NSNumber { idStr = idNum.stringValue }
            if let id = idStr { props["id"] = id.contains("-") ? id.lowercased() : id }
            var pointFeature: [String: Any] = [
                "type": "Feature",
                "geometry": ["type": "Point", "coordinates": coords],
                "properties": props
            ]
            if let id = idStr { pointFeature["id"] = id }
            pointFeatures.append(pointFeature)
        }
        let collection: [String: Any] = ["type": "FeatureCollection", "features": pointFeatures]
        return try JSONSerialization.data(withJSONObject: collection)
    }

    private static func pointFeatureCollectionData(
        coordinate: CLLocationCoordinate2D,
        id: String,
        properties: [String: Any]
    ) throws -> Data {
        let feature: [String: Any] = [
            "type": "Feature",
            "id": id,
            "geometry": [
                "type": "Point",
                "coordinates": [coordinate.longitude, coordinate.latitude]
            ],
            "properties": properties
        ]
        return try JSONSerialization.data(
            withJSONObject: [
                "type": "FeatureCollection",
                "features": [feature]
            ]
        )
    }

    private static func smartAddressLabelPointCollection(
        addresses: [AddressFeature],
        buildings: [BuildingFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) throws -> Data {
        let buildingContexts = labelBuildingContexts(
            buildings: buildings,
            addresses: addresses,
            orderedAddressIdsByBuilding: orderedAddressIdsByBuilding
        )

        var buildingByIdentifier: [String: LabelBuildingContext] = [:]
        var buildingByAddressId: [UUID: LabelBuildingContext] = [:]
        for context in buildingContexts {
            for identifier in context.identifiers {
                buildingByIdentifier[identifier] = context
            }
            for addressId in context.orderedAddressIds {
                buildingByAddressId[addressId] = context
            }
        }

        let pointFeatures: [[String: Any]] = addresses.compactMap { feature in
            let featureProperties: [String: Any] = [
                "id": feature.properties.id as Any,
                "address_id": feature.properties.id as Any,
                "house_number": feature.properties.houseNumber as Any,
                "formatted": feature.properties.formatted as Any
            ]

            guard let addressIdString = normalizedFeatureIdentifier(
                feature: ["id": feature.id as Any],
                properties: featureProperties
            ) else {
                return nil
            }

            let houseLabel = normalizedHouseNumberLabel(from: featureProperties)
            guard !houseLabel.isEmpty else { return nil }
            guard let baseCoordinate = CampaignTargetResolver.coordinate(for: feature.geometry) else { return nil }

            let addressUUID = UUID(uuidString: addressIdString)
            let buildingIdentifiers = [
                feature.properties.buildingGersId,
                feature.properties.gersId
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

            let linkedBuilding = addressUUID.flatMap { buildingByAddressId[$0] }
                ?? buildingIdentifiers.compactMap { buildingByIdentifier[$0] }.first

            let resolvedCoordinate: CLLocationCoordinate2D
            let labelPriority: Double

            if let linkedBuilding {
                let totalAddresses = max(linkedBuilding.orderedAddressIds.count, linkedBuilding.addressCount, 1)
                let addressIndex = addressUUID.flatMap { uuid in
                    linkedBuilding.orderedAddressIds.firstIndex(of: uuid)
                } ?? 0
                resolvedCoordinate = preferredLabelCoordinate(
                    baseCoordinate: baseCoordinate,
                    building: linkedBuilding,
                    addressIndex: addressIndex,
                    totalAddresses: totalAddresses
                )
                labelPriority = labelPriorityValue(
                    building: linkedBuilding,
                    totalAddresses: totalAddresses,
                    addressIndex: addressIndex
                )
            } else {
                resolvedCoordinate = baseCoordinate
                labelPriority = 90
            }

            return [
                "type": "Feature",
                "id": addressIdString,
                "geometry": [
                    "type": "Point",
                    "coordinates": [resolvedCoordinate.longitude, resolvedCoordinate.latitude]
                ],
                "properties": [
                    "id": addressIdString,
                    "house_number_label": houseLabel,
                    "label_priority": labelPriority
                ]
            ]
        }

        return try JSONSerialization.data(withJSONObject: [
            "type": "FeatureCollection",
            "features": pointFeatures
        ])
    }

    private static func normalizedFeatureIdentifier(feature: [String: Any], properties: [String: Any]) -> String? {
        let candidates: [Any?] = [
            properties["id"],
            properties["address_id"],
            feature["id"]
        ]

        for candidate in candidates {
            if let string = candidate as? String, !string.isEmpty {
                return string.contains("-") ? string.lowercased() : string
            }
            if let int = candidate as? Int {
                return String(int)
            }
            if let number = candidate as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func normalizedHouseNumberLabel(from properties: [String: Any]) -> String {
        func clean(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let directHouseNumber = clean(properties["house_number"] as? String)
        if !directHouseNumber.isEmpty {
            return directHouseNumber
        }

        let formatted = clean(properties["formatted"] as? String)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        let firstToken = streetOnly.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return clean(firstToken)
    }

    private struct LabelBuildingContext {
        let identifiers: [String]
        let centroid: CLLocationCoordinate2D
        let orderedAddressIds: [UUID]
        let addressCount: Int
        let height: Double
    }

    private static func labelBuildingContexts(
        buildings: [BuildingFeature],
        addresses: [AddressFeature],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) -> [LabelBuildingContext] {
        let addressesByIdentifier = Dictionary(grouping: addresses) { feature in
            (feature.properties.buildingGersId ?? feature.properties.gersId ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }

        return buildings.compactMap { building in
            guard let centroid = CampaignTargetResolver.coordinate(for: building.geometry) else { return nil }

            let identifiers = building.properties.buildingIdentifierCandidates
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            guard !identifiers.isEmpty else { return nil }

            var orderedAddressIds: [UUID] = []
            for identifier in identifiers {
                if let mapped = orderedAddressIdsByBuilding[identifier] {
                    orderedAddressIds.append(contentsOf: mapped)
                }
                if let featureGroup = addressesByIdentifier[identifier] {
                    orderedAddressIds.append(contentsOf: featureGroup.sorted(by: compareLabelAddresses).compactMap { feature in
                        guard let id = feature.properties.id ?? feature.id else { return nil }
                        return UUID(uuidString: id)
                    })
                }
            }

            if let directAddressId = building.properties.addressId.flatMap(UUID.init(uuidString:)) {
                orderedAddressIds.append(directAddressId)
            }

            orderedAddressIds = dedupePreservingOrder(orderedAddressIds)

            return LabelBuildingContext(
                identifiers: identifiers,
                centroid: centroid,
                orderedAddressIds: orderedAddressIds,
                addressCount: max(
                    orderedAddressIds.count,
                    building.properties.addressCount ?? 0,
                    building.properties.unitsCount,
                    1
                ),
                height: max(building.properties.heightM ?? building.properties.height, 8)
            )
        }
    }

    private static func compareLabelAddresses(_ lhs: AddressFeature, _ rhs: AddressFeature) -> Bool {
        let lhsHouse = houseNumberSortParts(
            houseNumber: lhs.properties.houseNumber,
            formatted: lhs.properties.formatted
        )
        let rhsHouse = houseNumberSortParts(
            houseNumber: rhs.properties.houseNumber,
            formatted: rhs.properties.formatted
        )

        switch (lhsHouse.number, rhsHouse.number) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if lhsHouse.suffix != rhsHouse.suffix {
            return lhsHouse.suffix.localizedStandardCompare(rhsHouse.suffix) == .orderedAscending
        }

        let lhsFormatted = (lhs.properties.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsFormatted = (rhs.properties.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return lhsFormatted.localizedStandardCompare(rhsFormatted) == .orderedAscending
    }

    private static func preferredLabelCoordinate(
        baseCoordinate: CLLocationCoordinate2D,
        building: LabelBuildingContext,
        addressIndex: Int,
        totalAddresses: Int
    ) -> CLLocationCoordinate2D {
        // Keep the house number pinned to the actual address point so the symbol sits directly
        // on the matching address extrusion instead of being spread around the linked building roof.
        _ = building
        _ = addressIndex
        _ = totalAddresses
        return baseCoordinate
    }

    private static func labelPriorityValue(
        building: LabelBuildingContext,
        totalAddresses: Int,
        addressIndex: Int
    ) -> Double {
        let linkedPriority = totalAddresses <= 1 ? 0.0 : 8.0
        let densityPenalty = Double(max(totalAddresses - 1, 0)) * 1.7
        let heightBonus = min(building.height / 24.0, 2.5)
        return linkedPriority + densityPenalty + Double(addressIndex) - heightBonus
    }

    
    /// When campaign has buildings but no address points (e.g. snapshot-only), show circle extrusions at building centroids.
    func updateAddressesFromBuildingCentroids(buildingGeoJSONData: Data?) {
        guard let data = buildingGeoJSONData else {
            print("🔍 [MapLayer] updateAddressesFromBuildingCentroids: no building data")
            return
        }
        guard mapView != nil else { return }
        do {
            let pointData = try Self.pointFeatureCollectionFromBuildingCentroids(data)
            guard let parsed = try? JSONSerialization.jsonObject(with: pointData) as? [String: Any],
                  let feats = parsed["features"] as? [[String: Any]] else {
                print("🔍 [MapLayer] updateAddressesFromBuildingCentroids: centroid extraction produced no features")
                return
            }
            if feats.isEmpty {
                print("🔍 [MapLayer] updateAddressesFromBuildingCentroids: 0 centroids (building geometry may not be Polygon/MultiPolygon)")
                return
            }
            updateAddresses(pointData)
            print("✅ [MapLayer] Updated addresses from \(feats.count) building centroids (circle extrusions fallback)")
        } catch {
            print("❌ [MapLayer] Error building centroid points: \(error)")
        }
    }
    
    /// Convert GeoJSON FeatureCollection of Point features to Polygon features (circle rings) for fill extrusion
    private static func convertAddressPointsToCirclePolygons(_ pointGeoJSONData: Data, radiusMeters: Double = 2.7, height: Double = 10, segments: Int = 20) throws -> Data {
        guard let json = try JSONSerialization.jsonObject(with: pointGeoJSONData) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            print("🔍 [MapLayer] convertAddressPointsToCirclePolygons: no features array in GeoJSON")
            return pointGeoJSONData
        }
        if features.isEmpty {
            print("🔍 [MapLayer] convertAddressPointsToCirclePolygons: input has 0 features")
        }
        let earth = 6_378_137.0
        var polygonFeatures: [[String: Any]] = []
        var skipped = 0
        
        for feature in features {
            guard let geom = feature["geometry"] as? [String: Any] else { skipped += 1; continue }
            guard geom["type"] as? String == "Point" else { skipped += 1; continue }
            guard let coordsAny = geom["coordinates"],
                  let coords = pointCoordinatesFromAny(coordsAny), coords.count >= 2 else {
                skipped += 1
                continue
            }
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
            props["height"] = height.isFinite ? height : 10
            // promoteId is "id" – ensure id is in properties and at root so setFeatureState can match (prefer address_id when present)
            var featureId: String?
            if let existing = props["id"] as? String, !existing.isEmpty {
                featureId = existing
            } else if let addressId = props["address_id"] as? String, !addressId.isEmpty {
                featureId = addressId
                props["id"] = addressId
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
        if skipped > 0 {
            print("🔍 [MapLayer] convertAddressPointsToCirclePolygons: skipped \(skipped) features (not Point or bad coords)")
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
        let signature = Self.sourceSignature(for: data)
        guard lastRoadsSourceSignature != signature else { return }
        
        do {
            let geoJSON = try JSONDecoder().decode(GeoJSONObject.self, from: data)
            mapView.mapboxMap.updateGeoJSONSource(withId: Self.roadsSourceId, geoJSON: geoJSON)
            lastRoadsSourceSignature = signature
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

        do {
            try mapView.mapboxMap.updateLayer(withId: Self.buildingsLayerId, type: FillExtrusionLayer.self) { layer in
                layer.filter = Self.buildingsStatusFilter(
                    showQrScanned: showQrScanned,
                    showConversations: showConversations,
                    showTouched: showTouched,
                    showUntouched: showUntouched
                )
            }
            try mapView.mapboxMap.updateLayer(withId: Self.townhomeOverlayLayerId, type: FillExtrusionLayer.self) { layer in
                layer.filter = Self.townhomeOverlayFilter(
                    showConversations: showConversations,
                    showTouched: showTouched,
                    showUntouched: showUntouched
                )
            }
            print("✅ [MapLayer] Updated status filter")
        } catch {
            print("❌ [MapLayer] Error updating filter: \(error)")
        }
    }

    private static func buildingsStatusFilter(
        showQrScanned: Bool,
        showConversations: Bool,
        showTouched: Bool,
        showUntouched: Bool
    ) -> Exp {
        Exp(.all) {
            Exp(.match) {
                Exp(.geometryType)
                "Polygon"
                true
                "MultiPolygon"
                true
                false
            }
            Exp(.switchCase) {
                Exp(.gt) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "scans_total" }
                        Exp(.get) { "scans_total" }
                        0
                    }
                    0
                }
                showQrScanned
                Exp(.match) {
                    Exp(.coalesce) {
                        Exp(.featureState) { "status" }
                        Exp(.get) { "status" }
                        "not_visited"
                    }
                    "hot"
                    showConversations
                    "talked"
                    showConversations
                    "appointment"
                    showConversations
                    "hot_lead"
                    showConversations
                    "visited"
                    showTouched
                    "do_not_knock"
                    showTouched
                    "delivered"
                    showTouched
                    "no_answer"
                    showTouched
                    "future_seller"
                    showTouched
                    "not_visited"
                    showUntouched
                    false
                }
            }
        }
    }

    private static func townhomeOverlayFilter(
        showConversations: Bool,
        showTouched: Bool,
        showUntouched: Bool
    ) -> Exp {
        Exp(.all) {
            Exp(.eq) {
                Exp(.geometryType)
                "Polygon"
            }
            Exp(.match) {
                Exp(.get) { "segment_status" }
                "hot"
                showConversations
                "visited"
                showTouched
                "do_not_knock"
                showTouched
                "not_visited"
                showUntouched
                false
            }
        }
    }

    private struct OverlayAddressContext {
        let id: UUID
        let buildingGersId: String
        let houseNumber: String?
        let streetName: String?
        let formatted: String?
    }

    private struct OverlayStatusRun {
        let status: String
        let count: Int
    }

    private struct ProjectedPoint {
        let x: Double
        let y: Double
    }

    private struct RotatedPoint {
        let u: Double
        let v: Double
    }

    private static func orderedAddressesForTownhome(
        gersId: String,
        fallbackAddressId: String?,
        addressesById: [UUID: OverlayAddressContext],
        orderedAddressIdsByBuilding: [String: [UUID]]
    ) -> [OverlayAddressContext] {
        let normalizedIds = dedupePreservingOrder(orderedAddressIdsByBuilding[gersId] ?? [])
        var ordered = normalizedIds.compactMap { addressesById[$0] }
        let seen = Set(ordered.map(\.id))

        let matchedAddresses = addressesById.values
            .filter { $0.buildingGersId == gersId && !seen.contains($0.id) }
            .sorted(by: compareOverlayAddresses)

        ordered.append(contentsOf: matchedAddresses)
        if !ordered.isEmpty {
            return ordered
        }

        if let fallbackAddressId,
           let uuid = UUID(uuidString: fallbackAddressId),
           let address = addressesById[uuid] {
            return [address]
        }

        return []
    }

    private static func compareOverlayAddresses(_ lhs: OverlayAddressContext, _ rhs: OverlayAddressContext) -> Bool {
        let lhsStreet = normalizedStreetName(for: lhs)
        let rhsStreet = normalizedStreetName(for: rhs)
        if lhsStreet != rhsStreet {
            return lhsStreet.localizedStandardCompare(rhsStreet) == .orderedAscending
        }

        let lhsHouse = houseNumberSortParts(
            houseNumber: lhs.houseNumber,
            formatted: lhs.formatted
        )
        let rhsHouse = houseNumberSortParts(
            houseNumber: rhs.houseNumber,
            formatted: rhs.formatted
        )

        switch (lhsHouse.number, rhsHouse.number) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            break
        }

        if lhsHouse.suffix != rhsHouse.suffix {
            return lhsHouse.suffix.localizedStandardCompare(rhsHouse.suffix) == .orderedAscending
        }

        let lhsFormatted = (lhs.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsFormatted = (rhs.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return lhsFormatted.localizedStandardCompare(rhsFormatted) == .orderedAscending
    }

    private static func normalizedStreetName(for address: OverlayAddressContext) -> String {
        let explicitStreet = (address.streetName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitStreet.isEmpty {
            return explicitStreet
        }

        let formatted = (address.formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
        return streetOnly.replacingOccurrences(
            of: #"^\s*\d+[A-Za-z\-]*\s+"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func houseNumberSortParts(houseNumber: String?, formatted: String?) -> (number: Int?, suffix: String) {
        let rawHouseNumber = (houseNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue: String
        if !rawHouseNumber.isEmpty {
            rawValue = rawHouseNumber
        } else {
            let formatted = (formatted ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let streetOnly = formatted.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? formatted
            rawValue = streetOnly.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        }

        let normalized = rawValue.uppercased()
        guard let range = normalized.range(of: #"^\d+"#, options: .regularExpression) else {
            return (nil, normalized)
        }

        let number = Int(normalized[range])
        let suffix = normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (number, suffix)
    }

    private static func dedupePreservingOrder(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for id in ids where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private static func overlaySegmentStatus(for status: AddressStatus?) -> String {
        guard let status else { return "not_visited" }
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

    private static func collapseStatusRuns(_ statuses: [String]) -> [OverlayStatusRun] {
        guard let first = statuses.first else { return [] }
        var runs: [OverlayStatusRun] = []
        var current = first
        var count = 1

        for status in statuses.dropFirst() {
            if status == current {
                count += 1
            } else {
                runs.append(OverlayStatusRun(status: current, count: count))
                current = status
                count = 1
            }
        }
        runs.append(OverlayStatusRun(status: current, count: count))
        return runs
    }

    private static func polygonRings(from geometry: MapFeatureGeoJSONGeometry) -> [[[Double]]] {
        if let polygon = geometry.asPolygon, let outerRing = cleanedOuterRing(polygon.first) {
            return [outerRing]
        }

        if let multiPolygon = geometry.asMultiPolygon {
            return multiPolygon.compactMap { cleanedOuterRing($0.first) }
        }

        return []
    }

    private static func cleanedOuterRing(_ ring: [[Double]]?) -> [[Double]]? {
        guard var ring, ring.count >= 4 else { return nil }
        if ring.first == ring.last {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return nil }
        ring.append(ring[0])
        return ring
    }

    private static func slicedPolygons(
        polygons: [[[Double]]],
        startFraction: Double,
        endFraction: Double
    ) -> [[[Double]]]? {
        guard !polygons.isEmpty, endFraction > startFraction else { return nil }

        let center = projectedCenter(for: polygons)
        let metersPerLat = 111_320.0
        let metersPerLon = max(cos(center.lat * .pi / 180.0) * metersPerLat, 0.0001)

        let projectedPolygons: [[ProjectedPoint]] = polygons.compactMap { polygon in
            let openRing = polygon.dropLast()
            guard openRing.count >= 3 else { return nil }
            return openRing.map { point in
                ProjectedPoint(
                    x: (point[0] - center.lon) * metersPerLon,
                    y: (point[1] - center.lat) * metersPerLat
                )
            }
        }
        let allPoints = projectedPolygons.flatMap { $0 }
        guard allPoints.count >= 3 else { return nil }

        let angle = principalAxisAngle(for: allPoints)
        let rotatedPolygons = projectedPolygons.map { polygon in
            polygon.map { point in
                RotatedPoint(
                    u: point.x * cos(angle) + point.y * sin(angle),
                    v: -point.x * sin(angle) + point.y * cos(angle)
                )
            }
        }

        let allU = rotatedPolygons.flatMap { $0.map(\.u) }
        guard let minU = allU.min(), let maxU = allU.max(), maxU - minU > 0.01 else { return nil }

        let sliceStart = minU + (maxU - minU) * startFraction
        let sliceEnd = minU + (maxU - minU) * endFraction

        let clippedPolygons: [[[Double]]] = rotatedPolygons.compactMap { polygon in
            let clipped = clipPolygon(polygon, minU: sliceStart, maxU: sliceEnd)
            guard clipped.count >= 3 else { return nil }

            var ring: [[Double]] = clipped.map { point in
                let x = point.u * cos(angle) - point.v * sin(angle)
                let y = point.u * sin(angle) + point.v * cos(angle)
                let lon = center.lon + (x / metersPerLon)
                let lat = center.lat + (y / metersPerLat)
                return [lon, lat]
            }
            guard ring.count >= 3 else { return nil }
            ring.append(ring[0])
            return ring
        }

        return clippedPolygons.isEmpty ? nil : clippedPolygons
    }

    private static func projectedCenter(for polygons: [[[Double]]]) -> (lon: Double, lat: Double) {
        let points = polygons.flatMap { $0 }
        let lon = points.map { $0[0] }.reduce(0, +) / Double(max(points.count, 1))
        let lat = points.map { $0[1] }.reduce(0, +) / Double(max(points.count, 1))
        return (lon, lat)
    }

    private static func principalAxisAngle(for points: [ProjectedPoint]) -> Double {
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)

        var sxx = 0.0
        var syy = 0.0
        var sxy = 0.0
        for point in points {
            let dx = point.x - meanX
            let dy = point.y - meanY
            sxx += dx * dx
            syy += dy * dy
            sxy += dx * dy
        }

        return 0.5 * atan2(2 * sxy, sxx - syy)
    }

    private static func clipPolygon(_ polygon: [RotatedPoint], minU: Double, maxU: Double) -> [RotatedPoint] {
        let afterMin = clipAgainstBoundary(
            polygon,
            isInside: { $0.u >= minU },
            intersection: { previous, current in
                intersect(previous: previous, current: current, boundaryU: minU)
            }
        )
        return clipAgainstBoundary(
            afterMin,
            isInside: { $0.u <= maxU },
            intersection: { previous, current in
                intersect(previous: previous, current: current, boundaryU: maxU)
            }
        )
    }

    private static func clipAgainstBoundary(
        _ polygon: [RotatedPoint],
        isInside: (RotatedPoint) -> Bool,
        intersection: (RotatedPoint, RotatedPoint) -> RotatedPoint
    ) -> [RotatedPoint] {
        guard !polygon.isEmpty else { return [] }

        var output: [RotatedPoint] = []
        var previous = polygon[polygon.count - 1]

        for current in polygon {
            let previousInside = isInside(previous)
            let currentInside = isInside(current)

            if currentInside {
                if !previousInside {
                    output.append(intersection(previous, current))
                }
                output.append(current)
            } else if previousInside {
                output.append(intersection(previous, current))
            }

            previous = current
        }

        return removeAdjacentDuplicatePoints(output)
    }

    private static func intersect(previous: RotatedPoint, current: RotatedPoint, boundaryU: Double) -> RotatedPoint {
        let deltaU = current.u - previous.u
        guard abs(deltaU) > 0.000001 else {
            return RotatedPoint(u: boundaryU, v: current.v)
        }

        let t = (boundaryU - previous.u) / deltaU
        return RotatedPoint(
            u: boundaryU,
            v: previous.v + (current.v - previous.v) * t
        )
    }

    private static func removeAdjacentDuplicatePoints(_ points: [RotatedPoint]) -> [RotatedPoint] {
        var cleaned: [RotatedPoint] = []
        for point in points {
            if let last = cleaned.last,
               abs(last.u - point.u) < 0.000001,
               abs(last.v - point.v) < 0.000001 {
                continue
            }
            cleaned.append(point)
        }
        return cleaned
    }
    
    // MARK: - Address Tap Result
    
    /// Result of tapping the addresses layer (3D circles). Decodes from feature properties.
    struct AddressTapResult: Decodable {
        let addressId: UUID
        let formatted: String
        let gersId: String?
        let buildingGersId: String?
        let houseNumber: String?
        let streetName: String?
        let source: String?
        
        init(addressId: UUID, formatted: String, gersId: String?, buildingGersId: String?, houseNumber: String?, streetName: String?, source: String?) {
            self.addressId = addressId
            self.formatted = formatted
            self.gersId = gersId
            self.buildingGersId = buildingGersId
            self.houseNumber = houseNumber
            self.streetName = streetName
            self.source = source
        }
        
        enum CodingKeys: String, CodingKey {
            case addressId = "id"
            case addressIdAlt = "address_id"
            case formatted
            case gersId = "gers_id"
            case buildingGersId = "building_gers_id"
            case houseNumber = "house_number"
            case streetName = "street_name"
            case source
        }
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let idFromId = try c.decodeIfPresent(String.self, forKey: .addressId)
            let idFromAddressId = try c.decodeIfPresent(String.self, forKey: .addressIdAlt)
            let idString = idFromId ?? idFromAddressId ?? ""
            guard let uuid = UUID(uuidString: idString) else {
                throw DecodingError.dataCorruptedError(forKey: .addressId, in: c, debugDescription: "Invalid UUID string: \(idString)")
            }
            addressId = uuid
            formatted = try c.decodeIfPresent(String.self, forKey: .formatted) ?? ""
            gersId = try c.decodeIfPresent(String.self, forKey: .gersId)
            buildingGersId = try c.decodeIfPresent(String.self, forKey: .buildingGersId)
            houseNumber = try c.decodeIfPresent(String.self, forKey: .houseNumber)
            streetName = try c.decodeIfPresent(String.self, forKey: .streetName)
            source = try c.decodeIfPresent(String.self, forKey: .source)
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
        @unknown default: return NSNull()
        }
    }
    
    /// Result of tapping either the buildings or addresses layer
    enum BuildingOrAddressTapResult {
        case building(BuildingProperties)
        case address(AddressTapResult)
    }

    /// Get building or address at tap location by querying both layers (so circles always show the card).
    func getBuildingOrAddressAt(point: CGPoint, completion: @escaping (BuildingOrAddressTapResult?) -> Void) {
        guard let mapView = mapView else { completion(nil); return }

        let options = RenderedQueryOptions(layerIds: [Self.buildingsLayerId, Self.addressesLayerId], filter: nil)
        mapView.mapboxMap.queryRenderedFeatures(with: point, options: options) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let features):
                guard let first = features.first, let properties = first.queriedFeature.feature.properties else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let converted = self.unwrapTurfProperties(properties)
                let sanitized = SafeJSON.sanitize(converted)
                guard JSONSerialization.isValidJSONObject(sanitized), let data = SafeJSON.data(from: sanitized) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                // Address (cylinder) features decode as lenient `BuildingProperties` too (defaults fill gaps),
                // which drops the address UUID when it lives in `id` but not `address_id`. Prefer address taps first.
                if let addressResult = try? JSONDecoder().decode(AddressTapResult.self, from: data) {
                    DispatchQueue.main.async { completion(.address(addressResult)) }
                    return
                }
                if let building = try? JSONDecoder().decode(BuildingProperties.self, from: data) {
                    DispatchQueue.main.async { completion(.building(building)) }
                    return
                }
                DispatchQueue.main.async { completion(nil) }
            case .failure(let error):
                print("❌ [MapLayer] Error querying features: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
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
        try? mapView.mapboxMap.removeLayer(withId: Self.townhomeOverlayLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.addressesLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.manualAddressPreviewLayerId)
        try? mapView.mapboxMap.removeLayer(withId: Self.roadsLayerId)
        
        // Remove sources
        try? mapView.mapboxMap.removeSource(withId: Self.buildingsSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.townhomeOverlaySourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.addressesSourceId)
        try? mapView.mapboxMap.removeSource(withId: Self.manualAddressPreviewSourceId)
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
