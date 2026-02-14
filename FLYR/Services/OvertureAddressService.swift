import Foundation
import CoreLocation

// MARK: - Overture Address Row (backend response)

/// Address row returned by the backend (Lambda + S3 / Overture).
struct OvertureAddressRow: Codable {
    let gersId: String?
    let geometryJson: String?
    let houseNumber: String?
    let streetName: String?
    let unit: String?
    let postalCode: String?
    let locality: String?
    let region: String?
    let country: String?
    let id: String?
    /// Optional lat/lon from nearest query (backend bbox + Haversine returns these).
    let lat: Double?
    let lon: Double?
    let distanceM: Double?
    /// Optional from nearest SQL shape (full_address, street_no, address_id).
    let fullAddress: String?
    let streetNo: String?
    let addressId: String?

    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case geometryJson = "geometry_json"
        case houseNumber = "house_number"
        case streetName = "street_name"
        case unit
        case postalCode = "postal_code"
        case locality
        case region
        case country
        case id
        case lat
        case lon
        case distanceM = "distance_m"
        case fullAddress = "full_address"
        case streetNo = "street_no"
        case addressId = "address_id"
    }

    /// Single coordinate for map pin (from lat/lon if present, else geometry_json Point).
    var coordinate: CLLocationCoordinate2D {
        if let lat = lat, let lon = lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard let json = geometryJson,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              let coords = obj["coordinates"] as? [Double],
              coords.count >= 2 else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        return CLLocationCoordinate2D(latitude: coords[1], longitude: coords[0])
    }

    /// Formatted address string (uses full_address from nearest SQL when present).
    var formatted: String {
        if let full = fullAddress, !full.isEmpty { return full }
        var parts: [String] = []
        let num = streetNo ?? houseNumber
        if let n = num, !n.isEmpty { parts.append(n) }
        if let s = streetName, !s.isEmpty { parts.append(s) }
        if let u = unit, !u.isEmpty { parts.append(u) }
        if let l = locality, !l.isEmpty { parts.append(l) }
        if let r = region, !r.isEmpty { parts.append(r) }
        if let p = postalCode, !p.isEmpty { parts.append(p) }
        if let c = country, !c.isEmpty { parts.append(c) }
        return parts.joined(separator: ", ")
    }

    /// House number for display (street_no from nearest SQL or house_number).
    var effectiveHouseNumber: String? { streetNo ?? houseNumber }

    /// Stable UUID for Identifiable / HomePoint.id (from backend id/address_id or deterministic from gers_id).
    var stableId: UUID {
        let idStr = id ?? addressId
        if let idStr = idStr, let uuid = UUID(uuidString: idStr) { return uuid }
        if let g = gersId, !g.isEmpty {
            let normalized = g.replacingOccurrences(of: "-", with: "").prefix(32)
            if normalized.count == 32, let uuid = UUID(uuidString: String(normalized)) { return uuid }
            var bytes = [UInt8](repeating: 0, count: 16)
            for (i, b) in g.utf8.prefix(16).enumerated() { bytes[i] = b }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
        return UUID()
    }
}

// MARK: - Generate Address List Response (backend contract)

/// Response from POST /api/campaigns/generate-address-list: inserted_count + preview (first 10, subset of fields).
/// Optional message (e.g. "No addresses found in polygon") is supported; unknown keys are ignored.
struct GenerateAddressListResponse: Codable {
    let insertedCount: Int
    let preview: [GenerateAddressListPreviewItem]
    let message: String?

    enum CodingKeys: String, CodingKey {
        case insertedCount = "inserted_count"
        case preview
        case message
    }
}

/// Preview item: id, formatted, postal_code, source, gers_id (no lat/lon in backend response).
struct GenerateAddressListPreviewItem: Codable {
    let id: String?
    let formatted: String?
    let postalCode: String?
    let source: String?
    let gersId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case formatted
        case postalCode = "postal_code"
        case source
        case gersId = "gers_id"
    }
}

// MARK: - Overture Address Service

/// Backend/API helper for address list generation (Lambda + S3). Frontend calls backend only.
final class OvertureAddressService {
    static let shared = OvertureAddressService()

    private init() {}

    /// Backend base URL (e.g. https://flyrpro.app).
    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    /// Whether base URL came from Info.plist (true) or default (false). For diagnostics.
    private var baseURLFromPlist: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String) != nil
    }

    /// Log backend connection diagnostics (no secrets). Call when a request is about to run or when it fails.
    private func logBackendDiagnostics(path: String, error: Error? = nil) {
        let connPath = "HTTP backend (FLYR_PRO_API_URL)"
        let url = "\(baseURL)\(path)"
        print("🔍 [ADDRESS BACKEND] connector=\(connPath) base_url=\(baseURL) url=\(url) from_plist=\(baseURLFromPlist)")
        if let e = error {
            print("❌ [ADDRESS BACKEND] request_failed error=\(e.localizedDescription)")
            let desc = e.localizedDescription.lowercased()
            if desc.contains("hostname") || desc.contains("could not be found") || desc.contains("cannot find") {
                print("💡 [ADDRESS BACKEND] Hostname/DNS failure: check FLYR_PRO_API_URL in Info.plist / xcconfig (e.g. flyrpro.app).")
            }
        }
    }

    /// Fetch addresses inside a polygon via backend POST /api/campaigns/generate-address-list (polygon mode).
    /// Backend requires campaign_id + polygon. Returns preview only (first 10); full list is inserted into DB.
    func getAddressesInPolygon(polygonGeoJSON: String, campaignId: UUID) async throws -> [AddressCandidate] {
        guard let data = polygonGeoJSON.data(using: .utf8),
              let polygonObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OvertureAddressError.invalidPolygon
        }
        let body: [String: Any] = [
            "campaign_id": campaignId.uuidString,
            "polygon": polygonObj
        ]
        return try await postDecodeGenerateAddressList(path: "/api/campaigns/generate-address-list", body: body)
    }

    /// Fetch nearest addresses via backend POST /api/campaigns/generate-address-list (closest-home: campaign_id + starting_address + coordinates + count).
    /// When campaignId is nil, callers should use Mapbox. Backend returns preview only (first 10).
    func getAddressesNearest(center: CLLocationCoordinate2D, limit: Int, campaignId: UUID?, startingAddress: String? = nil) async throws -> [AddressCandidate] {
        guard let campaignId = campaignId else {
            throw NSError(domain: "OvertureAddressService", code: 0, userInfo: [NSLocalizedDescriptionKey: "campaign_id required for generate-address-list; use Mapbox when no campaign"])
        }
        let startLabel = startingAddress?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? startingAddress!
            : "\(center.latitude), \(center.longitude)"
        let body: [String: Any] = [
            "campaign_id": campaignId.uuidString,
            "starting_address": startLabel,
            "coordinates": ["lat": center.latitude, "lng": center.longitude],
            "count": limit
        ]
        return try await postDecodeGenerateAddressList(path: "/api/campaigns/generate-address-list", body: body)
    }

    /// POST to generate-address-list and decode wrapped response { inserted_count, preview }; map preview to [AddressCandidate].
    private func postDecodeGenerateAddressList(path: String, body: [String: Any]) async throws -> [AddressCandidate] {
        logBackendDiagnostics(path: path)

        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OvertureAddressError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let bodyStr = String(data: responseData, encoding: .utf8) ?? ""
                let userMessage = Self.extractMessageFromErrorBody(responseData)
                let err = OvertureAddressError.httpError(status: http.statusCode, body: userMessage ?? bodyStr)
                logBackendDiagnostics(path: path, error: err)
                throw err
            }
            let decoder = JSONDecoder()
            let genResponse = try decoder.decode(GenerateAddressListResponse.self, from: responseData)
            return Self.previewToAddressCandidates(genResponse.preview, sourceLabel: "overture")
        } catch {
            logBackendDiagnostics(path: path, error: error)
            throw error
        }
    }

    /// Try to extract a "message" (or "error") field from error response JSON for user-facing error.
    private static func extractMessageFromErrorBody(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let msg = json["message"] as? String, !msg.isEmpty { return msg }
        if let msg = json["error"] as? String, !msg.isEmpty { return msg }
        return nil
    }

    /// Map backend preview (id, formatted, postal_code, source, gers_id; no lat/lon) to AddressCandidate.
    static func previewToAddressCandidates(_ preview: [GenerateAddressListPreviewItem], sourceLabel: String = "overture") -> [AddressCandidate] {
        preview.map { item in
            let id = (item.id.flatMap { UUID(uuidString: $0) }) ?? UUID()
            let address = item.formatted ?? ""
            return AddressCandidate(
                id: id,
                address: address,
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                distanceMeters: 0,
                number: "",
                street: "",
                houseKey: address.uppercased(),
                source: item.source ?? sourceLabel
            )
        }
    }

    /// Fetch addresses on same street (via backend).
    func getAddressesSameStreet(seed: CLLocationCoordinate2D, street: String, locality: String?, limit: Int) async throws -> [OvertureAddressRow] {
        var body: [String: Any] = [
            "lat": seed.latitude,
            "lon": seed.longitude,
            "street": street,
            "limit": limit
        ]
        if let locality = locality, !locality.isEmpty {
            body["locality"] = locality
        }
        return try await postDecode(path: "/api/addresses-same-street", body: body)
    }

    private func postDecode(path: String, body: [String: Any]) async throws -> [OvertureAddressRow] {
        logBackendDiagnostics(path: path)

        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OvertureAddressError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                let bodyStr = String(data: responseData, encoding: .utf8) ?? ""
                let userMessage = Self.extractMessageFromErrorBody(responseData)
                let err = OvertureAddressError.httpError(status: http.statusCode, body: userMessage ?? bodyStr)
                logBackendDiagnostics(path: path, error: err)
                throw err
            }
            let decoder = JSONDecoder()
            return try decoder.decode([OvertureAddressRow].self, from: responseData)
        } catch {
            logBackendDiagnostics(path: path, error: error)
            throw error
        }
    }

    /// Map Overture rows to AddressCandidate (for AddressService). Uses distance_m when present, else computes from reference.
    static func mapToAddressCandidates(_ rows: [OvertureAddressRow], reference: CLLocationCoordinate2D, sourceLabel: String = "overture") -> [AddressCandidate] {
        let refLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)
        return rows.map { row in
            let coord = row.coordinate
            let distanceM = row.distanceM ?? refLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            let streetUp = (row.streetName ?? "").uppercased()
            let num = row.effectiveHouseNumber ?? ""
            let houseKey = "\(num) \(streetUp)".trimmingCharacters(in: .whitespaces).uppercased()
            return AddressCandidate(
                id: row.stableId,
                address: row.formatted,
                coordinate: coord,
                distanceMeters: distanceM,
                number: num,
                street: streetUp,
                houseKey: houseKey.isEmpty ? row.formatted.uppercased() : houseKey,
                source: sourceLabel
            )
        }
    }

    /// Map Overture address rows to HomePoint for UseCampaignMap.
    static func mapToHomePoints(_ rows: [OvertureAddressRow]) -> [UseCampaignMap.HomePoint] {
        rows.map { row in
            UseCampaignMap.HomePoint(
                id: row.stableId,
                address: row.formatted,
                coord: row.coordinate,
                number: row.effectiveHouseNumber
            )
        }
    }
}

enum OvertureAddressError: LocalizedError {
    case invalidPolygon
    case invalidResponse
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidPolygon: return "Invalid GeoJSON polygon"
        case .invalidResponse: return "Invalid response from server"
        case .httpError(let status, let body): return "HTTP \(status): \(body.prefix(200))"
        }
    }
}
