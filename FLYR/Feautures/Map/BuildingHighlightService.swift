import MapboxMaps
import CoreLocation
import UIKit
import CoreGraphics

// MARK: - Building Highlight Service

/// Stateless service for rendering building polygons on Mapbox maps
/// Handles polygon queries, distance calculations, and fallback circle generation
final class BuildingHighlightService {
    private weak var mapView: MapView?
    private let sourceId = "campaign-buildings-source"
    private let fillLayerId = "campaign-buildings-fill"
    private let lineLayerId = "campaign-buildings-line"
    
    init(mapView: MapView) {
        self.mapView = mapView
    }
    
    /// Initialize GeoJSON sources and layers for building highlights
    func ensureLayers() {
        guard let mapView else { return }
        
        // Create empty GeoJSON source
        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(.init(features: []))
        try? mapView.mapboxMap.addSource(source)
        
        // Create fill layer for building interiors
        var fillLayer = FillLayer(id: fillLayerId, source: sourceId)
        fillLayer.fillColor = .constant(StyleColor(.clear))
        fillLayer.fillOpacity = .constant(0.1)
        fillLayer.fillOutlineColor = .constant(StyleColor(.clear))
        try? mapView.mapboxMap.addLayer(fillLayer)
        
        // Create line layer for building outlines
        var lineLayer = LineLayer(id: lineLayerId, source: sourceId)
        lineLayer.lineColor = .constant(StyleColor(.black))
        lineLayer.lineWidth = .constant(1.5)
        lineLayer.lineOpacity = .constant(0.85)
        try? mapView.mapboxMap.addLayer(lineLayer, layerPosition: .above(fillLayerId))
    }
    
    /// Highlight buildings for given coordinates
    /// - Parameters:
    ///   - coords: Array of coordinates to highlight
    ///   - searchMeters: Search radius for building polygons (default: 30)
    func highlightBuildings(coords: [CLLocationCoordinate2D], searchMeters: Double = 30) async {
        guard let mapView else { return }
        
        var features: [Feature] = []
        
        for coord in coords {
            // Try to find building polygon
            if let polygon = await queryBuildingPolygon(at: coord, within: searchMeters) {
                features.append(Feature(geometry: .polygon(polygon)))
            } else {
                // Fallback to circle if no building found
                if let circle = makeCircle(center: coord, meters: 10, segments: 24) {
                    features.append(Feature(geometry: .polygon(circle)))
                }
            }
        }
        
        // Update source with new features
        try? mapView.mapboxMap.updateGeoJSONSource(withId: sourceId, geoJSON: .featureCollection(.init(features: features)))
    }
    
    /// Query Mapbox building layer for polygon at coordinate
    /// - Parameters:
    ///   - coord: Coordinate to query
    ///   - within: Maximum distance in meters
    /// - Returns: Building polygon if found within distance
    private func queryBuildingPolygon(at coord: CLLocationCoordinate2D, within meters: Double) async -> Polygon? {
        guard let mapView else { return nil }
        
        do {
            let point = mapView.mapboxMap.point(for: coord)
            let box = CGRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48)
            let result = try await withCheckedThrowingContinuation { continuation in
                mapView.mapboxMap.queryRenderedFeatures(
                    with: box,
                    options: .init(layerIds: ["building"], filter: nil)
                ) { result in
                    continuation.resume(with: result)
                }
            }
            
            var best: (Polygon, Double)? = nil
            
            for feature in result {
                guard case let .polygon(polygon) = feature.queriedFeature.feature.geometry ?? .point(Point(LocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude))) else {
                    continue
                }
                
                let distance = distanceToPolygonCenter(polygon, from: coord)
                if best == nil || distance < best!.1 {
                    best = (polygon, distance)
                }
            }
            
            if let (polygon, distance) = best, distance <= meters {
                return polygon
            }
            
            return best?.0
        } catch {
            return nil
        }
    }
    
    /// Calculate distance from coordinate to polygon center
    /// - Parameters:
    ///   - polygon: The polygon to measure
    ///   - coord: Reference coordinate
    /// - Returns: Distance in meters
    private func distanceToPolygonCenter(_ polygon: Polygon, from coord: CLLocationCoordinate2D) -> Double {
        let ring = polygon.coordinates.first ?? []
        let avg = ring.reduce((0.0, 0.0)) { ($0.0 + $1.latitude, $0.1 + $1.longitude) }
        let center = CLLocationCoordinate2D(
            latitude: avg.0 / Double(max(ring.count, 1)),
            longitude: avg.1 / Double(max(ring.count, 1))
        )
        
        return CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude))
    }
    
    /// Generate circular polygon as fallback
    /// - Parameters:
    ///   - center: Center coordinate
    ///   - meters: Radius in meters
    ///   - segments: Number of segments for smooth circle
    /// - Returns: Circular polygon
    private func makeCircle(center: CLLocationCoordinate2D, meters: Double, segments: Int) -> Polygon? {
        guard segments >= 8 else { return nil }
        
        let earth = 6_378_137.0 // Earth radius in meters
        let lat = center.latitude * .pi / 180
        
        var coords: [CLLocationCoordinate2D] = []
        
        for i in 0...segments {
            let theta = 2 * .pi * Double(i) / Double(segments)
            let dx = meters * cos(theta)
            let dy = meters * sin(theta)
            let dLat = (dy / earth) * 180 / .pi
            let dLon = (dx / (earth * cos(lat))) * 180 / .pi
            
            coords.append(.init(
                latitude: center.latitude + dLat,
                longitude: center.longitude + dLon
            ))
        }
        
        return Polygon([coords])
    }
}
