import Foundation
import CoreLocation
import Combine

// MARK: - Use Nearest Addresses Hook

@MainActor
final class UseNearestAddresses: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [AddressCandidate] = []
    @Published var seedCenter: CLLocationCoordinate2D?
    @Published var cacheHit = false
    @Published var street: String?
    @Published var locality: String?
    
    private let geoAPI = GeoAPI.shared
    private let supabase = SupabaseClientShim()
    
    /// Find the nearest addresses to a seed location
    func run(seedQuery: String, limit: Int = 25, usePreciseMode: Bool = false) async {
        print("🔍 [ADDRESS DEBUG] Starting address search (precise: \(usePreciseMode))")
        print("🔍 [ADDRESS DEBUG] Seed query: '\(seedQuery)'")
        print("🔍 [ADDRESS DEBUG] Limit: \(limit)")
        
        isLoading = true
        error = nil
        results = []
        cacheHit = false
        
        defer { 
            isLoading = false
            print("🔍 [ADDRESS DEBUG] Search completed. Found \(results.count) addresses")
        }
        
        do {
            // Step 1: Forward geocode the seed address
            print("🔍 [ADDRESS DEBUG] Step 1: Forward geocoding seed address...")
            let seed = try await geoAPI.forwardGeocodeSeed(seedQuery)
            self.seedCenter = seed.coordinate
            print("🔍 [ADDRESS DEBUG] Seed geocoded successfully: \(seed.coordinate)")
            
            // Step 2: Get street info for caching
            if let streetInfo = try? await geoAPI.reverseStreet(seed.coordinate) {
                self.street = streetInfo.street
                self.locality = streetInfo.locality
                print("🔍 [ADDRESS DEBUG] Street: \(streetInfo.street), Locality: \(streetInfo.locality ?? "nil")")
                
                // Step 3: Check cache first
                if let cachedAddresses = try? await supabase.getCachedAddresses(street: streetInfo.street, locality: streetInfo.locality),
                   !cachedAddresses.isEmpty {
                    print("✅ [ADDRESS DEBUG] Cache hit! Found \(cachedAddresses.count) cached addresses")
                    results = cachedAddresses
                    cacheHit = true
                    return
                }
            }
            
            // Step 4: Cache miss - Find nearby addresses using API
            print("🔍 [ADDRESS DEBUG] Cache miss - querying Mapbox API...")
            let nearby = usePreciseMode
                ? try await geoAPI.nearbyAddressesPrecise(around: seed.coordinate, limit: limit)
                : try await geoAPI.nearbyAddresses(around: seed.coordinate, limit: limit)
            print("🔍 [ADDRESS DEBUG] Found \(nearby.count) nearby addresses")
            
            // Log first few addresses for debugging
            for (index, address) in nearby.prefix(3).enumerated() {
                print("🔍 [ADDRESS DEBUG] Address \(index + 1): '\(address.address)' at \(address.coordinate)")
            }
            
            results = nearby
            
            // Step 5: Cache the results
            if let street = self.street, !nearby.isEmpty {
                let source = usePreciseMode ? "polyline_walker" : "street_locked"
                try? await supabase.cacheAddresses(nearby, street: street, locality: self.locality, source: source)
                print("✅ [ADDRESS DEBUG] Cached \(nearby.count) addresses")
            }
            
            print("✅ [ADDRESS DEBUG] Address search completed successfully")
        } catch {
            print("❌ [ADDRESS DEBUG] Address search failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    /// Find nearby addresses using a known center coordinate (from autocomplete selection)
    func runWithKnownCenter(center: CLLocationCoordinate2D, limit: Int, usePreciseMode: Bool = false) async {
        print("🔍 [ADDRESS DEBUG] Starting address search with known center (precise: \(usePreciseMode))")
        print("🔍 [ADDRESS DEBUG] Center: \(center)")
        print("🔍 [ADDRESS DEBUG] Limit: \(limit)")
        
        isLoading = true
        error = nil
        results = []
        cacheHit = false
        
        defer { 
            isLoading = false
            print("🔍 [ADDRESS DEBUG] Search completed. Found \(results.count) addresses")
        }
        
        do {
            // Test token first
            try await geoAPI.testToken()
            
            self.seedCenter = center
            
            // Step 1: Get street info for caching
            if let streetInfo = try? await geoAPI.reverseStreet(center) {
                self.street = streetInfo.street
                self.locality = streetInfo.locality
                print("🔍 [ADDRESS DEBUG] Street: \(streetInfo.street), Locality: \(streetInfo.locality ?? "nil")")
                
                // Step 2: Check cache first
                if let cachedAddresses = try? await supabase.getCachedAddresses(street: streetInfo.street, locality: streetInfo.locality),
                   !cachedAddresses.isEmpty {
                    print("✅ [ADDRESS DEBUG] Cache hit! Found \(cachedAddresses.count) cached addresses")
                    results = cachedAddresses
                    cacheHit = true
                    return
                }
            }
            
            // Step 3: Cache miss - Find nearby addresses using API
            print("🔍 [ADDRESS DEBUG] Cache miss - querying Mapbox API...")
            let nearby = usePreciseMode
                ? try await geoAPI.nearbyAddressesPrecise(around: center, limit: limit)
                : try await geoAPI.nearbyAddresses(around: center, limit: limit)
            print("🔍 [ADDRESS DEBUG] Found \(nearby.count) nearby addresses")
            
            // Log first few addresses for debugging
            for (index, address) in nearby.prefix(3).enumerated() {
                print("🔍 [ADDRESS DEBUG] Address \(index + 1): '\(address.address)' at \(address.coordinate)")
            }
            
            results = nearby
            
            // Step 4: Cache the results
            if let street = self.street, !nearby.isEmpty {
                let source = usePreciseMode ? "polyline_walker" : "street_locked"
                try? await supabase.cacheAddresses(nearby, street: street, locality: self.locality, source: source)
                print("✅ [ADDRESS DEBUG] Cached \(nearby.count) addresses")
            }
            
            print("✅ [ADDRESS DEBUG] Address search completed successfully")
        } catch {
            print("❌ [ADDRESS DEBUG] Address search failed: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    /// Clear results and reset state
    func clear() {
        results = []
        error = nil
        isLoading = false
        seedCenter = nil
    }
}