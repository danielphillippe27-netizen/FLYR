import Foundation
import Observation
import Supabase

/// Response from GET /api/daily-content. We use only quote (text, author, optional category).
struct DailyContentResponse: Decodable {
    let success: Bool
    let quote: DailyQuote
    let cachedAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case quote
        case cachedAt = "cached_at"
        case expiresAt = "expires_at"
    }
}

struct DailyQuote: Decodable {
    let text: String
    let author: String
    let category: String?
}

/// Fetches quote of the day from GET /api/daily-content. Uses same base URL and auth as other API calls.
@Observable
@MainActor
final class DailyContentService {
    static let shared = DailyContentService()

    private(set) var quote: DailyQuote?
    private(set) var isLoading = false
    private(set) var error: String?

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {}

    /// Fetches daily content (quote of the day). On success or API fallback, quote is set. Auth sent when session exists.
    func fetch() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        guard let url = URL(string: "\(requestBaseURL)/api/daily-content") else {
            error = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let session = try? await SupabaseManager.shared.client.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                error = "Could not load quote."
                return
            }
            let value = try decoder.decode(DailyContentResponse.self, from: data)
            if value.success, !value.quote.text.isEmpty {
                quote = value.quote
            } else {
                error = "No quote available."
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
