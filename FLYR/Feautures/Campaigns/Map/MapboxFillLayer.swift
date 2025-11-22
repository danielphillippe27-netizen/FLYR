import Foundation
import MapboxMaps
import CoreLocation
import UIKit

// MARK: - Mapbox Fill Layer Helper

enum MapboxFillLayer {
    
    /// Add building polygon outlines to a Mapbox map
    static func addPolygons(_ mapView: MapView, id: String, addresses: [CampaignAddress]) throws {
        // Filter addresses that have building outlines
        let addressesWithOutlines = addresses.compactMap { address -> (CampaignAddress, [[CLLocationCoordinate2D]])? in
            guard let outline = address.buildingOutline else { return nil }
            return (address, outline)
        }
        
        guard !addressesWithOutlines.isEmpty else { return }
        
        // Create GeoJSON features from polygon coordinates
        var features: [Feature] = []
        
        for (_, outline) in addressesWithOutlines {
            // Convert polygon rings to GeoJSON format
            let geoJSONRings = outline.map { ring in
                ring.map { coord in
                    LocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
                }
            }
            
            // Create polygon geometry
            let polygon = Polygon(geoJSONRings)
            let geometry = Geometry.polygon(polygon)
            
            // Create feature with properties
            let properties: [String: Any] = [
                "address": addressesWithOutlines.first?.0.address ?? "",
                "type": "building"
            ]
            
            let feature = Feature(geometry: geometry)
            features.append(feature)
        }
        
        // Create GeoJSON source
        let featureCollection = FeatureCollection(features: features)
        var source = GeoJSONSource(id: "\(id)-source")
        source.data = .featureCollection(featureCollection)
        
        // Add source to map
        try mapView.mapboxMap.style.addSource(source)
        
        // Create fill layer
        var fillLayer = FillLayer(id: "\(id)-fill", source: "\(id)-source")
        fillLayer.fillColor = .constant(StyleColor(UIColor.black.withAlphaComponent(0.1)))
        fillLayer.fillOpacity = .constant(0.3)
        
        // Add fill layer to map
        try mapView.mapboxMap.addLayer(fillLayer)
        
        // Create stroke layer for outlines
        var strokeLayer = LineLayer(id: "\(id)-stroke", source: "\(id)-source")
        strokeLayer.lineColor = .constant(StyleColor(.black))
        strokeLayer.lineWidth = .constant(1.0)
        strokeLayer.lineOpacity = .constant(0.8)
        
        // Add stroke layer to map
        try mapView.mapboxMap.addLayer(strokeLayer)
    }
    
    /// Remove building polygon layers from map
    static func removePolygons(_ mapView: MapView, id: String) {
        // Remove layers
        try? mapView.mapboxMap.removeLayer(withId: "\(id)-fill")
        try? mapView.mapboxMap.removeLayer(withId: "\(id)-stroke")
        
        // Remove source
        try? mapView.mapboxMap.removeSource(withId: "\(id)-source")
    }
}
