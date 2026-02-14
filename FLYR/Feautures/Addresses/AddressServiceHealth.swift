import Foundation
import CoreLocation

/// Health check actor for address service. No DB probe (address lookups use Mapbox only).
actor AddressServiceHealth {
    static let shared = AddressServiceHealth()

    private(set) var dbHealthy = false
    private var lastProbeTime: Date?
    private let ttlMinutes: Double = 5.0

    private init() {}

    /// Check if we should probe (TTL check). No-op since there is no address DB.
    func shouldProbe() -> Bool {
        guard let lastProbe = lastProbeTime else { return true }
        return Date().timeIntervalSince(lastProbe) > (ttlMinutes * 60)
    }

    /// No-op: address service uses Mapbox only; no database to probe.
    func probe(lat: Double, lon: Double, ignoreTTL: Bool = false) async {
        lastProbeTime = Date()
        dbHealthy = false
    }

    /// Convenience: probes only if TTL expired. No-op.
    func checkHealth(lat: Double, lon: Double) async {
        if shouldProbe() {
            await probe(lat: lat, lon: lon)
        }
    }
}
