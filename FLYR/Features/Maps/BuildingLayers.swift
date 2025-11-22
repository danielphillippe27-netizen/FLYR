import Foundation
import MapboxMaps
import UIKit

// MARK: - Building Layers Factory

/// Factory for creating and managing Mapbox map layers for building polygons
enum BuildingLayers {
    
    /// Add or update building polygon layers on the map
    /// - Parameters:
    ///   - map: Mapbox map instance
    ///   - sourceId: Unique source identifier
    ///   - featureCollection: GeoJSON FeatureCollection with building polygons
    static func addOrUpdate(
        map: MapboxMap,
        sourceId: String,
        featureCollection: GeoJSONFeatureCollection
    ) throws {
        print("🗺️ [LAYERS] Adding building layers with source: \(sourceId)")
        
        let fillLayerId = "\(sourceId)-fill"
        let outlineLayerId = "\(sourceId)-outline"
        
        // Convert GeoJSONFeatureCollection to Mapbox format
        let mapboxFeatureCollection = convertToMapboxFeatureCollection(featureCollection)
        
        // Create or update GeoJSON source
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(mapboxFeatureCollection)
        
        // Remove existing source if it exists
        if map.allSourceIdentifiers.contains(where: { $0.id == sourceId }) {
            try map.removeSource(withId: sourceId)
        }
        
        try map.addSource(source)
        
        // Remove existing layers if they exist
        if map.allLayerIdentifiers.contains(where: { $0.id == fillLayerId }) {
            try map.removeLayer(withId: fillLayerId)
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == outlineLayerId }) {
            try map.removeLayer(withId: outlineLayerId)
        }
        
        // Create fill layer (below outline) - polygons only
        var fillLayer = FillLayer(id: fillLayerId, source: sourceId)
        fillLayer.fillColor = .constant(StyleColor(UIColor.red))
        fillLayer.fillOpacity = .constant(0.25) // 25% opacity for map visibility
        fillLayer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        try map.addLayer(fillLayer, layerPosition: .below(outlineLayerId))
        
        // Create outline layer - polygons only (thin red border)
        var outlineLayer = LineLayer(id: outlineLayerId, source: sourceId)
        outlineLayer.lineColor = .constant(StyleColor(UIColor.red))
        outlineLayer.lineWidth = .constant(1.5) // Thin border
        outlineLayer.lineOpacity = .constant(1.0) // Full opacity
        outlineLayer.filter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        try map.addLayer(outlineLayer)
        
        print("✅ [LAYERS] Added building layers: \(fillLayerId), \(outlineLayerId)")
    }
    
    /// Set selected building highlight
    /// - Parameters:
    ///   - map: Mapbox map instance
    ///   - selectedAddressId: Selected address ID (nil to clear selection)
    ///   - sourceId: Source identifier
    static func setSelected(
        map: MapboxMap,
        selectedAddressId: UUID?,
        sourceId: String
    ) throws {
        let outlineLayerId = "\(sourceId)-outline"
        
        guard map.allLayerIdentifiers.contains(where: { $0.id == outlineLayerId }) else {
            print("⚠️ [LAYERS] Outline layer not found: \(outlineLayerId)")
            return
        }
        
        // Build filter: polygon types + optional selection
        let polygonFilter = Exp(.match) {
            Exp(.geometryType)
            "Polygon"
            true
            "MultiPolygon"
            true
            false
        }
        
        if let selectedId = selectedAddressId {
            let selectionFilter = Exp(.eq) {
                "campaign_address_id"
                selectedId.uuidString
            }
            
            let combinedFilter = Exp(.all) {
                polygonFilter
                selectionFilter
            }
            
            try map.updateLayer(withId: outlineLayerId, type: LineLayer.self) { layer in
                layer.filter = combinedFilter
                layer.lineWidth = .constant(4.0)
            }
        } else {
            try map.updateLayer(withId: outlineLayerId, type: LineLayer.self) { layer in
                layer.filter = polygonFilter
                layer.lineWidth = .constant(2.0)
            }
        }
        
        if let selectedId = selectedAddressId {
            print("✅ [LAYERS] Highlighted building for address: \(selectedId)")
        } else {
            print("✅ [LAYERS] Cleared building selection")
        }
    }
    
    /// Remove building layers from map
    /// - Parameters:
    ///   - map: Mapbox map instance
    ///   - sourceId: Source identifier
    static func remove(map: MapboxMap, sourceId: String) throws {
        let fillLayerId = "\(sourceId)-fill"
        let outlineLayerId = "\(sourceId)-outline"
        
        // Remove layers
        if map.allLayerIdentifiers.contains(where: { $0.id == fillLayerId }) {
            try map.removeLayer(withId: fillLayerId)
        }
        if map.allLayerIdentifiers.contains(where: { $0.id == outlineLayerId }) {
            try map.removeLayer(withId: outlineLayerId)
        }
        
        // Remove source
        if map.allSourceIdentifiers.contains(where: { $0.id == sourceId }) {
            try map.removeSource(withId: sourceId)
        }
        
        print("✅ [LAYERS] Removed building layers: \(sourceId)")
    }
    
    // MARK: - Private Helpers
    
    /// Convert GeoJSONFeatureCollection to Mapbox FeatureCollection
    private static func convertToMapboxFeatureCollection(_ collection: GeoJSONFeatureCollection) -> FeatureCollection {
        let features = collection.features.map { feature in
            convertToMapboxFeature(feature)
        }
        return FeatureCollection(features: features)
    }
    
    /// Convert GeoJSONFeature to Mapbox Feature
    private static func convertToMapboxFeature(_ feature: GeoJSONFeature) -> Feature {
        let geometry = convertToMapboxGeometry(feature.geometry)
        let properties = convertToMapboxProperties(feature.properties)
        
        return Feature(geometry: geometry)
    }
    
    /// Convert GeoJSONGeometry to Mapbox Geometry
    private static func convertToMapboxGeometry(_ geometry: GeoJSONGeometry) -> Geometry {
        switch geometry.type {
        case "Polygon":
            if let coords = geometry.coordinates.value as? [[[Double]]] {
                let polygonCoords = coords.map { ring in
                    ring.map { coord in
                        CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                    }
                }
                return .polygon(Polygon(polygonCoords))
            }
        case "MultiPolygon":
            if let coords = geometry.coordinates.value as? [[[[Double]]]] {
                let multiPolygonCoords = coords.map { polygon in
                    polygon.map { ring in
                        ring.map { coord in
                            CLLocationCoordinate2D(latitude: coord[1], longitude: coord[0])
                        }
                    }
                }
                return .multiPolygon(MultiPolygon(multiPolygonCoords))
            }
        default:
            break
        }
        
        // Fallback to empty polygon
        let emptyCoords = [[CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
                           CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
                           CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
                           CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)]]
        return .polygon(Polygon(emptyCoords))
    }
    
    /// Convert properties to Mapbox format
    private static func convertToMapboxProperties(_ properties: [String: AnyCodable]) -> [String: Any] {
        var mapboxProperties: [String: Any] = [:]
        
        for (key, value) in properties {
            mapboxProperties[key] = value.value
        }
        
        return mapboxProperties
    }
}
