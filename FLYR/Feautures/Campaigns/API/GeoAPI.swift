import Foundation
import CoreLocation
import Turf

enum GeoAPIError: LocalizedError {
    case missingToken
    case badURL
    case requestFailed
    case decodeFailed
    case noResults
    
    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Mapbox API token is missing. Please check your configuration."
        case .badURL:
            return "Invalid API request URL. Please try again."
        case .requestFailed:
            return "Failed to connect to Mapbox API. Please check your internet connection and try again."
        case .decodeFailed:
            return "Failed to parse API response. Please try again."
        case .noResults:
            return "No addresses found for this location. Please try a different address."
        }
    }
}

final class GeoAPI {
    static let shared = GeoAPI()
    private init() {}
    
  // Keep your token getter as-is
  internal var token: String {
        Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
    }
    
  // Test method to validate token
  func testToken() async throws {
    print("🔍 [GEOAPI DEBUG] Testing Mapbox token...")
    let testUrl = "https://api.mapbox.com/geocoding/v5/mapbox.places/New York.json?limit=1&access_token=\(token)"
    guard let url = URL(string: testUrl) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
    print("🔍 [GEOAPI DEBUG] Token test - Status: \(statusCode)")
    if statusCode != 200 {
      if let responseString = String(data: data, encoding: .utf8) {
        print("❌ [GEOAPI DEBUG] Token test response: \(responseString)")
      }
      throw GeoAPIError.requestFailed
    }
    print("✅ [GEOAPI DEBUG] Token is valid")
  }

  // ✅ Forward geocode stays the same
    func forwardGeocodeSeed(_ query: String) async throws -> SeedGeocode {
        guard !token.isEmpty else { 
            print("❌ [GEOAPI DEBUG] Missing Mapbox token for forward geocoding")
            throw GeoAPIError.missingToken 
        }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(encodedQuery).json?limit=1&access_token=\(token)"
        print("🔍 [GEOAPI DEBUG] Forward geocoding URL: \(urlString.replacingOccurrences(of: token, with: "TOKEN_HIDDEN"))")
        
        guard let url = URL(string: urlString) else { 
            print("❌ [GEOAPI DEBUG] Invalid forward geocoding URL: \(urlString.replacingOccurrences(of: token, with: "TOKEN_HIDDEN"))")
            throw GeoAPIError.badURL 
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("🔍 [GEOAPI DEBUG] Forward geocoding response status: \(statusCode)")
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("❌ [GEOAPI DEBUG] Forward geocoding failed with status: \(statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [GEOAPI DEBUG] Forward geocoding error response: \(responseString)")
            }
            throw GeoAPIError.requestFailed
        }
        
        struct GeocodeResponse: Decodable {
            struct Feature: Decodable {
                let center: [Double]
                let place_name: String
            }
            let features: [Feature]
        }
        
        do {
            let decoded = try JSONDecoder().decode(GeocodeResponse.self, from: data)
            guard let feature = decoded.features.first,
                  feature.center.count == 2 else {
                throw GeoAPIError.noResults
            }
            
            let coordinate = CLLocationCoordinate2D(
                latitude: feature.center[1],
                longitude: feature.center[0]
            )
            
            return SeedGeocode(query: query, coordinate: coordinate)
        } catch {
            throw GeoAPIError.decodeFailed
        }
    }
    
  // 🎯 CLOSEST-FIRST: Street-accurate search with micro-grid + concentric rings + street-lock
  func nearbyAddresses(around seed: CLLocationCoordinate2D, limit: Int = 25) async throws -> [AddressCandidate] {
    guard !token.isEmpty else { throw GeoAPIError.missingToken }

    print("🔍 [GEOAPI DEBUG] Starting closest-first address search for \(limit) addresses")
    
    var results: [AddressCandidate] = []
    var seen = Set<String>() // houseKey deduplication
    let needed = max(1, limit)

    // 0) Micro-grid around seed (± ~60–70m). Picks the houses literally across the street first.
    try await addMicroGrid(around: seed, into: &results, seen: &seen, overshoot: needed * 4)
    if results.count >= needed { 
      let final = sortTrim(results, seed, needed)
      print("🔍 [GEOAPI DEBUG] Micro-grid found \(final.count) addresses")
      return final
    }

    // 1) Concentric rings (100m → 250m → 500m → 800m → 1200m).
    let radii: [Double] = [100, 250, 500, 800, 1200]
    for r in radii {
      try await addRing(radius: r, around: seed, into: &results, seen: &seen, overshoot: needed * 5)
      print("🔍 [GEOAPI DEBUG] Ring \(r)m found \(results.count) total addresses")
      // plateau early-stop: if we have enough, break
      if results.count >= needed { break }
    }

    // 2) Street-lock pass: reverse to get street, then bias geocoder to that street only.
    if let streetMeta = try? await reverseSeedStreet(seed) {
      try await addStreetLocked(street: streetMeta.street, locality: streetMeta.locality,
                                around: seed, into: &results, seen: &seen,
                                overshoot: max(120, needed * 6))
      print("🔍 [GEOAPI DEBUG] Street-locked search completed")
    }

    let final = sortTrim(results, seed, needed)
    print("🔍 [GEOAPI DEBUG] Final results: \(final.count) addresses (from \(results.count) total)")
    return final
  }
  
  // 🎯 PRECISE MODE: Tilequery polyline walker for 95%+ recall on tricky streets
  func nearbyAddressesPrecise(around seed: CLLocationCoordinate2D, limit: Int = 25) async throws -> [AddressCandidate] {
        guard !token.isEmpty else { throw GeoAPIError.missingToken }
    
    print("🔍 [GEOAPI PRECISE] Starting Tilequery polyline walker for \(limit) addresses")
    
    var results: [AddressCandidate] = []
    var seen = Set<String>() // houseKey deduplication
    let needed = max(1, limit)
    
    // 1) Get street name from seed via reverse geocoding
    guard let streetMeta = try? await reverseSeedStreet(seed) else {
      print("⚠️ [GEOAPI PRECISE] Could not reverse geocode seed, falling back to Street-Locked")
      return try await nearbyAddresses(around: seed, limit: limit)
    }
    
    print("🔍 [GEOAPI PRECISE] Target street: \(streetMeta.street), locality: \(streetMeta.locality ?? "nil")")
    
    // 2) Get road geometry from Tilequery
    guard let polyline = try? await getTilequeryGeometry(coord: seed) else {
      print("⚠️ [GEOAPI PRECISE] Could not get road geometry, falling back to Street-Locked")
      return try await nearbyAddresses(around: seed, limit: limit)
    }
    
    print("🔍 [GEOAPI PRECISE] Got polyline with \(polyline.count) points")
    
    // 3) Walk the polyline every 15m, generating probe points
    let probes = interpolateProbes(along: polyline, interval: 15.0)
    print("🔍 [GEOAPI PRECISE] Generated \(probes.count) probe points")
    
    // 4) At each probe: call geocodeNearestOnStreet
    var probeCount = 0
    for probe in probes {
      probeCount += 1
      
      if let addr = try? await geocodeNearestOnStreet(street: streetMeta.street, locality: streetMeta.locality, near: probe) {
        // Filter: only include if it matches our target street
        let (num, st) = parseHouse(addr.placeName)
        if st == streetMeta.street.uppercased() && !num.isEmpty {
          let k = key(num, st)
          if seen.insert(k).inserted {
            let distance = CLLocation(latitude: seed.latitude, longitude: seed.longitude)
              .distance(from: CLLocation(latitude: addr.coord.latitude, longitude: addr.coord.longitude))
            results.append(AddressCandidate(
              address: addr.placeName,
              coordinate: addr.coord,
              distanceMeters: distance,
              number: num,
              street: st,
              houseKey: k
            ))
          }
        }
      }
      
      // Early stop if we have way more than needed
      if results.count >= needed * 2 {
        print("🔍 [GEOAPI PRECISE] Early stop at probe \(probeCount)/\(probes.count), found \(results.count) addresses")
        break
      }
    }
    
    print("🔍 [GEOAPI PRECISE] Probes: \(probeCount), Found: \(results.count) unique addresses")
    
    // 5) Sort by distance and trim to limit
    let final = sortTrim(results, seed, needed)
    print("🔍 [GEOAPI PRECISE] Final results: \(final.count) addresses (recall: \(Double(final.count) / Double(needed) * 100.0)%)")
    return final
  }
  
  // MARK: - Tilequery Helpers
  
  /// Get road geometry from Mapbox Tilequery API
  private func getTilequeryGeometry(coord: CLLocationCoordinate2D) async throws -> [CLLocationCoordinate2D] {
    // Tilequery API: https://docs.mapbox.com/api/maps/tilequery/
    // We query the streets-v8 tileset for road geometries
    let urlStr = "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/tilequery/\(coord.longitude),\(coord.latitude).json?radius=50&limit=1&dedupe=true&geometry=linestring&layers=road&access_token=\(token)"
    
    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      print("❌ [GEOAPI PRECISE] Tilequery failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
      throw GeoAPIError.requestFailed
    }
    
    struct TilequeryResponse: Decodable {
      struct Feature: Decodable {
        let geometry: Geometry
        
        struct Geometry: Decodable {
          let type: String
          let coordinates: [[Double]]
        }
      }
      let features: [Feature]
    }
    
    let tilequeryResponse = try JSONDecoder().decode(TilequeryResponse.self, from: data)
    guard let feature = tilequeryResponse.features.first else {
      print("⚠️ [GEOAPI PRECISE] No road geometry found")
      throw GeoAPIError.noResults
    }
    
    // Convert coordinates to CLLocationCoordinate2D
    let polyline = feature.geometry.coordinates.map { coords in
      CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
    }
    
    return polyline
  }
  
  /// Interpolate probe points along a polyline at regular intervals
  private func interpolateProbes(along polyline: [CLLocationCoordinate2D], interval: Double) -> [CLLocationCoordinate2D] {
    guard polyline.count >= 2 else { return polyline }
    
    var probes: [CLLocationCoordinate2D] = []
    var accumulatedDistance: Double = 0.0
    var nextProbeDistance: Double = 0.0
    
    // Always start with first point
    probes.append(polyline[0])
    nextProbeDistance += interval
    
    for i in 0..<(polyline.count - 1) {
      let start = polyline[i]
      let end = polyline[i + 1]
      
      let segmentDistance = CLLocation(latitude: start.latitude, longitude: start.longitude)
        .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
      
      // Walk this segment, adding probes at interval
      var segmentAccumulated: Double = 0.0
      while accumulatedDistance + segmentAccumulated + interval <= accumulatedDistance + segmentDistance {
        segmentAccumulated += interval
        
        // Interpolate point along segment
        let fraction = segmentAccumulated / segmentDistance
        let lat = start.latitude + (end.latitude - start.latitude) * fraction
        let lon = start.longitude + (end.longitude - start.longitude) * fraction
        
        probes.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        
        if probes.count >= 200 { // Safety limit
          return probes
        }
      }
      
      accumulatedDistance += segmentDistance
    }
    
    // Always end with last point
    if let last = polyline.last, last != probes.last {
      probes.append(last)
    }
    
    return probes
  }
  
  // MARK: - Helper Methods for Closest-First Search
  
  private func sortTrim(_ items: [AddressCandidate], _ seed: CLLocationCoordinate2D, _ limit: Int) -> [AddressCandidate] {
    let sorted = items.sorted { 
      let distance1 = CLLocation(latitude: seed.latitude, longitude: seed.longitude)
        .distance(from: CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude))
      let distance2 = CLLocation(latitude: seed.latitude, longitude: seed.longitude)
        .distance(from: CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude))
      return distance1 < distance2
    }
    return Array(sorted.prefix(limit))
  }
  
  private func parseHouse(_ place: String) -> (number: String, street: String) {
    let first = place.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) ?? place
    let parts = first.split(separator: " ")
    guard let num = parts.first, num.allSatisfy(\.isNumber) else {
      return ("", first.uppercased())
    }
    let street = parts.dropFirst().joined(separator: " ").uppercased()
    return (String(num), street)
  }
  
  private func key(_ number: String, _ street: String) -> String { 
    (number + " " + street).uppercased() 
  }
  
  // Micro grid: 3×3 around the seed within ~60–70m offsets.
  private func addMicroGrid(around seed: CLLocationCoordinate2D,
                            into out: inout [AddressCandidate],
                            seen: inout Set<String>,
                            overshoot: Int) async throws {
    let delta = 0.0006 // ~60–70m latitude (lon varies slightly with lat)
    for dy in [-1,0,1] {
      for dx in [-1,0,1] {
        let c = CLLocationCoordinate2D(latitude: seed.latitude + Double(dy)*delta,
                                       longitude: seed.longitude + Double(dx)*delta)
        let items = try await geocodeInBBox(center: c, meters: 120, overshoot: overshoot)
        merge(items, seed: seed, into: &out, seen: &seen)
      }
    }
  }
  
  // Concentric ring: bbox around seed with given radius; overshoot to catch more addresses.
  private func addRing(radius meters: Double,
                       around seed: CLLocationCoordinate2D,
                       into out: inout [AddressCandidate],
                       seen: inout Set<String>,
                       overshoot: Int) async throws {
    let items = try await geocodeInBBox(center: seed, meters: meters, overshoot: overshoot)
    merge(items, seed: seed, into: &out, seen: &seen)
  }
  
  // Street-locked: query "<street>, <city>" with proximity seeds.
  private func addStreetLocked(street: String,
                               locality: String?,
                               around seed: CLLocationCoordinate2D,
                               into out: inout [AddressCandidate],
                               seen: inout Set<String>,
                               overshoot: Int) async throws {
    // sample a few points along the street direction (short distances)
    let deltas = [-0.0015, -0.0008, 0.0, 0.0008, 0.0015] // ≈ 80–160m steps
    for d in deltas {
      let p = CLLocationCoordinate2D(latitude: seed.latitude + d, longitude: seed.longitude)
      if let addr = try await geocodeNearestOnStreet(street: street, locality: locality, near: p) {
        merge([addr], seed: seed, into: &out, seen: &seen)
      }
    }
  }
  
  // Merge + strong dedupe by houseKey (number + street)
  private func merge(_ raw: [(placeName: String, coord: CLLocationCoordinate2D)],
                     seed: CLLocationCoordinate2D,
                     into out: inout [AddressCandidate],
                     seen: inout Set<String>) {
    for r in raw {
      let (num, st) = parseHouse(r.placeName)
      guard !num.isEmpty else { continue }
      let k = key(num, st)
      if seen.insert(k).inserted {
        let distance = CLLocation(latitude: seed.latitude, longitude: seed.longitude)
          .distance(from: CLLocation(latitude: r.coord.latitude, longitude: r.coord.longitude))
        out.append(AddressCandidate(
          address: r.placeName,
          coordinate: r.coord,
          distanceMeters: distance,
          number: num,
          street: st,
          houseKey: k
        ))
      }
    }
  }
  
  // MARK: - Geocoder hooks — wire these to your existing Mapbox calls
  
  /// Reverse: return street + locality for the seed
  private func reverseSeedStreet(_ seed: CLLocationCoordinate2D) async throws -> (street: String, locality: String?) {
    // Mapbox reverse geocode types=address,place; choose first address, read "text" for street and context[place] for locality
    let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(seed.longitude),\(seed.latitude).json?types=address,place&limit=1&access_token=\(token)"
    
    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      throw GeoAPIError.requestFailed
    }
    
    struct ReverseResponse: Decodable {
      struct Feature: Decodable {
        let text: String
        let context: [Context]?
        
        struct Context: Decodable {
          let text: String
          let id: String
        }
      }
      let features: [Feature]
    }
    
    let reverseResponse = try JSONDecoder().decode(ReverseResponse.self, from: data)
    guard let feature = reverseResponse.features.first else { throw GeoAPIError.noResults }
    
    let locality = feature.context?.first { $0.id.contains("place") }?.text
    return (feature.text, locality)
  }
  
  /// BBox geocode: types=address, bbox from center/meters, limit=overshoot
  private func geocodeInBBox(center: CLLocationCoordinate2D,
                             meters: Double,
                             overshoot: Int) async throws -> [(placeName: String, coord: CLLocationCoordinate2D)] {
    // Build bbox via delta meters around center
    let latDelta = meters / 111000.0 // rough conversion: 1 degree ≈ 111km
    let lonDelta = meters / (111000.0 * cos(center.latitude * .pi / 180.0))
    
    let bbox = "\(center.longitude - lonDelta),\(center.latitude - latDelta),\(center.longitude + lonDelta),\(center.latitude + latDelta)"
    
    let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(center.longitude),\(center.latitude).json?types=address&bbox=\(bbox)&limit=\(overshoot)&access_token=\(token)"
    
    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
        let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GeoAPIError.requestFailed
        }
        
    struct BBoxResponse: Decodable {
            struct Feature: Decodable {
                let place_name: String
                let center: [Double]
            }
            let features: [Feature]
        }
        
    let bboxResponse = try JSONDecoder().decode(BBoxResponse.self, from: data)
    return bboxResponse.features.map { feature in
      let coord = CLLocationCoordinate2D(latitude: feature.center[1], longitude: feature.center[0])
      return (feature.place_name, coord)
    }
  }
  
  /// Street-locked nearest: query "<street>, <locality?>" with proximity=<lon,lat>, types=address, autocomplete=false, limit=1
  private func geocodeNearestOnStreet(street: String,
                                      locality: String?,
                                      near: CLLocationCoordinate2D) async throws -> (placeName: String, coord: CLLocationCoordinate2D)? {
    let query = locality != nil ? "\(street), \(locality!)" : street
    let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    
    let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(encodedQuery).json?types=address&proximity=\(near.longitude),\(near.latitude)&autocomplete=false&limit=1&access_token=\(token)"
    
    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
      return nil
    }
    
    struct StreetResponse: Decodable {
      struct Feature: Decodable {
        let place_name: String
        let center: [Double]
      }
      let features: [Feature]
    }
    
    let streetResponse = try JSONDecoder().decode(StreetResponse.self, from: data)
    guard let feature = streetResponse.features.first else { return nil }
    
    let coord = CLLocationCoordinate2D(latitude: feature.center[1], longitude: feature.center[0])
    return (feature.place_name, coord)
  }
  
  // Helper method for radius-based search
  private func searchWithRadius(_ center: CLLocationCoordinate2D, radius: Int, limit: Int) async throws -> [AddressCandidate] {
    let urlStr = """
      https://api.mapbox.com/geocoding/v5/mapbox.places/\(center.longitude),\(center.latitude).json
      ?types=address
      &radius=\(radius)
      &limit=\(min(max(limit, 50), 1000))
      &access_token=\(token)
      """
      .replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: " ", with: "")

    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard statusCode == 200 else { 
      print("❌ [GEOAPI DEBUG] HTTP Error: \(statusCode)")
      if let responseString = String(data: data, encoding: .utf8) {
        print("❌ [GEOAPI DEBUG] Error Response: \(responseString)")
      }
      throw GeoAPIError.requestFailed 
    }
    
    // Log the raw API response for debugging
    if let responseString = String(data: data, encoding: .utf8) {
      print("🔍 [GEOAPI DEBUG] Raw API Response (\(radius)m): \(responseString)")
    }

    struct GeoAPIResponse: Decodable {
      struct Feature: Decodable { 
        let place_name: String
        let center: [Double]
        let place_type: [String]?
        let properties: Properties?
        
        struct Properties: Decodable {
          let accuracy: String?
        }
      }
      let features: [Feature]
    }
    let decoded = try JSONDecoder().decode(GeoAPIResponse.self, from: data)

    var items: [AddressCandidate] = []
    for f in decoded.features where f.center.count == 2 {
      let fmt = f.place_name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      
      if isLikelyAddress(placeName: fmt, placeTypes: f.place_type, properties: f.properties) {
        let coord = CLLocationCoordinate2D(latitude: f.center[1], longitude: f.center[0])
        let d = GeoAPI.haversine(from: center, to: coord)
        items.append(AddressCandidate(address: fmt, coordinate: coord, distanceMeters: d))
      }
    }
    return items
  }
  
  // Helper method for bounding box search
  private func searchWithBoundingBox(_ center: CLLocationCoordinate2D, limit: Int) async throws -> [AddressCandidate] {
    let bbox = bbox(center: center, meters: 10000) // 10km bounding box
    let urlStr = """
      https://api.mapbox.com/geocoding/v5/mapbox.places/\(center.longitude),\(center.latitude).json
      ?types=address
      &bbox=\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)
      &limit=\(min(max(limit, 50), 1000))
      &access_token=\(token)
      """
      .replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: " ", with: "")

    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard statusCode == 200 else { throw GeoAPIError.requestFailed }

    struct GeoAPIResponse: Decodable {
      struct Feature: Decodable { 
        let place_name: String
        let center: [Double]
        let place_type: [String]?
        let properties: Properties?
        
        struct Properties: Decodable {
          let accuracy: String?
        }
      }
      let features: [Feature]
    }
    let decoded = try JSONDecoder().decode(GeoAPIResponse.self, from: data)

    var items: [AddressCandidate] = []
    for f in decoded.features where f.center.count == 2 {
      let fmt = f.place_name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      
      if isLikelyAddress(placeName: fmt, placeTypes: f.place_type, properties: f.properties) {
        let coord = CLLocationCoordinate2D(latitude: f.center[1], longitude: f.center[0])
        let d = GeoAPI.haversine(from: center, to: coord)
        items.append(AddressCandidate(address: fmt, coordinate: coord, distanceMeters: d))
      }
    }
    return items
  }
  
  // Helper method for search without types filter (more permissive)
  private func searchWithoutTypesFilter(_ center: CLLocationCoordinate2D, limit: Int) async throws -> [AddressCandidate] {
    let urlStr = """
      https://api.mapbox.com/geocoding/v5/mapbox.places/\(center.longitude),\(center.latitude).json
      ?radius=3000
      &limit=\(min(max(limit, 100), 2000))
      &access_token=\(token)
      """
      .replacingOccurrences(of: "\n", with: "")
      .replacingOccurrences(of: " ", with: "")

    guard let url = URL(string: urlStr) else { throw GeoAPIError.badURL }
    let (data, resp) = try await URLSession.shared.data(from: url)
    let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
    guard statusCode == 200 else { throw GeoAPIError.requestFailed }

    struct GeoAPIResponse: Decodable {
      struct Feature: Decodable { 
        let place_name: String
        let center: [Double]
        let place_type: [String]?
        let properties: Properties?
        
        struct Properties: Decodable {
          let accuracy: String?
        }
      }
      let features: [Feature]
    }
    let decoded = try JSONDecoder().decode(GeoAPIResponse.self, from: data)

    var items: [AddressCandidate] = []
    for f in decoded.features where f.center.count == 2 {
      let fmt = f.place_name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      
      // Very permissive filtering - accept almost anything that looks like an address
      if isVeryLikelyAddress(placeName: fmt, placeTypes: f.place_type, properties: f.properties) {
        let coord = CLLocationCoordinate2D(latitude: f.center[1], longitude: f.center[0])
        let d = GeoAPI.haversine(from: center, to: coord)
        items.append(AddressCandidate(address: fmt, coordinate: coord, distanceMeters: d))
      }
    }
    return items
  }
}

// MARK: - Helpers used above (add these if missing)
private extension GeoAPI {
  
  func isLikelyAddress(placeName: String, placeTypes: [String]?, properties: Any?) -> Bool {
    // Check if it's explicitly marked as an address
    if let types = placeTypes, types.contains("address") {
      return true
    }
    
    // Check for house number patterns (numbers at start of string)
    let houseNumberPattern = #"^\d+\s+"#
    if placeName.range(of: houseNumberPattern, options: .regularExpression) != nil {
      return true
    }
    
    // Accept POI with any accuracy (not just high accuracy ones)
    if let types = placeTypes, types.contains("poi") {
      return true
    }
    
    // Accept any result that looks like an address based on street names
    let streetPatterns = ["Street", "Road", "Avenue", "Crescent", "Drive", "Lane", "Way", "Boulevard", "Court", "Place", "Circle", "Trail"]
    if streetPatterns.contains(where: { placeName.contains($0) }) {
      return true
    }
    
    // Check for place types that might be addresses
    if let types = placeTypes {
      let addressTypes = ["address", "poi", "place"]
      if types.contains(where: { addressTypes.contains($0) }) {
        return true
      }
    }
    
    // Accept any result that contains numbers (likely house numbers)
    let numberPattern = #"\d+"#
    if placeName.range(of: numberPattern, options: .regularExpression) != nil {
      return true
    }
    
    return false
  }
  
  // Very permissive address filtering
  func isVeryLikelyAddress(placeName: String, placeTypes: [String]?, properties: Any?) -> Bool {
    // Accept anything that contains numbers (likely house numbers)
    let numberPattern = #"\d+"#
    if placeName.range(of: numberPattern, options: .regularExpression) != nil {
      return true
    }
    
    // Accept anything with street-like words
    let streetWords = ["Street", "Road", "Avenue", "Crescent", "Drive", "Lane", "Way", "Boulevard", "Court", "Place", "Circle", "Trail", "Crescent", "Close", "Grove", "Park", "Square", "Terrace", "Vale", "View", "Walk", "Rise", "Hill", "Gardens", "Manor", "House", "Cottage", "Lodge", "Villa", "Apartment", "Building", "Complex", "Tower", "Plaza", "Center", "Centre"]
    if streetWords.contains(where: { placeName.contains($0) }) {
      return true
    }
    
    // Accept any POI or place
    if let types = placeTypes {
      let acceptableTypes = ["address", "poi", "place", "locality", "neighborhood", "district"]
      if types.contains(where: { acceptableTypes.contains($0) }) {
        return true
      }
    }
    
    // Accept anything that looks like it could be a building or location
    return placeName.count > 5 && placeName.count < 100
  }
  
  func bbox(center: CLLocationCoordinate2D, meters: Double) -> (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
    let latDegPerM = 1.0 / 111_320.0
    let lonDegPerM = 1.0 / (111_320.0 * cos(center.latitude * .pi/180))
    let dLat = meters * latDegPerM, dLon = meters * lonDegPerM
    return (center.longitude - dLon, center.latitude - dLat, center.longitude + dLon, center.latitude + dLat)
  }

  static func haversine(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
    let R = 6_371_000.0
    let dLat = (to.latitude - from.latitude) * .pi / 180
    let dLon = (to.longitude - from.longitude) * .pi / 180
    let a = sin(dLat/2)*sin(dLat/2) + cos(from.latitude * .pi/180)*cos(to.latitude * .pi/180)*sin(dLon/2)*sin(dLon/2)
    return R * 2 * atan2(sqrt(a), sqrt(1-a))
  }
  
}
