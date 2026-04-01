import Foundation
import Supabase

@MainActor
final class HubSpotPushLeadAPI {
    static let shared = HubSpotPushLeadAPI()

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

    /// HubSpot requires at least email or name (phone/address alone are not enough for contact creation).
    func pushLead(
        _ lead: LeadModel,
        appointment: LeadSyncAppointment? = nil,
        task: LeadSyncTask? = nil
    ) async throws -> HubSpotPushLeadResponse {
        let cleanedEmail = lead.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedPhone = lead.phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = lead.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmail = cleanedEmail?.isEmpty == false
        let hasName = cleanedName?.isEmpty == false
        guard hasEmail || hasName else {
            throw HubSpotPushLeadError.invalidLead("Lead must have at least an email or a name for HubSpot.")
        }

        let taskPayload: HubSpotPushLeadRequest.TaskPayload? = {
            guard let task else { return nil }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            return HubSpotPushLeadRequest.TaskPayload(
                title: task.title,
                dueDate: dateFormatter.string(from: task.dueDate)
            )
        }()

        let appointmentPayload: HubSpotPushLeadRequest.AppointmentPayload? = {
            guard let appointment else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return HubSpotPushLeadRequest.AppointmentPayload(
                date: formatter.string(from: appointment.date),
                title: appointment.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                notes: appointment.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }()

        let body = HubSpotPushLeadRequest(
            id: lead.id.uuidString,
            name: cleanedName?.nilIfEmpty,
            phone: cleanedPhone?.nilIfEmpty,
            email: cleanedEmail?.nilIfEmpty,
            address: lead.address?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            source: lead.source.isEmpty ? "FLYR" : lead.source,
            campaignId: lead.campaignId?.uuidString,
            notes: lead.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: ISO8601DateFormatter().string(from: lead.createdAt),
            task: taskPayload,
            appointment: appointmentPayload
        )

        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(requestBaseURL)/api/integrations/hubspot/push-lead")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HubSpotPushLeadError.network("Invalid response.")
        }

        let decoder = JSONDecoder()
        if !(200...299).contains(http.statusCode) {
            let parsed = try? decoder.decode(HubSpotPushLeadResponse.self, from: data)
            let message = parsed?.error
                ?? parsed?.message
                ?? Self.extractServerMessage(from: data, fallback: "HubSpot sync failed (HTTP \(http.statusCode)).")

            switch http.statusCode {
            case 400:
                throw HubSpotPushLeadError.invalidLead(message)
            case 401:
                throw HubSpotPushLeadError.unauthorized(message)
            case 404:
                throw HubSpotPushLeadError.notConnected(message)
            default:
                throw HubSpotPushLeadError.server(message)
            }
        }

        do {
            let decoded = try decoder.decode(HubSpotPushLeadResponse.self, from: data)
            if decoded.success {
                return decoded
            }
            throw HubSpotPushLeadError.server(
                decoded.error
                    ?? decoded.message
                    ?? Self.extractServerMessage(from: data, fallback: "HubSpot sync failed.")
            )
        } catch let error as HubSpotPushLeadError {
            throw error
        } catch {
            let message = Self.extractServerMessage(
                from: data,
                fallback: "The server returned an unexpected response."
            )
            throw HubSpotPushLeadError.server(message)
        }
    }
}

enum HubSpotPushLeadError: LocalizedError {
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

private extension HubSpotPushLeadAPI {
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
