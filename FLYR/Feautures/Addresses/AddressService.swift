import Foundation
import CoreLocation
import Combine

// MARK: - Address Service

/// Pro-mode address service: ODA first, Mapbox fallback
@MainActor
final class AddressService: ObservableObject {
    static let shared = AddressService(oda: ODAProvider(), mapbox: MapboxProvider())
    
    private let oda: AddressProvider
    private let mapbox: AddressProvider
    private let geoAdapter = GeoStreetAdapter()
    
    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [AddressCandidate] = []
    @Published var source: AddressSource = .oda // Track which source was used
    
    enum AddressSource {
        case oda
        case mapbox
        case hybrid
    }
    
    init(oda: AddressProvider, mapbox: AddressProvider) {
        self.oda = oda
        self.mapbox = mapbox
    }
    
    /// Find nearest addresses: DB first with instant fallback
    func fetchNearest(center: CLLocationCoordinate2D, target: Int) async throws -> [AddressCandidate] {
        print("🔍 [ADDRESS SERVICE] Finding \(target) nearest addresses to \(center)")
        
        isLoading = true
        error = nil
        results = []
        source = .oda
        
        defer { isLoading = false }
        
        var seen = Set<String>()
        var out: [AddressCandidate] = []
        
        // Always attempt DB first with short timeout
        do {
            let startTime = Date()
            let odaResults = try await oda.tryDBOnce(center: center, limit: target * 2)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            
            // Update health to healthy after successful DB call
            await AddressServiceHealth.shared.probe(lat: center.latitude, lon: center.longitude, ignoreTTL: true)
            
            print("✅ [DB] ODA/Durham returned \(odaResults.count) addresses in \(latency)ms")
            
            for candidate in odaResults {
                if seen.insert(candidate.houseKey).inserted {
                    out.append(candidate)
                    if out.count >= target {
                        print("✅ [DB] ODA/Durham provided enough addresses (\(out.count))")
                        results = out
                        source = .oda
                        return out
                    }
                }
            }
        } catch {
            // Update health to unhealthy after failed DB call
            await AddressServiceHealth.shared.probe(lat: center.latitude, lon: center.longitude, ignoreTTL: true)
            print("⚠️ [DB] ODA/Durham failed: \(error.localizedDescription)")
        }
        
        // Phase 2: Fill gaps with Mapbox
        if out.count < target {
            print("🗺️ [FALLBACK] Using Mapbox API (confidence: 0.70)")
            print("🗺️ [FALLBACK] Filling gaps with Mapbox (need \(target - out.count) more)")
            source = out.isEmpty ? .mapbox : .hybrid
            
            do {
                let mapboxResults = try await mapbox.nearest(center: center, limit: max(target, target * 2))
                print("🗺️ [ADDRESS SERVICE] Mapbox returned \(mapboxResults.count) addresses")
                
                for candidate in mapboxResults {
                    if seen.insert(candidate.houseKey).inserted {
                        out.append(candidate)
                        if out.count >= target {
                            break
                        }
                    }
                }
            } catch {
                print("⚠️ [ADDRESS SERVICE] Mapbox failed: \(error.localizedDescription)")
                self.error = "Address search failed: \(error.localizedDescription)"
                throw error
            }
        }
        
        // Determine final source for logging
        let finalSource: String
        if out.isEmpty {
            finalSource = "none"
        } else if out.allSatisfy({ $0.source == "oda" }) {
            finalSource = "oda"
        } else if out.allSatisfy({ $0.source == "mapbox" }) {
            finalSource = "mapbox"
        } else {
            finalSource = "hybrid"
        }
        
        print("✅ [ADDRESS SERVICE] Final result: \(out.count) addresses (source: \(finalSource))")
        results = out
        return out
    }
    
    /// Find addresses on same street with automatic street detection: ODA first, Mapbox fallback
    func fetchSameStreet(seed: CLLocationCoordinate2D, target: Int) async throws -> [AddressCandidate] {
        print("🔍 [ADDRESS SERVICE] Finding \(target) addresses on same street (auto-detect) for \(seed)")
        
        // Use GeoStreetAdapter to get street and locality
        let (street, locality) = try await geoAdapter.reverseSeedStreet(at: seed)
        print("🔍 [ADDRESS SERVICE] Detected street: '\(street)', locality: '\(locality ?? "none")'")
        
        return try await fetchSameStreet(seed: seed, street: street, locality: locality, target: target)
    }
    
    /// Find addresses on same street: DB first with instant fallback
    func fetchSameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, target: Int) async throws -> [AddressCandidate] {
        print("🔍 [ADDRESS SERVICE] Finding \(target) addresses on street '\(street)' in locality '\(locality ?? "any")'")
        
        isLoading = true
        error = nil
        results = []
        source = .oda
        
        defer { isLoading = false }
        
        var seen = Set<String>()
        var out: [AddressCandidate] = []
        
        // Always attempt DB first with short timeout
        do {
            let startTime = Date()
            let odaResults = try await oda.sameStreet(seed: seed, street: street, locality: locality, limit: target * 3)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            
            // Update health to healthy after successful DB call
            await AddressServiceHealth.shared.probe(lat: seed.latitude, lon: seed.longitude, ignoreTTL: true)
            
            print("✅ [DB] ODA/Durham returned \(odaResults.count) addresses on street in \(latency)ms")
            
            for candidate in odaResults {
                if seen.insert(candidate.houseKey).inserted {
                    out.append(candidate)
                    if out.count >= target {
                        print("✅ [DB] ODA/Durham provided enough addresses on street (\(out.count))")
                        results = out
                        source = .oda
                        return out
                    }
                }
            }
        } catch {
            // Update health to unhealthy after failed DB call
            await AddressServiceHealth.shared.probe(lat: seed.latitude, lon: seed.longitude, ignoreTTL: true)
            print("⚠️ [DB] ODA/Durham street search failed: \(error.localizedDescription)")
        }
        
        // Phase 2: Fill gaps with Mapbox
        if out.count < target {
            print("🗺️ [FALLBACK] Using Mapbox API for street search (confidence: 0.70)")
            print("🗺️ [FALLBACK] Filling street gaps with Mapbox (need \(target - out.count) more)")
            source = out.isEmpty ? .mapbox : .hybrid
            
            do {
                let mapboxResults = try await mapbox.sameStreet(seed: seed, street: street, locality: locality, limit: max(target, target * 2))
                print("🗺️ [ADDRESS SERVICE] Mapbox returned \(mapboxResults.count) addresses on street")
                
                for candidate in mapboxResults {
                    if seen.insert(candidate.houseKey).inserted {
                        out.append(candidate)
                        if out.count >= target {
                            break
                        }
                    }
                }
            } catch {
                print("⚠️ [ADDRESS SERVICE] Mapbox street search failed: \(error.localizedDescription)")
                self.error = "Street address search failed: \(error.localizedDescription)"
                throw error
            }
        }
        
        print("✅ [ADDRESS SERVICE] Final street result: \(out.count) addresses (source: \(source))")
        results = out
        return out
    }
    
    /// Clear results and reset state
    func clear() {
        results = []
        error = nil
        isLoading = false
        source = .oda
    }
}
