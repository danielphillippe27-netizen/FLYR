import Foundation
import CoreLocation

extension GeoAPI {
    
    /// Reverse geocode to get street name + locality (for caching)
    func reverseStreet(_ coordinate: CLLocationCoordinate2D) async throws -> (street: String, locality: String?) {
        let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        guard !token.isEmpty else { 
            print("❌ [GEOAPI DEBUG] Missing Mapbox token")
            throw GeoAPIError.missingToken 
        }
        // Mapbox: use limit=1 for reverse (single result); limit>1 requires exactly one types parameter
        let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(coordinate.longitude),\(coordinate.latitude).json?types=address&limit=1&access_token=\(token)"
        print("🔍 [GEOAPI DEBUG] Reverse geocoding URL (first): \(urlStr.replacingOccurrences(of: token, with: "TOKEN_HIDDEN"))")
        
        guard let url = URL(string: urlStr) else { 
            print("❌ [GEOAPI DEBUG] Invalid reverse geocoding URL: \(urlStr.replacingOccurrences(of: token, with: "TOKEN_HIDDEN"))")
            throw GeoAPIError.badURL 
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("🔍 [GEOAPI DEBUG] Reverse geocoding response status (first): \(statusCode)")
        guard statusCode == 200 else { 
            print("❌ [GEOAPI DEBUG] Reverse geocoding failed with status: \(statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [GEOAPI DEBUG] Reverse geocoding error response: \(responseString)")
            }
            throw GeoAPIError.requestFailed 
        }
        
        struct Resp: Decodable {
            struct Feature: Decodable {
                let text: String
                let place_type: [String]
                let context: [Context]?
                
                struct Context: Decodable {
                    let text: String
                    let id: String
                }
            }
            let features: [Feature]
        }
        
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        let feat = decoded.features.first { $0.place_type.contains("address") }
            ?? decoded.features.first
        guard let f = feat else { throw GeoAPIError.noResults }
        
        let locality = f.context?.first { $0.id.contains("place") }?.text
        return (street: f.text, locality: locality)
    }

    func reverseStreet(at coordinate: CLLocationCoordinate2D) async throws -> (name: String, center: CLLocationCoordinate2D) {
        let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        guard !token.isEmpty else { throw GeoAPIError.missingToken }
        let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(coordinate.longitude),\(coordinate.latitude).json?types=address&limit=1&access_token=\(token)"
        print("🔍 [GEOAPI DEBUG] Reverse geocoding URL: \(urlStr)")
        guard let url = URL(string: urlStr) else { 
            print("❌ [GEOAPI DEBUG] Invalid reverse geocoding URL: \(urlStr)")
            throw GeoAPIError.badURL 
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("🔍 [GEOAPI DEBUG] Reverse geocoding response status: \(statusCode)")
        guard statusCode == 200 else { 
            print("❌ [GEOAPI DEBUG] Reverse geocoding failed with status: \(statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [GEOAPI DEBUG] Reverse geocoding response: \(responseString)")
            }
            throw GeoAPIError.requestFailed 
        }

        struct Resp: Decodable {
            struct Feature: Decodable { let text: String; let place_type: [String]; let center: [Double] }
            let features: [Feature]
        }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        let feat = decoded.features.first { $0.place_type.contains("address") }
                ?? decoded.features.first { $0.place_type.contains("street") }
        guard let f = feat, f.center.count == 2 else { throw GeoAPIError.noResults }
        return (name: f.text, center: CLLocationCoordinate2D(latitude: f.center[1], longitude: f.center[0]))
    }

    private func bbox(center: CLLocationCoordinate2D, meters: Double) -> (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        let latDegPerM = 1.0 / 111_320.0
        let lonDegPerM = 1.0 / (111_320.0 * cos(center.latitude * .pi/180))
        let dLat = meters * latDegPerM, dLon = meters * lonDegPerM
        return (center.longitude - dLon, center.latitude - dLat, center.longitude + dLon, center.latitude + dLat)
    }

    /// Returns array of { formatted, lon, lat } JSON-ready dictionaries (deduped)
    func addressesOnStreetJSON(streetName: String, center: CLLocationCoordinate2D, radiusMeters: Double = 800, limit: Int = 1000) async throws -> [[String: Any]] {
        let token = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String ?? ""
        guard !token.isEmpty else { 
            print("❌ [GEOAPI DEBUG] Missing Mapbox token for street search")
            throw GeoAPIError.missingToken 
        }
        let bb = bbox(center: center, meters: radiusMeters)
        let q = streetName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? streetName
        let urlStr = "https://api.mapbox.com/geocoding/v5/mapbox.places/\(q).json?types=address&bbox=\(bb.minLon),\(bb.minLat),\(bb.maxLon),\(bb.maxLat)&limit=\(min(max(limit,1),1000))&access_token=\(token)"
        print("🔍 [GEOAPI DEBUG] Street search URL: \(urlStr.replacingOccurrences(of: token, with: "TOKEN_HIDDEN"))")
        guard let url = URL(string: urlStr) else { 
            print("❌ [GEOAPI DEBUG] Invalid street search URL: \(urlStr.replacingOccurrences(of: token, with: "TOKEN_HIDDEN"))")
            throw GeoAPIError.badURL 
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
        print("🔍 [GEOAPI DEBUG] Street search response status: \(statusCode)")
        guard statusCode == 200 else { 
            print("❌ [GEOAPI DEBUG] Street search failed with status: \(statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ [GEOAPI DEBUG] Street search error response: \(responseString)")
            }
            throw GeoAPIError.requestFailed 
        }

        struct Resp: Decodable { struct Feature: Decodable { let place_name: String; let center: [Double] }; let features: [Feature] }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)

        var seen = Set<String>(); var out: [[String: Any]] = []
        for f in decoded.features where f.center.count == 2 {
            let fmt = f.place_name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = fmt.uppercased()
            if seen.insert(key).inserted {
                out.append(["formatted": fmt, "lon": f.center[0], "lat": f.center[1]])
            }
        }
        return out
    }
}
