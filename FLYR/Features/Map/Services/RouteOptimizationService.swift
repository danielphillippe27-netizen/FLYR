import Foundation
import CoreLocation

/// Service for optimizing routes using TSP algorithms and road-aware pathfinding
@MainActor
class RouteOptimizationService {
    
    static let shared = RouteOptimizationService()
    
    // Constants
    private let walkingSpeedMetersPerSecond: Double = 1.4 // Average human walking pace
    private let timePerStopSeconds: Double = 120.0 // 2 minutes per stop
    
    private init() {}
    
    // MARK: - Main Optimization Method
    
    /// Optimize route for a set of addresses
    /// - Parameters:
    ///   - addresses: Campaign addresses to visit
    ///   - startLocation: Starting location (user's current position)
    ///   - targetCount: Optional target count (if less than total, select best subset)
    ///   - roads: Road features for road-aware routing
    ///   - campaignId: Optional campaign ID for fetching roads if not provided
    /// - Returns: Optimized route with waypoints and segments
    func optimizeRoute(
        addresses: [CampaignAddress],
        startLocation: CLLocationCoordinate2D,
        targetCount: Int? = nil,
        roads: [RoadFeature]? = nil,
        campaignId: String? = nil
    ) async -> OptimizedRoute? {
        
        print("🗺️ [RouteOptimization] Starting optimization for \(addresses.count) addresses")
        
        // Filter addresses with valid coordinates
        let validAddresses = addresses.filter { $0.coordinate != nil }
        
        guard !validAddresses.isEmpty else {
            print("⚠️ [RouteOptimization] No valid addresses with coordinates")
            return nil
        }
        
        // Select subset if target count is specified
        let selectedAddresses: [CampaignAddress]
        if let targetCount = targetCount, targetCount < validAddresses.count {
            selectedAddresses = selectBestSubset(
                addresses: validAddresses,
                startLocation: startLocation,
                count: targetCount
            )
        } else {
            selectedAddresses = validAddresses
        }
        
        print("🗺️ [RouteOptimization] Optimizing route for \(selectedAddresses.count) addresses")
        
        // Phase 1: TSP - Find optimal order
        let coordinates = selectedAddresses.compactMap { $0.coordinate }
        let orderedIndices = solveTSP(
            points: coordinates,
            startLocation: startLocation
        )
        
        // Reorder addresses based on TSP solution
        let orderedAddresses = orderedIndices.map { selectedAddresses[$0] }
        
        // Phase 2: Road-aware routing (if roads available)
        var roadGraph: RoadGraph?
        if let roads = roads, !roads.isEmpty {
            roadGraph = buildRoadGraph(roads: roads)
            print("🗺️ [RouteOptimization] Built road graph with \(roadGraph?.nodeCount ?? 0) nodes")
        } else if let campaignId = campaignId {
            // Try to fetch roads
            if let fetchedRoads = await fetchRoads(campaignId: campaignId) {
                roadGraph = buildRoadGraph(roads: fetchedRoads)
                print("🗺️ [RouteOptimization] Built road graph with \(roadGraph?.nodeCount ?? 0) nodes")
            }
        }
        
        // Build waypoints and segments
        let waypoints = createWaypoints(
            addresses: orderedAddresses,
            startTime: Date()
        )
        
        let segments = createSegments(
            waypoints: waypoints,
            startLocation: startLocation,
            roadGraph: roadGraph
        )
        
        // Calculate totals
        let totalDistance = segments.reduce(0.0) { $0 + $1.distance }
        let travelTime = totalDistance / walkingSpeedMetersPerSecond
        let stopTime = Double(waypoints.count) * timePerStopSeconds
        let estimatedDuration = travelTime + stopTime
        
        let route = OptimizedRoute(
            waypoints: waypoints,
            roadSegments: segments,
            totalDistance: totalDistance,
            estimatedDuration: estimatedDuration
        )
        
        print("✅ [RouteOptimization] Route optimized: \(route.formattedDistance), \(route.formattedDuration), \(route.stopCount) stops")
        
        return route
    }
    
    // MARK: - TSP Algorithm
    
    /// Solve Traveling Salesman Problem using nearest-neighbor + 2-opt
    private func solveTSP(points: [CLLocationCoordinate2D], startLocation: CLLocationCoordinate2D) -> [Int] {
        guard !points.isEmpty else { return [] }
        
        // Add start location as point 0
        let allPoints = [startLocation] + points
        let n = allPoints.count
        
        // Nearest neighbor greedy construction
        var tour = nearestNeighborTSP(points: allPoints)
        
        // Apply 2-opt improvement if small enough
        if n <= 100 {
            tour = twoOptImprovement(tour: tour, points: allPoints, maxIterations: 100)
        }
        
        // Remove the start location index (0) and adjust remaining indices
        return tour.filter { $0 != 0 }.map { $0 - 1 }
    }
    
    /// Nearest neighbor heuristic
    private func nearestNeighborTSP(points: [CLLocationCoordinate2D]) -> [Int] {
        let n = points.count
        guard n > 0 else { return [] }
        
        var tour: [Int] = [0] // Start at first point (start location)
        var unvisited = Set(1..<n)
        
        while !unvisited.isEmpty {
            let current = tour.last!
            let currentPoint = points[current]
            
            // Find nearest unvisited point
            var nearestIdx = unvisited.first!
            var nearestDist = distance(currentPoint, points[nearestIdx])
            
            for idx in unvisited {
                let dist = distance(currentPoint, points[idx])
                if dist < nearestDist {
                    nearestDist = dist
                    nearestIdx = idx
                }
            }
            
            tour.append(nearestIdx)
            unvisited.remove(nearestIdx)
        }
        
        return tour
    }
    
    /// 2-opt improvement
    private func twoOptImprovement(tour: [Int], points: [CLLocationCoordinate2D], maxIterations: Int) -> [Int] {
        guard tour.count >= 4 else { return tour }
        var currentTour = tour
        var improved = true
        var iterations = 0
        
        while improved && iterations < maxIterations {
            improved = false
            iterations += 1
            
            for i in 1..<(currentTour.count - 2) {
                for j in (i + 1)..<(currentTour.count - 1) {
                    // Try reversing segment [i...j]
                    let newTour = twoOptSwap(tour: currentTour, i: i, j: j)
                    
                    if tourLength(newTour, points: points) < tourLength(currentTour, points: points) {
                        currentTour = newTour
                        improved = true
                    }
                }
            }
        }
        
        return currentTour
    }
    
    /// Perform 2-opt swap
    private func twoOptSwap(tour: [Int], i: Int, j: Int) -> [Int] {
        var newTour = tour
        newTour[i...j].reverse()
        return newTour
    }
    
    /// Calculate total tour length
    private func tourLength(_ tour: [Int], points: [CLLocationCoordinate2D]) -> Double {
        var length = 0.0
        for i in 0..<(tour.count - 1) {
            length += distance(points[tour[i]], points[tour[i + 1]])
        }
        return length
    }
    
    /// Distance between two coordinates in meters
    private func distance(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return loc1.distance(from: loc2)
    }
    
    // MARK: - Subset Selection
    
    /// Select best subset of addresses based on proximity and TSP optimization
    private func selectBestSubset(
        addresses: [CampaignAddress],
        startLocation: CLLocationCoordinate2D,
        count: Int
    ) -> [CampaignAddress] {
        guard count < addresses.count else { return addresses }
        
        // First, run TSP on all addresses to find optimal global order
        let allCoords = addresses.compactMap { $0.coordinate }
        let orderedIndices = solveTSP(points: allCoords, startLocation: startLocation)
        
        // Take first N addresses from optimized order
        let selectedIndices = Array(orderedIndices.prefix(count))
        return selectedIndices.map { addresses[$0] }
    }
    
    // MARK: - Road Graph
    
    /// Build road graph from road features
    private func buildRoadGraph(roads: [RoadFeature]) -> RoadGraph {
        let graph = RoadGraph()
        
        for road in roads {
            if let lineString = extractLineStringCoordinates(from: road.geometry) {
                graph.addRoad(lineString: lineString, roadClass: road.properties.roadClass)
            }
        }
        
        return graph
    }
    
    /// Extract coordinates from GeoJSON geometry
    private func extractLineStringCoordinates(from geometry: MapFeatureGeoJSONGeometry) -> [CLLocationCoordinate2D]? {
        // Try LineString first
        if let coords = geometry.asLineString {
            return coords.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        }
        
        // Try MultiLineString
        if let lineStrings = geometry.asMultiLineString {
            // For MultiLineString, concatenate all line strings
            return lineStrings.flatMap { lineString in
                lineString.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            }
        }
        
        return nil
    }
    
    /// Fetch roads for a campaign
    private func fetchRoads(campaignId: String) async -> [RoadFeature]? {
        let service = await MainActor.run { MapFeaturesService.shared }
        await service.fetchCampaignRoads(campaignId: campaignId)
        return await MainActor.run { service.roads?.features }
    }
    
    // MARK: - Waypoints & Segments
    
    /// Create waypoints from ordered addresses
    private func createWaypoints(
        addresses: [CampaignAddress],
        startTime: Date
    ) -> [RouteWaypoint] {
        return addresses.enumerated().map { index, address in
            RouteWaypoint(
                id: address.id,
                address: address.address,
                coordinate: address.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                orderIndex: index,
                estimatedArrivalTime: nil // Can be calculated later if needed
            )
        }
    }
    
    /// Create road segments between waypoints
    private func createSegments(
        waypoints: [RouteWaypoint],
        startLocation: CLLocationCoordinate2D,
        roadGraph: RoadGraph?
    ) -> [RoadSegment] {
        guard !waypoints.isEmpty else { return [] }
        
        var segments: [RoadSegment] = []
        var previousCoord = startLocation
        
        for waypoint in waypoints {
            let segment: RoadSegment
            
            if let graph = roadGraph,
               let (path, distance) = graph.findDetailedPath(from: previousCoord, to: waypoint.coordinate) {
                // Road-aware segment
                segment = RoadSegment(
                    fromWaypointId: waypoint.id, // Using waypoint ID for tracking
                    toWaypointId: waypoint.id,
                    coordinates: path,
                    distance: distance,
                    roadClass: nil
                )
            } else {
                // Straight-line fallback
                let straightDistance = distance(previousCoord, waypoint.coordinate)
                segment = RoadSegment(
                    fromWaypointId: waypoint.id,
                    toWaypointId: waypoint.id,
                    coordinates: [previousCoord, waypoint.coordinate],
                    distance: straightDistance,
                    roadClass: nil
                )
            }
            
            segments.append(segment)
            previousCoord = waypoint.coordinate
        }
        
        return segments
    }
}
