import Foundation
import CoreLocation
import Combine

// MARK: - Address Service

/// Address service: backend (Lambda/S3) primary, Mapbox fallback.
@MainActor
final class AddressService: ObservableObject {
    static let shared = AddressService(overture: OvertureAddressProvider(), mapbox: MapboxProvider())

    private let overture: AddressProvider
    private let mapbox: AddressProvider
    private let geoAdapter = GeoStreetAdapter()

    @Published var isLoading = false
    @Published var error: String?
    @Published var results: [AddressCandidate] = []
    @Published var source: AddressSource = .overture

    enum AddressSource {
        case overture  // Backend Lambda/S3 (generate-address-list)
        case mapbox
        case hybrid
    }

    init(overture: AddressProvider, mapbox: AddressProvider) {
        self.overture = overture
        self.mapbox = mapbox
    }

    /// Find nearest addresses: backend (generate-address-list) first when campaignId present, else Mapbox fallback
    func fetchNearest(center: CLLocationCoordinate2D, target: Int, campaignId: UUID? = nil) async throws -> [AddressCandidate] {
        print("🔍 [ADDRESS SERVICE] Finding \(target) nearest addresses to \(center) (strategy: backend when campaignId set, else Mapbox fallback)")

        isLoading = true
        error = nil
        results = []
        source = .overture

        defer { isLoading = false }

        var seen = Set<String>()
        var out: [AddressCandidate] = []

        do {
            print("🔍 [ADDRESS SERVICE] Trying address backend...")
            let startTime = Date()
            let overtureResults = try await overture.tryDBOnce(center: center, limit: target * 2, timeoutMs: 1200, campaignId: campaignId)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            print("✅ [ADDRESS SERVICE] Backend returned \(overtureResults.count) addresses in \(latency)ms")

            for candidate in overtureResults {
                if seen.insert(candidate.houseKey).inserted {
                    out.append(candidate)
                    if out.count >= target {
                        results = out
                        source = .overture
                        print("✅ [ADDRESS SERVICE] Final result: \(out.count) addresses (source: overture)")
                        return out
                    }
                }
            }
        } catch {
            print("⚠️ [ADDRESS SERVICE] Address backend failed: \(error.localizedDescription)")
        }

        if out.count < target {
            print("🗺️ [FALLBACK] Using Mapbox (need \(target - out.count) more)")
            source = out.isEmpty ? .mapbox : .hybrid
            do {
                let mapboxResults = try await mapbox.nearest(center: center, limit: max(target, target * 2), campaignId: nil)
                for candidate in mapboxResults {
                    if seen.insert(candidate.houseKey).inserted {
                        out.append(candidate)
                        if out.count >= target { break }
                    }
                }
            } catch {
                print("⚠️ [ADDRESS SERVICE] Mapbox failed: \(error.localizedDescription)")
                self.error = "Address search failed: \(error.localizedDescription)"
                throw error
            }
        }

        let finalSource: String = out.isEmpty ? "none" : (out.allSatisfy { $0.source == "overture" } ? "overture" : (out.allSatisfy { $0.source == "mapbox" } ? "mapbox" : "hybrid"))
        print("✅ [ADDRESS SERVICE] Final result: \(out.count) addresses (source: \(finalSource))")
        results = out
        return out
    }

    /// Find addresses on same street with automatic street detection
    func fetchSameStreet(seed: CLLocationCoordinate2D, target: Int) async throws -> [AddressCandidate] {
        print("🔍 [ADDRESS SERVICE] Finding \(target) addresses on same street (auto-detect) for \(seed)")

        let (street, locality) = try await geoAdapter.reverseSeedStreet(at: seed)
        print("🔍 [ADDRESS SERVICE] Detected street: '\(street)', locality: '\(locality ?? "none")'")

        return try await fetchSameStreet(seed: seed, street: street, locality: locality, target: target)
    }

    /// Find addresses on same street: backend first, Mapbox fallback
    func fetchSameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, target: Int) async throws -> [AddressCandidate] {
        print("🔍 [ADDRESS SERVICE] Finding \(target) addresses on street '\(street)' in locality '\(locality ?? "any")'")

        isLoading = true
        error = nil
        results = []
        source = .overture

        defer { isLoading = false }

        var seen = Set<String>()
        var out: [AddressCandidate] = []

        do {
            let startTime = Date()
            let overtureResults = try await overture.sameStreet(seed: seed, street: street, locality: locality, limit: target * 3)
            let latency = Int(Date().timeIntervalSince(startTime) * 1000)
            print("✅ [ADDRESS SERVICE] Backend returned \(overtureResults.count) on street in \(latency)ms")

            for candidate in overtureResults {
                if seen.insert(candidate.houseKey).inserted {
                    out.append(candidate)
                    if out.count >= target {
                        results = out
                        source = .overture
                        print("✅ [ADDRESS SERVICE] Final street result: \(out.count) addresses (source: overture)")
                        return out
                    }
                }
            }
        } catch {
            print("⚠️ [ADDRESS SERVICE] Backend street search failed: \(error.localizedDescription)")
        }

        if out.count < target {
            print("🗺️ [FALLBACK] Using Mapbox for street (need \(target - out.count) more)")
            source = out.isEmpty ? .mapbox : .hybrid
            do {
                let mapboxResults = try await mapbox.sameStreet(seed: seed, street: street, locality: locality, limit: max(target, target * 2))
                for candidate in mapboxResults {
                    if seen.insert(candidate.houseKey).inserted {
                        out.append(candidate)
                        if out.count >= target { break }
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
        source = .overture
    }
}
