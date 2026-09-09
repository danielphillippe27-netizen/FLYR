import Foundation
import Combine
import Supabase

enum WolfGridAppleMailbox {
    static let emailAddress = "daniel@wolfgrid.app"
    static let authenticationEmailAddress = "daniel_phillippe@icloud.com"
}

struct SalespersonEmailMailbox: Decodable, Equatable {
    let emailAddress: String
    let isActive: Bool
    let lastSyncedAt: String?
}

private struct SalespersonEmailMailboxEnvelope: Decodable {
    let connection: SalespersonEmailMailbox?
}

private struct SalespersonEmailMailboxUpdate: Encodable {
    let emailAddress: String
    let authenticationEmailAddress: String
    let appSpecificPassword: String?
    let isActive: Bool
}

private actor SalespersonEmailMailboxAPI {
    static let shared = SalespersonEmailMailboxAPI()

    func fetch() async throws -> SalespersonEmailMailbox? {
        let request = try await request(method: "GET")
        let data = try await responseData(for: request)
        return try JSONDecoder().decode(SalespersonEmailMailboxEnvelope.self, from: data).connection
    }

    func update(appSpecificPassword: String?, isActive: Bool) async throws -> SalespersonEmailMailbox {
        let payload = SalespersonEmailMailboxUpdate(
            emailAddress: WolfGridAppleMailbox.emailAddress,
            authenticationEmailAddress: WolfGridAppleMailbox.authenticationEmailAddress,
            appSpecificPassword: appSpecificPassword,
            isActive: isActive
        )
        let body = try JSONEncoder().encode(payload)
        let request = try await request(method: "PUT", body: body)
        let data = try await responseData(for: request)
        guard let mailbox = try JSONDecoder().decode(SalespersonEmailMailboxEnvelope.self, from: data).connection else {
            throw SalespersonEmailMailboxError.invalidResponse
        }
        return mailbox
    }

    private func request(method: String, body: Data? = nil) async throws -> URLRequest {
        let url = Config.backendAPIURL.appendingPathComponent("api/email/apple/connection")
        let session = try await SupabaseManager.shared.client.auth.session
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SalespersonEmailMailboxError.message("No response from the server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let serverMessage = (try? JSONDecoder().decode([String: String].self, from: data)["error"])
            throw SalespersonEmailMailboxError.message(
                serverMessage ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
        return data
    }
}

enum SalespersonEmailMailboxError: LocalizedError {
    case invalidResponse
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The mailbox server returned an invalid response."
        case .message(let message):
            return message
        }
    }
}

@MainActor
final class SalespersonEmailMailboxViewModel: ObservableObject {
    @Published private(set) var mailbox: SalespersonEmailMailbox?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    var isConnected: Bool { mailbox?.isActive == true }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            mailbox = try await SalespersonEmailMailboxAPI.shared.fetch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func save(appSpecificPassword: String?, isActive: Bool = true) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer {
            isSaving = false
            hasLoaded = true
        }
        do {
            mailbox = try await SalespersonEmailMailboxAPI.shared.update(
                appSpecificPassword: appSpecificPassword,
                isActive: isActive
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
