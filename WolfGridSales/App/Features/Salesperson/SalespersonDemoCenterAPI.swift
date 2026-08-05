import Foundation
import Auth
import Supabase

enum SalespersonDemoCenterAPIError: LocalizedError {
    case badURL
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Unable to build demo link request."
        case .status(_, let message):
            return message
        }
    }
}

struct SalespersonDemoCenterResponse: Decodable, Equatable {
    struct Salesperson: Decodable, Equatable {
        let id: String
        let fullName: String?
        let email: String?
        let referralCode: String
        let demoEmailAddress: String?
        let assignedPhoneNumber: String?
        let phoneForwardTo: String?
    }

    struct Links: Decodable, Equatable {
        let soloDemoUrl: String?
        let teamDemoUrl: String?
        let individualAgentListingUrl: String?
        let realEstateAgentUrl: String?
        let realEstateTeamUrl: String?
        let roofingUrl: String?
        let solarUrl: String?
        let homeServiceUrl: String?

        var resolvedSoloDemoUrl: String? {
            Self.clean(soloDemoUrl)
                ?? Self.clean(individualAgentListingUrl)
                ?? Self.clean(realEstateAgentUrl)
        }

        var resolvedTeamDemoUrl: String? {
            Self.clean(teamDemoUrl) ?? Self.clean(realEstateTeamUrl)
        }

        private static func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return nil }
            return trimmed
        }
    }

    struct Stats: Decodable, Equatable {
        let clicks: Int?
        let demoViews: Int?
        let videoStarts: Int?
        let trials: Int?
        let emailOpens: Int?
        let emailOpenTrackingEnabled: Bool?
    }

    let salesperson: Salesperson
    let links: Links
    let stats: Stats?

    var attributionText: String {
        let trimmedName = salesperson.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName?.isEmpty == false ? trimmedName : nil
        return "\(name ?? "Salesperson") · \(salesperson.referralCode)"
    }
}

actor SalespersonDemoCenterAPI {
    static let shared = SalespersonDemoCenterAPI()

    private let decoder = JSONDecoder()

    func fetchDemoCenter() async throws -> SalespersonDemoCenterResponse {
        guard let url = URL(string: "api/salesperson/demo-center", relativeTo: Config.backendAPIURL)?.absoluteURL else {
            throw SalespersonDemoCenterAPIError.badURL
        }

        let session = try await SupabaseManager.shared.client.auth.session
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SalespersonDemoCenterAPIError.status(0, "No response from server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode([String: String].self, from: data)["error"])
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SalespersonDemoCenterAPIError.status(http.statusCode, message)
        }

        return try decoder.decode(SalespersonDemoCenterResponse.self, from: data)
    }
}
