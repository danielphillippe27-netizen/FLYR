import Foundation
import CoreLocation

/// A graph representation of road networks for pathfinding
class RoadGraph {
    
    // MARK: - Node
    
    /// A node in the road graph (typically an intersection or endpoint)
    struct Node: Hashable {
        let coordinate: CLLocationCoordinate2D
        
        // Custom hashable implementation for CLLocationCoordinate2D
        func hash(into hasher: inout Hasher) {
            hasher.combine(coordinate.latitude)
            hasher.combine(coordinate.longitude)
        }
        
        static func == (lhs: Node, rhs: Node) -> Bool {
            // Use small epsilon for floating point comparison
            abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.000001 &&
            abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.000001
        }
        
        /// Distance to another node in meters
        func distance(to other: Node) -> Double {
            let from = CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            let to = CLLocation(
                latitude: other.coordinate.latitude,
                longitude: other.coordinate.longitude
            )
            return from.distance(from: to)
        }
    }
    
    // MARK: - Edge
    
    /// An edge connecting two nodes in the road graph
    struct Edge {
        let to: Node
        let distance: Double // meters
        let roadClass: String?
        let coordinates: [CLLocationCoordinate2D] // Full path for this segment
        
        /// Weight for pathfinding (lower is better)
        var weight: Double {
            // Weight based on distance and road class
            var multiplier = 1.0
            
            // Prefer major roads (lower multiplier = lower weight = preferred)
            switch roadClass?.lowercased() {
            case "motorway", "trunk":
                multiplier = 0.8
            case "primary":
                multiplier = 0.9
            case "secondary":
                multiplier = 1.0
            case "tertiary":
                multiplier = 1.1
            case "residential", "unclassified":
                multiplier = 1.2
            default:
                multiplier = 1.3
            }
            
            return distance * multiplier
        }
    }
    
    // MARK: - Properties
    
    private var adjacencyList: [Node: [Edge]] = [:]
    private var allNodes: Set<Node> = []
    
    var nodeCount: Int {
        allNodes.count
    }
    
    var edgeCount: Int {
        adjacencyList.values.reduce(0) { $0 + $1.count }
    }
    
    // MARK: - Graph Construction
    
    /// Add a road to the graph from a LineString of coordinates
    func addRoad(lineString: [CLLocationCoordinate2D], roadClass: String?) {
        guard lineString.count >= 2 else { return }
        
        // Create nodes for each coordinate
        let nodes = lineString.map { Node(coordinate: $0) }
        
        // Add all nodes to the set
        allNodes.formUnion(nodes)
        
        // Create edges between consecutive nodes
        for i in 0..<(nodes.count - 1) {
            let from = nodes[i]
            let to = nodes[i + 1]
            
            let distance = from.distance(to: to)
            
            // Edge coordinates are just the two endpoints for this segment
            let edgeCoords = [from.coordinate, to.coordinate]
            
            // Add forward edge
            let forwardEdge = Edge(
                to: to,
                distance: distance,
                roadClass: roadClass,
                coordinates: edgeCoords
            )
            adjacencyList[from, default: []].append(forwardEdge)
            
            // Add backward edge (roads are bidirectional)
            let backwardEdge = Edge(
                to: from,
                distance: distance,
                roadClass: roadClass,
                coordinates: edgeCoords.reversed()
            )
            adjacencyList[to, default: []].append(backwardEdge)
        }
    }
    
    /// Find the nearest node to a given coordinate
    func nearestNode(to coordinate: CLLocationCoordinate2D, maxDistance: Double = 500.0) -> Node? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        var nearestNode: Node?
        var minDistance = maxDistance
        
        for node in allNodes {
            let nodeLocation = CLLocation(
                latitude: node.coordinate.latitude,
                longitude: node.coordinate.longitude
            )
            let distance = target.distance(from: nodeLocation)
            
            if distance < minDistance {
                minDistance = distance
                nearestNode = node
            }
        }
        
        return nearestNode
    }
    
    // MARK: - Pathfinding
    
    /// Find the shortest path between two nodes using Dijkstra's algorithm
    func findShortestPath(from start: Node, to end: Node) -> [Node]? {
        guard allNodes.contains(start) && allNodes.contains(end) else {
            return nil
        }
        
        // Special case: start == end
        if start == end {
            return [start]
        }
        
        var distances: [Node: Double] = [start: 0]
        var previous: [Node: Node] = [:]
        var unvisited = Set(allNodes)
        
        while !unvisited.isEmpty {
            // Find unvisited node with minimum distance
            guard let current = unvisited.min(by: { node1, node2 in
                let dist1 = distances[node1] ?? Double.infinity
                let dist2 = distances[node2] ?? Double.infinity
                return dist1 < dist2
            }) else {
                break
            }
            
            // If we reached the end, reconstruct path
            if current == end {
                return reconstructPath(from: start, to: end, previous: previous)
            }
            
            let currentDistance = distances[current] ?? Double.infinity
            
            // If current distance is infinity, there's no path
            if currentDistance == Double.infinity {
                break
            }
            
            unvisited.remove(current)
            
            // Check all neighbors
            guard let edges = adjacencyList[current] else { continue }
            
            for edge in edges {
                let neighbor = edge.to
                guard unvisited.contains(neighbor) else { continue }
                
                let altDistance = currentDistance + edge.weight
                let neighborDistance = distances[neighbor] ?? Double.infinity
                
                if altDistance < neighborDistance {
                    distances[neighbor] = altDistance
                    previous[neighbor] = current
                }
            }
        }
        
        // No path found
        return nil
    }
    
    /// Find path with full coordinate details
    func findDetailedPath(from startCoord: CLLocationCoordinate2D, to endCoord: CLLocationCoordinate2D) -> (path: [CLLocationCoordinate2D], distance: Double)? {
        // Find nearest nodes
        guard let startNode = nearestNode(to: startCoord),
              let endNode = nearestNode(to: endCoord) else {
            return nil
        }
        
        // Find path between nodes
        guard let nodePath = findShortestPath(from: startNode, to: endNode) else {
            return nil
        }
        
        // Build detailed coordinate path and calculate distance
        var coordinates: [CLLocationCoordinate2D] = []
        var totalDistance: Double = 0.0
        
        for i in 0..<(nodePath.count - 1) {
            let from = nodePath[i]
            let to = nodePath[i + 1]
            
            // Find the edge between these nodes
            if let edges = adjacencyList[from],
               let edge = edges.first(where: { $0.to == to }) {
                
                // Add coordinates from this edge (excluding first if not the first segment)
                if i == 0 {
                    coordinates.append(contentsOf: edge.coordinates)
                } else {
                    coordinates.append(contentsOf: edge.coordinates.dropFirst())
                }
                
                totalDistance += edge.distance
            }
        }
        
        return (coordinates, totalDistance)
    }
    
    /// Reconstruct path from previous nodes dictionary
    private func reconstructPath(from start: Node, to end: Node, previous: [Node: Node]) -> [Node] {
        var path: [Node] = [end]
        var current = end
        
        while current != start {
            guard let prev = previous[current] else {
                return [] // Path broken
            }
            path.insert(prev, at: 0)
            current = prev
        }
        
        return path
    }
    
    // MARK: - Utilities
    
    /// Clear the graph
    func clear() {
        adjacencyList.removeAll()
        allNodes.removeAll()
    }
    
    /// Get neighbors of a node
    func neighbors(of node: Node) -> [Edge] {
        return adjacencyList[node] ?? []
    }
    
    /// Check if a node exists in the graph
    func contains(_ node: Node) -> Bool {
        return allNodes.contains(node)
    }
}
