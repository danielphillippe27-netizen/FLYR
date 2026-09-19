import Foundation
import Supabase

enum SalespersonCalendarEventType: String {
    case appointment
    case followUp = "follow_up"
    case call
    case task
}

struct SalespersonCalendarItem: Identifiable, Equatable, Sendable {
    let id: String
    let sourceId: UUID
    let eventType: String
    let title: String
    let startAt: Date
    let endAt: Date
    let notes: String?
    let location: String?
    let contactName: String?
    let conferenceProvider: String?
    let conferenceJoinURL: URL?
    let attendeeEmails: [String]

    enum CodingKeys: String, CodingKey {
        case sourceId = "id"
        case eventType = "event_type"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case notes
        case location
    }

    fileprivate init(from row: SalespersonCalendarRow) {
        id = "event-\(row.id.uuidString)"
        sourceId = row.id
        eventType = row.eventType
        title = row.title
        startAt = row.startAt
        endAt = row.endAt
        notes = row.notes
        location = row.location
        contactName = row.contactName
        conferenceProvider = row.conferenceProvider
        conferenceJoinURL = row.conferenceJoinURL.flatMap(URL.init(string:))
        attendeeEmails = row.attendeeEmails
    }
}

private struct SalespersonCalendarRow: Decodable {
    let id: UUID
    let eventType: String
    let title: String
    let startAt: Date
    let endAt: Date
    let notes: String?
    let location: String?
    let contactName: String?
    let conferenceProvider: String?
    let conferenceJoinURL: String?
    let attendeeEmails: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case eventType = "event_type"
        case title
        case startAt = "start_at"
        case endAt = "end_at"
        case notes
        case location
        case contactName = "contact_name"
        case conferenceProvider = "conference_provider"
        case conferenceJoinURL = "conference_join_url"
        case attendeeEmails = "attendee_emails"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // Older meeting-api responses omitted event_type even though the saved
        // calendar row was always an appointment. Keep those responses usable
        // while the server contract rolls out.
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
            ?? SalespersonCalendarEventType.appointment.rawValue
        title = try container.decode(String.self, forKey: .title)
        startAt = try container.decode(Date.self, forKey: .startAt)
        endAt = try container.decode(Date.self, forKey: .endAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName)
        conferenceProvider = try container.decodeIfPresent(String.self, forKey: .conferenceProvider)
        conferenceJoinURL = try container.decodeIfPresent(String.self, forKey: .conferenceJoinURL)
        attendeeEmails = try container.decodeIfPresent([String].self, forKey: .attendeeEmails) ?? []
    }
}

actor SalespersonCalendarService {
    static let shared = SalespersonCalendarService()

    private var client: SupabaseClient { SupabaseManager.shared.client }

    func fetchCalendarItems(start: Date, end: Date) async -> [SalespersonCalendarItem] {
        guard let userId = await MainActor.run(body: { AuthManager.shared.user?.id }) else { return [] }
        do {
            let rows: [SalespersonCalendarRow] = try await client
                .from("calendar_events")
                .select("id,event_type,title,start_at,end_at,notes,location,contact_name,conference_provider,conference_join_url,attendee_emails")
                .eq("user_id", value: userId)
                .is("deleted_at", value: nil)
                .gte("start_at", value: start)
                .lte("start_at", value: end)
                .order("start_at", ascending: true)
                .execute()
                .value
            return rows.map(SalespersonCalendarItem.init)
        } catch {
            return []
        }
    }

    func fetchAllCalendarItems() async -> [SalespersonCalendarItem] {
        guard let userId = await MainActor.run(body: { AuthManager.shared.user?.id }) else { return [] }
        do {
            let rows: [SalespersonCalendarRow] = try await client
                .from("calendar_events")
                .select("id,event_type,title,start_at,end_at,notes,location,contact_name,conference_provider,conference_join_url,attendee_emails")
                .eq("user_id", value: userId)
                .is("deleted_at", value: nil)
                .order("start_at", ascending: true)
                .execute()
                .value
            return rows.map(SalespersonCalendarItem.init)
        } catch {
            return []
        }
    }

    func deleteEvent(id: UUID) async throws {
        try await client
            .from("calendar_events")
            .update(["deleted_at": AnyCodable(Date())])
            .eq("id", value: id)
            .execute()
    }
}

struct ZoomConnectionStatus: Decodable, Sendable {
    let connected: Bool
    let email: String?
}

struct ZoomMeetingDraft: Encodable, Sendable {
    let title: String
    let startAt: Date
    let endAt: Date
    let notes: String?
    let attendeeEmails: [String]
    let workspaceId: String?
    let contactName: String?
    let timeZone: String?
}

private struct ZoomOAuthStartResponse: Decodable {
    let authorizeUrl: String?
    let error: String?
}

private struct ZoomMeetingResponse: Decodable {
    let meeting: SalespersonCalendarRow?
    let invitationsSent: Int?
    let invitationsRequested: Int?
    let error: String?
}

struct ZoomMeetingCreationResult: Sendable {
    let meeting: SalespersonCalendarItem
    let invitationsSent: Int
    let invitationsRequested: Int
}

actor ZoomMeetingAPI {
    static let shared = ZoomMeetingAPI()

    private var baseURL: URL { Config.backendAPIURL }

    func status() async throws -> ZoomConnectionStatus {
        try await request(path: "/api/integrations/zoom/status", method: "GET", body: Optional<String>.none)
    }

    func authorizeURL() async throws -> URL {
        let response: ZoomOAuthStartResponse = try await request(
            path: "/api/integrations/zoom/oauth/start?platform=ios",
            method: "GET",
            body: Optional<String>.none
        )
        guard let rawURL = response.authorizeUrl, let url = URL(string: rawURL) else {
            throw NSError(domain: "ZoomMeetingAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Zoom did not return an authorization URL."])
        }
        return url
    }

    func createMeeting(_ draft: ZoomMeetingDraft) async throws -> ZoomMeetingCreationResult {
        let response: ZoomMeetingResponse = try await request(path: "/api/meetings", method: "POST", body: draft)
        guard let meeting = response.meeting else {
            throw NSError(domain: "ZoomMeetingAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: response.error ?? "Zoom did not return the created meeting."])
        }
        return ZoomMeetingCreationResult(
            meeting: SalespersonCalendarItem(from: meeting),
            invitationsSent: response.invitationsSent ?? 0,
            invitationsRequested: response.invitationsRequested ?? 0
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let session = try await SupabaseManager.shared.client.auth.session
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.flyrZoom.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if (200...299).contains(http.statusCode) {
            return try JSONDecoder.flyrZoom.decode(Response.self, from: data)
        }
        let serverError = (try? JSONDecoder().decode(ZoomMeetingResponse.self, from: data).error)
        throw NSError(domain: "ZoomMeetingAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: serverError ?? "Zoom request failed."])
    }
}

private extension JSONEncoder {
    static var flyrZoom: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var flyrZoom: JSONDecoder {
        let decoder = JSONDecoder()
        // SalespersonCalendarRow defines explicit snake_case CodingKeys, while
        // the response envelope uses camelCase. Applying convertFromSnakeCase
        // here transforms the row keys before those explicit mappings run.
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
