import Foundation
import MapboxMaps
import CoreLocation

// MARK: - Building Geometry Helpers

/// Geometry utilities for building polygon selection and analysis
enum BuildingGeometryHelpers {
    
    /// Check if a point is contained within a polygon using ray casting algorithm
    /// - Parameters:
    ///   - point: Point to test
    ///   - polygon: Polygon to test against
    /// - Returns: True if point is inside polygon
    static func pointInPolygon(_ point: CLLocationCoordinate2D, polygon: Polygon) -> Bool {
        guard let ring = polygon.coordinates.first, ring.count >= 3 else {
            return false
        }
        
        var inside = false
        let pointLat = point.latitude
        let pointLon = point.longitude
        
        var j = ring.count - 1
        for i in 0..<ring.count {
            let vi = ring[i]
            let vj = ring[j]
            
            let viLat = vi.latitude
            let viLon = vi.longitude
            let vjLat = vj.latitude
            let vjLon = vj.longitude
            
            if ((viLat > pointLat) != (vjLat > pointLat)) &&
               (pointLon < (vjLon - viLon) * (pointLat - viLat) / (vjLat - viLat) + viLon) {
                inside = !inside
            }
            j = i
        }
        
        return inside
    }
    
    /// Calculate the centroid of a polygon
    /// - Parameter polygon: Polygon to calculate centroid for
    /// - Returns: Centroid coordinate, or nil if polygon is invalid
    static func polygonCentroid(_ polygon: Polygon) -> CLLocationCoordinate2D? {
        guard let ring = polygon.coordinates.first, ring.count >= 3 else {
            return nil
        }
        
        var sumLat = 0.0
        var sumLon = 0.0
        var count = 0
        
        // Use all points except the last (which duplicates the first)
        for i in 0..<(ring.count - 1) {
            let coord = ring[i]
            sumLat += coord.latitude
            sumLon += coord.longitude
            count += 1
        }
        
        guard count > 0 else { return nil }
        
        return CLLocationCoordinate2D(
            latitude: sumLat / Double(count),
            longitude: sumLon / Double(count)
        )
    }
    
    /// Calculate distance in meters between a point and a polygon's centroid
    /// - Parameters:
    ///   - point: Point to measure from
    ///   - polygon: Polygon to measure to
    /// - Returns: Distance in meters, or nil if centroid cannot be calculated
    static func distanceToPolygonCentroid(_ point: CLLocationCoordinate2D, polygon: Polygon) -> Double? {
        guard let centroid = polygonCentroid(polygon) else {
            return nil
        }
        
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
        let centroidLocation = CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)
        
        return pointLocation.distance(from: centroidLocation)
    }
    
    /// Check if two polygons have approximately the same geometry (for deduplication)
    /// Uses centroid and area comparison with tolerance
    /// - Parameters:
    ///   - poly1: First polygon
    ///   - poly2: Second polygon
    ///   - tolerance: Distance tolerance in meters (default: 1.0)
    /// - Returns: True if polygons are considered the same
    static func polygonsAreEqual(_ poly1: Polygon, _ poly2: Polygon, tolerance: Double = 1.0) -> Bool {
        guard let centroid1 = polygonCentroid(poly1),
              let centroid2 = polygonCentroid(poly2) else {
            return false
        }
        
        let centroid1Loc = CLLocation(latitude: centroid1.latitude, longitude: centroid1.longitude)
        let centroid2Loc = CLLocation(latitude: centroid2.latitude, longitude: centroid2.longitude)
        let distance = centroid1Loc.distance(from: centroid2Loc)
        
        // If centroids are very close and areas are similar, consider them equal
        if distance < tolerance {
            let area1 = poly1.areaApprox()
            let area2 = poly2.areaApprox()
            let areaDiff = abs(area1 - area2) / max(area1, area2)
            return areaDiff < 0.01 // 1% area difference tolerance
        }
        
    return false
  }
}

