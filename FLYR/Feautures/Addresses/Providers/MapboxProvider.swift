import Foundation
import CoreLocation

// MARK: - Mapbox Provider

/// Mapbox API provider - fallback for missing addresses with progressive street-unlock
public struct MapboxProvider: AddressProvider {
    private let geoAPI = GeoAPI.shared
    
    public init() {}
    
    public func nearest(center: CLLocationCoordinate2D, limit: Int) async throws -> [AddressCandidate] {
        print("🗺️ [MAPBOX] Finding \(limit) nearest addresses to \(center)")
        
        // Use the expanded search with progressive street-unlock
        let results = try await nearestExpanded(center: center, limit: limit)
        print("🗺️ [MAPBOX] Found \(results.count) addresses from Mapbox")
        
        return results
    }
    
    public func sameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, limit: Int) async throws -> [AddressCandidate] {
        print("🗺️ [MAPBOX] Finding \(limit) addresses on street '\(street)' in locality '\(locality ?? "any")'")
        
        // Use the existing street-locked search
        let results = try await geoAPI.nearbyAddresses(around: seed, limit: limit)
        
        // Filter to only addresses on the same street
        let filtered = results.filter { candidate in
            candidate.street.uppercased() == street.uppercased()
        }
        
        print("🗺️ [MAPBOX] Found \(filtered.count) addresses on street from Mapbox")
        
        return filtered
    }
    
    /// Expanded search with progressive street-unlock logic
    func nearestExpanded(center: CLLocationCoordinate2D, limit: Int, disableStreetLock: Bool = false) async throws -> [AddressCandidate] {
        print("🗺️ [MAPBOX EXPANDED] Starting progressive search for \(limit) addresses (street-lock: \(!disableStreetLock))")
        
        var results: [String: AddressCandidate] = [:]
        let target = limit
        let radii: [Double] = [100, 250, 500, 800, 1200, 2000, 3000, 6000]
        var streetLock = !disableStreetLock
        
        // Get baseline street name for street-lock filtering (skip if disabled)
        let baselineStreetName: String
        if !disableStreetLock {
            do {
                let streetMeta = try await geoAPI.reverseStreet(center)
                baselineStreetName = streetMeta.street.uppercased()
                print("🗺️ [MAPBOX EXPANDED] Baseline street: '\(baselineStreetName)'")
            } catch {
                print("⚠️ [MAPBOX EXPANDED] Could not get street name, disabling street-lock")
                streetLock = false
                baselineStreetName = ""
            }
        } else {
            print("🗺️ [MAPBOX EXPANDED] Street-lock disabled by caller")
            baselineStreetName = ""
        }
        
        for radius in radii {
            print("🗺️ [MAPBOX EXPANDED] Searching radius \(radius)m (street-lock: \(streetLock))")
            
            // Get addresses in this radius
            let batch = try await geoAPI.nearbyAddresses(around: center, limit: 50)
                .filter { $0.street != "" } // Only addresses with street names
            
            // Apply street-lock filter if enabled
            let filtered = streetLock
                ? batch.filter { normalize($0.street) == baselineStreetName }
                : batch
            
            print("🗺️ [MAPBOX EXPANDED] Found \(batch.count) total, \(filtered.count) after street filter")
            
            // Add to results with deduplication
            for candidate in filtered {
                let key = "\(normalize(candidate.address))|\(round(candidate.coordinate.latitude, 6)),\(round(candidate.coordinate.longitude, 6))"
                if results[key] == nil {
                    // Create new candidate with mapbox source
                    let mapboxCandidate = AddressCandidate(
                        id: candidate.id,
                        address: candidate.address,
                        coordinate: candidate.coordinate,
                        distanceMeters: candidate.distanceMeters,
                        number: candidate.number,
                        street: candidate.street,
                        houseKey: candidate.houseKey,
                        source: "mapbox"
                    )
                    results[key] = mapboxCandidate
                }
            }
            
            // Check if we have enough results
            if results.count >= target {
                print("🗺️ [MAPBOX EXPANDED] Reached target of \(target) addresses")
                break
            }
            
            // Disable street-lock after 500m radius if we don't have enough results
            if streetLock && radius >= 500 && results.count < target {
                print("🗺️ [MAPBOX EXPANDED] Disabling street-lock after \(radius)m (only found \(results.count)/\(target))")
                streetLock = false
            }
        }
        
        // Convert to array, sort by distance, and take limit
        let finalResults = Array(results.values)
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(target)
        
        print("🗺️ [MAPBOX EXPANDED] Final results: \(finalResults.count) addresses")
        return Array(finalResults)
    }
    
    /// Normalize street name for comparison
    private func normalize(_ street: String) -> String {
        return street
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }
    
    /// Round coordinate to specified decimal places
    private func round(_ value: Double, _ places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (value * multiplier).rounded() / multiplier
    }
}


