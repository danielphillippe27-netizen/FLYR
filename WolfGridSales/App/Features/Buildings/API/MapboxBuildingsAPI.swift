import Foundation
import CoreLocation

// MARK: - Buildings API for Mapbox Tilequery

/// API for fetching building polygons from Mapbox Tilequery
final class MapboxBuildingsAPI {
    static let shared = MapboxBuildingsAPI()
    private init() {}
    
    /// Fetch the best building polygon for a coordinate using Mapbox Tilequery
    /// - Parameters:
    ///   - coord: Center coordinate to search around
    ///   - radiusMeters: Search radius in meters (default: 50)
    ///   - token: Mapbox access token
    /// - Returns: Tuple of (buildingId, geometry) or nil if no building found
    func fetchBestBuildingPolygon(
        coord: CLLocationCoordinate2D,
        radiusMeters: Int = 50,
        token: String
    ) async throws -> (buildingId: String, geometry: [String: Any])? {
        print("🏗️ [MBX] tilequery @ \(coord.latitude),\(coord.longitude)")
        
        // Build Mapbox Tilequery URL
        let baseURL = "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery"
        let urlString = "\(baseURL)/\(coord.longitude),\(coord.latitude).json?radius=\(radiusMeters)&layers=building&limit=6&access_token=\(token)"
        
        print("🏗️ [MBX] Tilequery URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ [MBX] Invalid URL")
            throw MapboxBuildingsAPIError.invalidURL
        }
        
        // Make request
        let (data, response) = try await URLSession.shared.data(from: url)
        
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("🏗️ [MBX] status \(statusCode) bytes \(data.count)")
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [MBX] Invalid response")
            throw MapboxBuildingsAPIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [MBX] HTTP error: \(httpResponse.statusCode)")
            if httpResponse.statusCode == 401 {
                print("❌ [MBX] 401 Unauthorized - check your Mapbox token")
            }
            throw MapboxBuildingsAPIError.httpError(httpResponse.statusCode)
        }
        
        // Parse GeoJSON response
        let tilequeryResponse = try JSONDecoder().decode(TilequeryResponse.self, from: data)
        
        print("🏗️ [MBX] status \(statusCode) candidates \(tilequeryResponse.features.count)")
        
        guard !tilequeryResponse.features.isEmpty else {
            print("🏗️ [MBX] No buildings found for \(coord)")
            return nil
        }
        
        // Find best building polygon
        let bestFeature = selectBestBuildingFeature(
            features: tilequeryResponse.features,
            targetCoord: coord
        )
        
        guard let buildingId = bestFeature.properties["id"]?.value as? String else {
            print("🏗️ [MBX] No building ID found in feature")
            return nil
        }
        
        // Convert geometry to dictionary format
        let geometry = convertGeometryToDictionary(bestFeature.geometry)
        
        print("✅ [MBX] Found building \(buildingId) for \(coord)")
        return (buildingId: buildingId, geometry: geometry)
    }
    
    // MARK: - Private Helpers
    
    /// Select the best building feature from multiple candidates
    private func selectBestBuildingFeature(
        features: [TilequeryFeature],
        targetCoord: CLLocationCoordinate2D
    ) -> TilequeryFeature {
        // Priority: contains point > nearest to point > largest area
        let targetPoint = CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude)
        
        // First, try to find buildings that contain the target point
        let containingBuildings = features.filter { feature in
            containsPoint(feature: feature, point: targetCoord)
        }
        
        if !containingBuildings.isEmpty {
            // Return the largest containing building
            return containingBuildings.max { $0.area < $1.area } ?? containingBuildings[0]
        }
        
        // If no containing buildings, find the nearest
        let nearestBuilding = features.min { feature1, feature2 in
            let distance1 = distanceToPoint(feature: feature1, point: targetPoint)
            let distance2 = distanceToPoint(feature: feature2, point: targetPoint)
            return distance1 < distance2
        }
        
        return nearestBuilding ?? features[0]
    }
    
    /// Check if a building polygon contains the target point
    private func containsPoint(feature: TilequeryFeature, point: CLLocationCoordinate2D) -> Bool {
        // This is a simplified check - in a real implementation you'd use proper geometry libraries
        // For now, we'll use a bounding box approximation
        guard let coordinates = feature.geometry.coordinates.value as? [[[Double]]] else {
            return false
        }
        
        // Get bounding box of polygon
        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        
        for ring in coordinates {
            for coord in ring {
                if coord.count >= 2 {
                    let lon = coord[0]
                    let lat = coord[1]
                    minLat = min(minLat, lat)
                    maxLat = max(maxLat, lat)
                    minLon = min(minLon, lon)
                    maxLon = max(maxLon, lon)
                }
            }
        }
        
        return point.latitude >= minLat && point.latitude <= maxLat &&
               point.longitude >= minLon && point.longitude <= maxLon
    }
    
    /// Calculate distance from building to target point
    private func distanceToPoint(feature: TilequeryFeature, point: CLLocation) -> Double {
        // Calculate centroid of polygon and return distance
        guard let coordinates = feature.geometry.coordinates.value as? [[[Double]]] else {
            return Double.infinity
        }
        
        var totalLat = 0.0
        var totalLon = 0.0
        var count = 0
        
        for ring in coordinates {
            for coord in ring {
                if coord.count >= 2 {
                    totalLon += coord[0]
                    totalLat += coord[1]
                    count += 1
                }
            }
        }
        
        guard count > 0 else { return Double.infinity }
        
        let centroid = CLLocation(
            latitude: totalLat / Double(count),
            longitude: totalLon / Double(count)
        )
        
        return point.distance(from: centroid)
    }
    
    /// Convert GeoJSON geometry to dictionary format for storage
    private func convertGeometryToDictionary(_ geometry: TilequeryGeometry) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["type"] = geometry.type
        dict["coordinates"] = geometry.coordinates.value
        
        // Flatten MultiPolygon to largest Polygon if needed
        if geometry.type == "MultiPolygon" {
            if let multiCoords = geometry.coordinates.value as? [[[[Double]]]] {
                // Find the largest polygon by area
                let largestPolygon = findLargestPolygon(multiCoords: multiCoords)
                dict["type"] = "Polygon"
                dict["coordinates"] = largestPolygon
            }
        }
        
        return dict
    }
    
    /// Find the largest polygon from a MultiPolygon
    private func findLargestPolygon(multiCoords: [[[[Double]]]]) -> [[[Double]]] {
        var largestArea = 0.0
        var largestPolygon: [[[Double]]] = multiCoords[0]
        
        for polygon in multiCoords {
            let area = calculatePolygonArea(coordinates: polygon)
            if area > largestArea {
                largestArea = area
                largestPolygon = polygon
            }
        }
        
        return largestPolygon
    }
    
    /// Calculate approximate area of a polygon (simplified)
    private func calculatePolygonArea(coordinates: [[[Double]]]) -> Double {
        guard let ring = coordinates.first, ring.count >= 3 else { return 0.0 }
        
        var area = 0.0
        let n = ring.count - 1 // Exclude last point (duplicate of first)
        
        for i in 0..<n {
            let j = (i + 1) % n
            if ring[i].count >= 2 && ring[j].count >= 2 {
                area += ring[i][0] * ring[j][1]
                area -= ring[j][0] * ring[i][1]
            }
        }
        
        return abs(area) / 2.0
    }
}

// MARK: - Response Models

private struct TilequeryResponse: Codable {
    let type: String
    let features: [TilequeryFeature]
}

private struct TilequeryFeature: Codable {
    let type: String
    let geometry: TilequeryGeometry
    let properties: [String: AnyCodable]
    
    var area: Double {
        // Calculate area from geometry
        guard let coordinates = geometry.coordinates.value as? [[[Double]]] else { return 0.0 }
        return calculatePolygonArea(coordinates: coordinates)
    }
    
    private func calculatePolygonArea(coordinates: [[[Double]]]) -> Double {
        guard let ring = coordinates.first, ring.count >= 3 else { return 0.0 }
        
        var area = 0.0
        let n = ring.count - 1
        
        for i in 0..<n {
            let j = (i + 1) % n
            if ring[i].count >= 2 && ring[j].count >= 2 {
                area += ring[i][0] * ring[j][1]
                area -= ring[j][0] * ring[i][1]
            }
        }
        
        return abs(area) / 2.0
    }
}

private struct TilequeryGeometry: Codable {
    let type: String
    let coordinates: AnyCodable
}

// MARK: - Errors

enum MapboxBuildingsAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noBuildingsFound
    case invalidGeometry
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Mapbox Tilequery URL"
        case .invalidResponse:
            return "Invalid response from Mapbox"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noBuildingsFound:
            return "No buildings found in the area"
        case .invalidGeometry:
            return "Invalid building geometry"
        }
    }
}
