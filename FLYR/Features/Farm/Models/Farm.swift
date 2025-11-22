import Foundation
import CoreLocation

/// Farm model representing a geographic farming territory
struct Farm: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let userId: UUID
    let name: String
    let polygon: String? // GeoJSON string from PostGIS
    let startDate: Date
    let endDate: Date
    let frequency: Int // touches per month (1-4)
    let createdAt: Date
    let areaLabel: String? // Optional area label/description
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "owner_id"
        case name
        case polygon
        case startDate = "start_date"
        case endDate = "end_date"
        case frequency
        case createdAt = "created_at"
        case areaLabel = "area_label"
    }
    
    /// Convert polygon GeoJSON string to CLLocationCoordinate2D array
    /// Handles both GeoJSON Feature and raw Geometry formats
    var polygonCoordinates: [CLLocationCoordinate2D]? {
        guard let polygon = polygon else { return nil }
        
        // Try to parse as JSON
        guard let data = polygon.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Handle GeoJSON Feature format
        if let geometry = json["geometry"] as? [String: Any],
           let type = geometry["type"] as? String,
           type == "Polygon",
           let coordinates = geometry["coordinates"] as? [[[Double]]],
           let firstRing = coordinates.first {
            return firstRing.compactMap { coord in
                guard coord.count >= 2 else { return nil }
                return CLLocationCoordinate2D(
                    latitude: coord[1],
                    longitude: coord[0]
                )
            }
        }
        
        // Handle raw Geometry format
        if let type = json["type"] as? String,
           type == "Polygon",
           let coordinates = json["coordinates"] as? [[[Double]]],
           let firstRing = coordinates.first {
            return firstRing.compactMap { coord in
                guard coord.count >= 2 else { return nil }
                return CLLocationCoordinate2D(
                    latitude: coord[1],
                    longitude: coord[0]
                )
            }
        }
        
        return nil
    }
    
    /// Check if farm is currently active
    var isActive: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }
    
    /// Check if farm is completed
    var isCompleted: Bool {
        Date() > endDate
    }
    
    /// Calculate progress percentage (0.0 - 1.0)
    var progress: Double {
        let now = Date()
        guard now >= startDate && endDate > startDate else {
            return now < startDate ? 0.0 : 1.0
        }
        
        let totalDuration = endDate.timeIntervalSince(startDate)
        let elapsed = now.timeIntervalSince(startDate)
        return min(max(elapsed / totalDuration, 0.0), 1.0)
    }
}

/// Database row representation for farms
struct FarmDBRow: Codable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let polygon: String? // PostGIS returns as GeoJSON
    let startDate: Date
    let endDate: Date
    let frequency: Int
    let createdAt: Date
    let areaLabel: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case polygon
        case startDate = "start_date"
        case endDate = "end_date"
        case frequency
        case createdAt = "created_at"
        case areaLabel = "area_label"
    }
    
    func toFarm() -> Farm {
        Farm(
            id: id,
            userId: ownerId,
            name: name,
            polygon: polygon,
            startDate: startDate,
            endDate: endDate,
            frequency: frequency,
            createdAt: createdAt,
            areaLabel: areaLabel
        )
    }
}

