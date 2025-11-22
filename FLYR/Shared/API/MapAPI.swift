import Foundation
import CoreLocation

/// Protocol for map API services
protocol MapAPIType {
    func generateMapImage(center: CLLocationCoordinate2D, 
                          zoom: Int, 
                          width: Int, 
                          height: Int) async throws -> Data
    func getMapSnapshot(center: CLLocationCoordinate2D, 
                       markers: [MapMarker]) async throws -> Data
}

/// Represents a map marker
struct MapMarker {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let color: String
    
    init(coordinate: CLLocationCoordinate2D, title: String, color: String = "red") {
        self.coordinate = coordinate
        self.title = title
        self.color = color
    }
}

/// Mapbox Static Images API implementation
class MapboxMapAPI: MapAPIType {
    private let accessToken: String
    
    init(accessToken: String) {
        self.accessToken = accessToken
    }
    
    func generateMapImage(center: CLLocationCoordinate2D, 
                         zoom: Int = 15, 
                         width: Int = 400, 
                         height: Int = 240) async throws -> Data {
        
        let urlString = """
        https://api.mapbox.com/styles/v1/mapbox/streets-v11/static/\(center.longitude),\(center.latitude),\(zoom)/\(width)x\(height)@2x?access_token=\(accessToken)
        """
        
        guard let url = URL(string: urlString) else {
            throw MapAPIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MapAPIError.requestFailed
        }
        
        return data
    }
    
    func getMapSnapshot(center: CLLocationCoordinate2D, 
                       markers: [MapMarker]) async throws -> Data {
        var urlString = """
        https://api.mapbox.com/styles/v1/mapbox/streets-v11/static/\(center.longitude),\(center.latitude),15/400x240@2x?access_token=\(accessToken)
        """
        
        // Add markers to URL
        for (index, marker) in markers.enumerated() {
            urlString += "&markers=\(marker.color)|\(marker.coordinate.longitude),\(marker.coordinate.latitude)"
        }
        
        print("🗺️ [MAPAPI DEBUG] Requesting URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ [MAPAPI DEBUG] Invalid URL")
            throw MapAPIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [MAPAPI DEBUG] Invalid response")
            throw MapAPIError.requestFailed
        }
        
        print("🗺️ [MAPAPI DEBUG] Response status: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            print("❌ [MAPAPI DEBUG] HTTP Error: \(httpResponse.statusCode)")
            throw MapAPIError.requestFailed
        }
        
        print("✅ [MAPAPI DEBUG] Map snapshot received, size: \(data.count) bytes")
        return data
    }
}

/// Map API errors
enum MapAPIError: Error {
    case invalidURL
    case requestFailed
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid map URL"
        case .requestFailed:
            return "Map request failed"
        case .invalidResponse:
            return "Invalid map response"
        }
    }
}
