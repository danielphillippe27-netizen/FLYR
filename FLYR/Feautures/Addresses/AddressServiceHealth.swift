import Foundation
import CoreLocation

/// Health check actor for address service - tracks DB health with TTL
actor AddressServiceHealth {
    static let shared = AddressServiceHealth()
    
    private(set) var dbHealthy = true
    private var lastProbeTime: Date?
    private let ttlMinutes: Double = 5.0
    private let maxResponseTimeSeconds: Double = 1.5
    
    private init() {}
    
    /// Check if we should probe the database (TTL check)
    func shouldProbe() -> Bool {
        guard let lastProbe = lastProbeTime else { return true }
        return Date().timeIntervalSince(lastProbe) > (ttlMinutes * 60)
    }
    
    /// Probe database health with a quick test call
    func probe(lat: Double, lon: Double, ignoreTTL: Bool = false) async {
        if !ignoreTTL, let lastProbe = lastProbeTime, Date().timeIntervalSince(lastProbe) < (ttlMinutes * 60) {
            print("🏥 [HEALTH] Using cached health status: \(dbHealthy ? "healthy" : "unhealthy")")
            return
        }
        
        print("🏥 [HEALTH] Probing database health at \(lat), \(lon)")
        
        let startTime = Date()
        
        do {
            // Quick test call to fn_addr_nearest_v2 with minimal limit
            let supabase = await SupabaseClientShim()
            let _: [ODAHealthTestRow] = try await supabase.callRPC("fn_addr_nearest_v2", params: [
                "p_lon": lon,
                "p_lat": lat,
                "p_limit": 1,
                "p_province": "ON"
            ])
            
            let responseTime = Date().timeIntervalSince(startTime)
            dbHealthy = responseTime <= maxResponseTimeSeconds
            lastProbeTime = Date()
            
            if dbHealthy {
                print("✅ [HEALTH] Database healthy (response time: \(String(format: "%.3f", responseTime))s)")
            } else {
                print("⚠️ [HEALTH] Database slow (response time: \(String(format: "%.3f", responseTime))s), marking unhealthy")
            }
        } catch {
            dbHealthy = false
            lastProbeTime = Date()
            print("❌ [HEALTH] Database probe failed: \(error.localizedDescription)")
        }
    }
    
    /// Convenience method that probes only if TTL has expired
    func checkHealth(lat: Double, lon: Double) async {
        if shouldProbe() {
            await probe(lat: lat, lon: lon)
        } else {
            print("🏥 [HEALTH] Using cached health status: \(dbHealthy ? "healthy" : "unhealthy")")
        }
    }
}

// MARK: - Health Test Row

/// Minimal row structure for health check probe
private struct ODAHealthTestRow: Decodable {
    let addressId: String
    let fullAddress: String
    let streetNo: String
    let streetName: String
    let city: String
    let province: String
    let postalCode: String?
    let distanceM: Double
    let lat: Double
    let lon: Double
    
    enum CodingKeys: String, CodingKey {
        case addressId = "address_id"
        case fullAddress = "full_address"
        case streetNo = "street_no"
        case streetName = "street_name"
        case city, province
        case postalCode = "postal_code"
        case distanceM = "distance_m"
        case lat, lon
    }
}
