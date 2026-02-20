import Foundation
import Supabase

// MARK: - Building detail response (GET /api/buildings/{gersId}?campaign_id=...)

/// Response from GET /api/buildings/{gersId}. Scan data (scans, last_scanned_at) is gated by backend for non‑Pro users (returned as 0 / null).
struct BuildingDetailResponse: Codable {
    let gersId: String
    let addressId: UUID?
    let campaignId: UUID?
    let campaignName: String?
    let address: String?
    let postalCode: String?
    let status: String?
    let visited: Bool?
    let scans: Int
    let lastScannedAt: Date?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case gersId = "gers_id"
        case addressId = "address_id"
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case address
        case postalCode = "postal_code"
        case status
        case visited
        case scans
        case lastScannedAt = "last_scanned_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gersId = try c.decode(String.self, forKey: .gersId)
        addressId = try c.decodeIfPresent(UUID.self, forKey: .addressId)
        campaignId = try c.decodeIfPresent(UUID.self, forKey: .campaignId)
        campaignName = try c.decodeIfPresent(String.self, forKey: .campaignName)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        visited = try c.decodeIfPresent(Bool.self, forKey: .visited)
        scans = try c.decodeIfPresent(Int.self, forKey: .scans) ?? 0
        lastScannedAt = try c.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

// MARK: - Building Details API

/// Fetches building details including scan data from GET /api/buildings/{gersId}.
/// Backend returns scans/last_scanned_at only for paying users (Pro/Team); otherwise 0 and null.
@MainActor
final class BuildingDetailsAPI {
    static let shared = BuildingDetailsAPI()

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    /// Fetch building details for a given GERS ID and optional campaign.
    /// When user is not Pro, API returns same shape with scans: 0 and last_scanned_at: null.
    func fetchBuildingDetails(gersId: String, campaignId: UUID) async throws -> BuildingDetailResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        var components = URLComponents(string: "\(baseURL)/api/buildings/\(gersId)")
        components?.queryItems = [URLQueryItem(name: "campaign_id", value: campaignId.uuidString)]
        guard let url = components?.url else {
            throw BuildingDetailsError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BuildingDetailsError.network
        }
        guard (200...299).contains(http.statusCode) else {
            throw BuildingDetailsError.server(http.statusCode)
        }
        return try decoder.decode(BuildingDetailResponse.self, from: data)
    }
}

enum BuildingDetailsError: LocalizedError {
    case invalidURL
    case network
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .network: return "Network error"
        case .server(let code): return "Server error (\(code))"
        }
    }
}
