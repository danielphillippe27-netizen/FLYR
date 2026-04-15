import Foundation
import Supabase

@MainActor
final class BoldTrailPushLeadAPI {
    static let shared = BoldTrailPushLeadAPI()

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

    private init() {}

    func pushLead(_ lead: LeadModel) async throws -> BoldTrailPushLeadResponse {
        let cleanedEmail = lead.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPhone = lead.phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (cleanedEmail?.isEmpty == false) || (cleanedPhone?.isEmpty == false) else {
            throw BoldTrailPushLeadError.invalidLead("Lead must have at least one of email or phone.")
        }

        let body = BoldTrailPushLeadRequest(
            id: lead.id.uuidString,
            name: lead.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            phone: cleanedPhone?.nilIfEmpty,
            email: cleanedEmail?.nilIfEmpty,
            address: lead.address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: lead.source.isEmpty ? "FLYR" : lead.source,
            campaignId: lead.campaignId?.uuidString,
            notes: lead.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: ISO8601DateFormatter().string(from: lead.createdAt)
        )

        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/boldtrail/push-lead")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BoldTrailPushLeadError.network("Invalid response.")
        }

        let decoder = JSONDecoder()
        if !(200...299).contains(http.statusCode) {
            let parsed = try? decoder.decode(BoldTrailPushLeadResponse.self, from: data)
            let message = parsed?.error
                ?? parsed?.message
                ?? Self.extractServerMessage(
                    from: data,
                    fallback: "BoldTrail sync failed (HTTP \(http.statusCode))."
                )

            switch http.statusCode {
            case 400:
                throw BoldTrailPushLeadError.invalidLead(message)
            case 401:
                throw BoldTrailPushLeadError.unauthorized(message)
            case 404:
                throw BoldTrailPushLeadError.notConnected(message)
            default:
                throw BoldTrailPushLeadError.server(message)
            }
        }

        do {
            let decoded = try decoder.decode(BoldTrailPushLeadResponse.self, from: data)
            if decoded.success {
                return decoded
            }
            throw BoldTrailPushLeadError.server(
                decoded.error
                    ?? decoded.message
                    ?? Self.extractServerMessage(from: data, fallback: "BoldTrail sync failed.")
            )
        } catch let error as BoldTrailPushLeadError {
            throw error
        } catch {
            let message = Self.extractServerMessage(
                from: data,
                fallback: "The server returned an unexpected response."
            )
            throw BoldTrailPushLeadError.server(message)
        }
    }
}

enum BoldTrailPushLeadError: LocalizedError {
    case invalidLead(String)
    case notConnected(String)
    case unauthorized(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidLead(let message), .notConnected(let message), .unauthorized(let message), .network(let message), .server(let message):
            return message
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension BoldTrailPushLeadAPI {
    static func extractServerMessage(from data: Data, fallback: String) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "detail", "details"] {
                if let value = json[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            if text.hasPrefix("<") {
                return fallback
            }
            if text.count > 240 {
                return String(text.prefix(237)) + "..."
            }
            return text
        }

        return fallback
    }
}
