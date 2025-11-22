import Foundation
import CoreLocation
import MapboxMaps

/// Helper functions for computing campaign polygons from addresses
enum CampaignPolygonHelper {
    /// Compute a bounding box polygon from campaign addresses
    /// Returns a simple rectangular polygon that encompasses all addresses
    static func boundingBoxPolygon(from addresses: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard !addresses.isEmpty else {
            return []
        }
        
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        
        for address in addresses {
            minLat = min(minLat, address.latitude)
            maxLat = max(maxLat, address.latitude)
            minLon = min(minLon, address.longitude)
            maxLon = max(maxLon, address.longitude)
        }
        
        // Add padding (10% on each side)
        let latPadding = (maxLat - minLat) * 0.1
        let lonPadding = (maxLon - minLon) * 0.1
        
        minLat -= latPadding
        maxLat += latPadding
        minLon -= lonPadding
        maxLon += lonPadding
        
        // Create rectangular polygon (clockwise)
        return [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon), // SW
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon), // SE
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon), // NE
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon), // NW
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon)  // Close polygon
        ]
    }
    
    /// Compute convex hull polygon from campaign addresses using Graham scan algorithm
    /// Returns a polygon that wraps around all addresses
    static func convexHullPolygon(from addresses: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard addresses.count >= 3 else {
            // If less than 3 points, return bounding box
            return boundingBoxPolygon(from: addresses)
        }
        
        // Find the point with the lowest y-coordinate (and leftmost if tie)
        let sorted = addresses.sorted { a, b in
            if a.latitude != b.latitude {
                return a.latitude < b.latitude
            }
            return a.longitude < b.longitude
        }
        
        let p0 = sorted[0]
        let remaining = Array(sorted[1...])
        
        // Sort by polar angle with respect to p0
        let sortedByAngle = remaining.sorted { a, b in
            let angleA = atan2(a.latitude - p0.latitude, a.longitude - p0.longitude)
            let angleB = atan2(b.latitude - p0.latitude, b.longitude - p0.longitude)
            return angleA < angleB
        }
        
        // Build convex hull using Graham scan
        var hull = [p0]
        
        for point in sortedByAngle {
            while hull.count > 1 {
                let p1 = hull[hull.count - 2]
                let p2 = hull[hull.count - 1]
                
                // Check if point is to the left of the line from p1 to p2
                let cross = (p2.longitude - p1.longitude) * (point.latitude - p1.latitude) -
                           (p2.latitude - p1.latitude) * (point.longitude - p1.longitude)
                
                if cross <= 0 {
                    hull.removeLast()
                } else {
                    break
                }
            }
            hull.append(point)
        }
        
        // Close the polygon
        if !hull.isEmpty && hull.first != hull.last {
            hull.append(hull.first!)
        }
        
        return hull
    }
    
    /// Compute polygon from campaign addresses using the specified method
    /// - Parameters:
    ///   - addresses: Array of campaign address coordinates
    ///   - method: Method to use (boundingBox or convexHull)
    /// - Returns: Polygon coordinates
    static func polygon(
        from addresses: [CLLocationCoordinate2D],
        method: PolygonMethod = .convexHull
    ) -> [CLLocationCoordinate2D] {
        switch method {
        case .boundingBox:
            return boundingBoxPolygon(from: addresses)
        case .convexHull:
            return convexHullPolygon(from: addresses)
        }
    }
    
    enum PolygonMethod {
        case boundingBox
        case convexHull
    }
}



