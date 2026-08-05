import Foundation
import CoreLocation

/// A waypoint in an optimized route
struct RouteWaypoint: Identifiable, Codable, Equatable {
    let id: UUID
    let address: String
    let coordinate: CLLocationCoordinate2D
    let orderIndex: Int
    let estimatedArrivalTime: Date?
    
    init(
        id: UUID,
        address: String,
        coordinate: CLLocationCoordinate2D,
        orderIndex: Int,
        estimatedArrivalTime: Date? = nil
    ) {
        self.id = id
        self.address = address
        self.coordinate = coordinate
        self.orderIndex = orderIndex
        self.estimatedArrivalTime = estimatedArrivalTime
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, address, latitude, longitude, orderIndex, estimatedArrivalTime
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        address = try container.decode(String.self, forKey: .address)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        orderIndex = try container.decode(Int.self, forKey: .orderIndex)
        estimatedArrivalTime = try container.decodeIfPresent(Date.self, forKey: .estimatedArrivalTime)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(address, forKey: .address)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(orderIndex, forKey: .orderIndex)
        try container.encodeIfPresent(estimatedArrivalTime, forKey: .estimatedArrivalTime)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: RouteWaypoint, rhs: RouteWaypoint) -> Bool {
        lhs.id == rhs.id &&
        lhs.address == rhs.address &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.orderIndex == rhs.orderIndex
    }
}

/// A road segment connecting two waypoints
struct RoadSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let fromWaypointId: UUID
    let toWaypointId: UUID
    let coordinates: [CLLocationCoordinate2D]
    let distance: Double // meters
    let roadClass: String?
    
    init(
        id: UUID = UUID(),
        fromWaypointId: UUID,
        toWaypointId: UUID,
        coordinates: [CLLocationCoordinate2D],
        distance: Double,
        roadClass: String? = nil
    ) {
        self.id = id
        self.fromWaypointId = fromWaypointId
        self.toWaypointId = toWaypointId
        self.coordinates = coordinates
        self.distance = distance
        self.roadClass = roadClass
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, fromWaypointId, toWaypointId, coordinatesList, distance, roadClass
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fromWaypointId = try container.decode(UUID.self, forKey: .fromWaypointId)
        toWaypointId = try container.decode(UUID.self, forKey: .toWaypointId)
        
        // Decode array of [lat, lon] pairs
        let coordPairs = try container.decode([[Double]].self, forKey: .coordinatesList)
        coordinates = coordPairs.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        
        distance = try container.decode(Double.self, forKey: .distance)
        roadClass = try container.decodeIfPresent(String.self, forKey: .roadClass)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fromWaypointId, forKey: .fromWaypointId)
        try container.encode(toWaypointId, forKey: .toWaypointId)
        
        // Encode as array of [lat, lon] pairs
        let coordPairs = coordinates.map { [$0.latitude, $0.longitude] }
        try container.encode(coordPairs, forKey: .coordinatesList)
        
        try container.encode(distance, forKey: .distance)
        try container.encodeIfPresent(roadClass, forKey: .roadClass)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: RoadSegment, rhs: RoadSegment) -> Bool {
        lhs.id == rhs.id
    }
}

/// An optimized route containing waypoints and road segments
struct OptimizedRoute: Codable, Equatable {
    let waypoints: [RouteWaypoint]
    let roadSegments: [RoadSegment]
    let totalDistance: Double // meters
    let estimatedDuration: TimeInterval // seconds
    let createdAt: Date
    
    init(
        waypoints: [RouteWaypoint],
        roadSegments: [RoadSegment],
        totalDistance: Double,
        estimatedDuration: TimeInterval,
        createdAt: Date = Date()
    ) {
        self.waypoints = waypoints
        self.roadSegments = roadSegments
        self.totalDistance = totalDistance
        self.estimatedDuration = estimatedDuration
        self.createdAt = createdAt
    }
    
    /// Total number of stops in the route
    var stopCount: Int {
        waypoints.count
    }
    
    /// Total distance in kilometers
    var totalDistanceKm: Double {
        totalDistance / 1000.0
    }
    
    /// Formatted distance string (e.g., "2.5 km")
    var formattedDistance: String {
        String(format: "%.1f km", totalDistanceKm)
    }
    
    /// Formatted duration string (e.g., "1h 23m" or "45m")
    var formattedDuration: String {
        let hours = Int(estimatedDuration) / 3600
        let minutes = (Int(estimatedDuration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Get all coordinates for the entire route path
    var allCoordinates: [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        
        for segment in roadSegments {
            coordinates.append(contentsOf: segment.coordinates)
        }
        
        return coordinates
    }
    
    /// Convert route to JSON for database storage
    func toJSON() -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(self),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        
        return json
    }
    
    /// Create route from JSON
    static func fromJSON(_ json: [String: Any]) -> OptimizedRoute? {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(OptimizedRoute.self, from: data)
    }
}
