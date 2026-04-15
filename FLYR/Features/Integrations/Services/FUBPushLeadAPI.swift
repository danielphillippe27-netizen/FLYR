import Foundation
import Supabase

/// Calls FLYR backend POST /api/integrations/fub/push-lead and POST /api/leads/sync-crm with Bearer JWT.
/// Uses the key stored in crm_connection_secrets (native Connect flow).
@MainActor
final class FUBPushLeadAPI {
    static let shared = FUBPushLeadAPI()

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

    /// Build push-lead body from LeadModel (at least one of email or phone required).
    /// Optional task/appointment payloads are forwarded for FUB follow-up creation.
    func pushLead(
        _ lead: LeadModel,
        appointment: LeadSyncAppointment? = nil,
        task: LeadSyncTask? = nil
    ) async throws -> FUBPushLeadResponse {
        let cleanedEmail = lead.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPhone = lead.phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail: String? = {
            guard let email = cleanedEmail, !email.isEmpty else { return nil }
            guard Self.isLikelyValidEmail(email) else {
                print("⚠️ [FUBPushLeadAPI] Ignoring invalid email for FUB push: \(email)")
                return nil
            }
            return email
        }()
        let hasEmail = normalizedEmail != nil
        let hasPhone = cleanedPhone?.isEmpty == false
        guard hasEmail || hasPhone else {
            throw FUBPushLeadError.invalidLead("Lead must have at least one of email or phone.")
        }

        let nameParts = (lead.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let firstName = nameParts.first.map(String.init)
        let lastName = nameParts.count > 1 ? String(nameParts[1]) : nil

        let taskPayload: FUBPushLeadRequest.TaskPayload? = {
            guard let task else { return nil }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            return FUBPushLeadRequest.TaskPayload(
                title: task.title,
                dueDate: dateFormatter.string(from: task.dueDate)
            )
        }()

        let appointmentPayload: FUBPushLeadRequest.AppointmentPayload? = {
            guard let appointment else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return FUBPushLeadRequest.AppointmentPayload(
                date: formatter.string(from: appointment.date),
                title: appointment.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                notes: appointment.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }()

        let body = FUBPushLeadRequest(
            firstName: firstName?.isEmpty == false ? firstName : nil,
            lastName: lastName?.isEmpty == false ? lastName : nil,
            email: normalizedEmail,
            phone: hasPhone ? cleanedPhone : nil,
            address: lead.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? lead.address : nil,
            city: nil,
            state: nil,
            zip: nil,
            message: lead.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? lead.notes : nil,
            source: lead.source.isEmpty ? "FLYR" : lead.source,
            sourceUrl: nil,
            campaignId: lead.campaignId.map { $0.uuidString },
            metadata: nil,
            task: taskPayload,
            appointment: appointmentPayload
        )

        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/fub/push-lead")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        if let payload = String(data: request.httpBody ?? Data(), encoding: .utf8) {
            print("📤 [FUBPushLeadAPI] push-lead payload: \(payload)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FUBPushLeadError.network("Invalid response.")
        }

        let decoder = JSONDecoder()
        
        // Handle error status codes first (before trying to decode success response)
        if http.statusCode == 404 {
            throw FUBPushLeadError.notConnected("FUB integration not found.")
        }
        if http.statusCode == 401 {
            // Check for token expired error
            if let errorJson = try? decoder.decode([String: String].self, from: data),
               errorJson["code"] == "FUB_TOKEN_EXPIRED" {
                throw FUBPushLeadError.tokenExpired(errorJson["error"] ?? "Follow Up Boss token expired.")
            }
            throw FUBPushLeadError.unauthorized("Not authorized.")
        }
        if !(200...299).contains(http.statusCode) {
            // Try to decode error message from response
            print("❌ [FUBPushLeadAPI] push-lead HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "<invalid UTF-8>")")
            if let errorJson = try? decoder.decode([String: String].self, from: data),
               let errorMsg = errorJson["error"] {
                throw FUBPushLeadError.server(errorMsg)
            }
            throw FUBPushLeadError.server("Push failed (HTTP \(http.statusCode)).")
        }

        // Now decode successful response
        do {
            let parsed = try decoder.decode(FUBPushLeadResponse.self, from: data)
            print("✅ [FUBPushLeadAPI] push-lead success personId=\(parsed.fubPersonId.map(String.init) ?? "nil") note=\(parsed.noteCreated == true ? "ok" : "pending/failed") task=\(parsed.taskCreated == true ? "ok" : "pending/failed") appt=\(parsed.appointmentCreated == true ? "ok" : "pending/failed")")
            if let errors = parsed.followUpErrors, !errors.isEmpty {
                print("⚠️ [FUBPushLeadAPI] follow-up errors: \(errors.joined(separator: " | "))")
            }
            return parsed
        } catch {
            print("❌ [FUBPushLeadAPI] JSON decode error: \(error)")
            print("❌ [FUBPushLeadAPI] Response data: \(String(data: data, encoding: .utf8) ?? "<invalid UTF-8>")")
            throw FUBPushLeadError.server("Invalid response format from server.")
        }
    }

    private static func isLikelyValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let domain = String(parts[1])
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    /// Fetch FUB connection status from backend (connected, lastSyncAt, lastError).
    func fetchStatus() async throws -> FUBStatusResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/fub/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FUBPushLeadError.network("Invalid response.") }
        let decoded = try JSONDecoder().decode(FUBStatusResponse.self, from: data)
        if http.statusCode == 401 { throw FUBPushLeadError.unauthorized(decoded.error ?? "Not authorized.") }
        if !(200...299).contains(http.statusCode) { throw FUBPushLeadError.server(decoded.error ?? "Request failed.") }
        return decoded
    }

    /// Test that the stored FUB key is still valid (backend calls FUB /me).
    func testConnection() async throws -> FUBTestResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/fub/test")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FUBPushLeadError.network("Invalid response.") }
        let decoded = try JSONDecoder().decode(FUBTestResponse.self, from: data)
        if http.statusCode == 404 { throw FUBPushLeadError.notConnected(decoded.error ?? "Not connected.") }
        if http.statusCode == 401 { throw FUBPushLeadError.unauthorized(decoded.error ?? "Not authorized.") }
        if !(200...299).contains(http.statusCode) { throw FUBPushLeadError.server(decoded.error ?? "Test failed.") }
        return decoded
    }

    /// Send a test lead to Follow Up Boss (test@flyrpro.app, 5555555555).
    func testPush() async throws -> FUBTestResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/fub/test-push")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FUBPushLeadError.network("Invalid response.") }
        let decoded = try JSONDecoder().decode(FUBTestResponse.self, from: data)
        if http.statusCode == 400 { throw FUBPushLeadError.notConnected(decoded.error ?? "Not connected.") }
        if http.statusCode == 401 { throw FUBPushLeadError.unauthorized(decoded.error ?? "Not authorized.") }
        if !(200...299).contains(http.statusCode) { throw FUBPushLeadError.server(decoded.error ?? "Test push failed.") }
        return decoded
    }

    /// Sync existing contacts to Follow Up Boss (backend fetches contacts and pushes each).
    func syncCRM() async throws -> FUBSyncCRMResponse {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/leads/sync-crm")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FUBPushLeadError.network("Invalid response.")
        }

        let decoder = JSONDecoder()
        let parsed = try decoder.decode(FUBSyncCRMResponse.self, from: data)

        if http.statusCode == 400 && parsed.error != nil {
            throw FUBPushLeadError.notConnected(parsed.error!)
        }
        if http.statusCode == 401 {
            throw FUBPushLeadError.unauthorized(parsed.error ?? "Not authorized.")
        }
        if !(200...299).contains(http.statusCode) {
            throw FUBPushLeadError.server(parsed.error ?? "Sync failed.")
        }

        return parsed
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum FUBPushLeadError: LocalizedError {
    case invalidLead(String)
    case notConnected(String)
    case unauthorized(String)
    case tokenExpired(String)
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidLead(let msg), .notConnected(let msg), .unauthorized(let msg), .tokenExpired(let msg), .network(let msg), .server(let msg):
            return msg
        }
    }
}
