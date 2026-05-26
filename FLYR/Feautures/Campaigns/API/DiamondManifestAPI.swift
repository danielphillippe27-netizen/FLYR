import Foundation
import Supabase

final class DiamondManifestAPI {
    static let shared = DiamondManifestAPI()

    private let supabaseClient = SupabaseManager.shared.client
    private let baseURL: URL

    private init() {
        let configured =
            (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String) ??
            (Bundle.main.object(forInfoDictionaryKey: "FLYR_API_BASE_URL") as? String) ??
            "https://flyrpro.app"
        let trimmed = configured.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if let components = URLComponents(string: trimmed),
           components.host?.lowercased() == "flyrpro.app" {
            self.baseURL = URL(string: "https://www.flyrpro.app")!
        } else {
            self.baseURL = URL(string: trimmed) ?? URL(string: "https://www.flyrpro.app")!
        }
    }

    func fetchManifest(campaignId: UUID) async throws -> DiamondManifest {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("campaigns")
            .appendingPathComponent(campaignId.uuidString)
            .appendingPathComponent("diamond-manifest")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let session = try? await supabaseClient.auth.session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiamondManifestAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw DiamondManifestAPIError.httpStatus(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(DiamondManifest.self, from: data)
    }

    func waitForReadyManifest(
        campaignId: UUID,
        timeoutSeconds: TimeInterval = 120,
        pollIntervalSeconds: TimeInterval = 3
    ) async throws -> DiamondManifest {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastError: Error?

        while Date() < deadline {
            do {
                let manifest = try await fetchManifest(campaignId: campaignId)
                if manifest.hasRenderablePMTilesGeometry || manifest.hasRenderablePMTilesAddresses {
                    return manifest
                }
            } catch {
                lastError = error
            }

            let sleepNanoseconds = UInt64(pollIntervalSeconds * 1_000_000_000)
            try await Task.sleep(nanoseconds: sleepNanoseconds)
        }

        throw DiamondManifestAPIError.notReady(lastError?.localizedDescription)
    }
}

enum DiamondManifestAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case notReady(String?)

    var statusCode: Int? {
        switch self {
        case .invalidResponse:
            return nil
        case .httpStatus(let status):
            return status
        case .notReady:
            return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid Diamond manifest response"
        case .httpStatus(let status):
            return "Diamond manifest request failed with status \(status)"
        case .notReady(let reason):
            if let reason, !reason.isEmpty {
                return "Diamond geometry was not ready yet: \(reason)"
            }
            return "Diamond geometry was not ready yet"
        }
    }
}
