import Foundation
import Supabase

enum ActivityFeedFilter: String, CaseIterable, Identifiable {
    case activity = "Activity"
    case appointments = "Appointments"
    case followUp = "Follow Up"

    var id: String { rawValue }
}

enum ActivityFeedKind {
    case session
    case appointment
    case followUp
}

struct ActivityFeedItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let timestamp: Date
    let kind: ActivityFeedKind
    let sessionId: UUID?
    let sessionDurationSeconds: TimeInterval?
}

@MainActor
final class ActivityFeedService {
    static let shared = ActivityFeedService()

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private init() {}

    func fetchItems(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        filter: ActivityFeedFilter,
        limit: Int = 150
    ) async throws -> [ActivityFeedItem] {
        switch filter {
        case .activity:
            return try await fetchSessionItems(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
        case .appointments:
            async let appointmentActivities = fetchAppointmentRows(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
            async let contactsTask = fetchContactRows(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
            let activities = (try? await appointmentActivities) ?? []
            let contacts = try await contactsTask
            let contactIdsWithMeeting = Set(activities.map(\.contact.id))

            let activityItems = activities.map { row in
                ActivityFeedItem(
                    id: "appointment-activity-\(row.id.uuidString)",
                    title: displayName(for: row.contact),
                    subtitle: appointmentSubtitle(for: row),
                    timestamp: row.timestamp,
                    kind: .appointment,
                    sessionId: nil,
                    sessionDurationSeconds: nil
                )
            }

            let contactItems = contacts
                .filter { isAppointmentStatus($0.status) && !contactIdsWithMeeting.contains($0.id) }
                .map { row in
                    let status = prettyStatus(row.status)
                    let subtitle = "\(row.address) • \(status)"
                    return ActivityFeedItem(
                        id: "appointment-\(row.id.uuidString)",
                        title: displayName(for: row),
                        subtitle: subtitle,
                        timestamp: row.updatedAt ?? row.createdAt,
                        kind: .appointment,
                        sessionId: nil,
                        sessionDurationSeconds: nil
                    )
                }
            return (activityItems + contactItems)
                .sorted(by: { $0.timestamp > $1.timestamp })
        case .followUp:
            let contacts = try await fetchContactRows(
                userId: userId,
                workspaceId: workspaceId,
                includeMembers: includeMembers,
                limit: limit
            )
            return contacts
                .filter { needsFollowUp($0) }
                .map { row in
                    let dueDate = row.reminderDate ?? row.updatedAt ?? row.createdAt
                    let subtitle: String
                    if row.reminderDate != nil {
                        subtitle = "\(row.address) • Follow up due"
                    } else {
                        subtitle = "\(row.address) • \(prettyStatus(row.status))"
                    }
                    return ActivityFeedItem(
                        id: "follow-up-\(row.id.uuidString)",
                        title: displayName(for: row),
                        subtitle: subtitle,
                        timestamp: dueDate,
                        kind: .followUp,
                        sessionId: nil,
                        sessionDurationSeconds: nil
                    )
                }
                .sorted(by: { $0.timestamp < $1.timestamp })
        }
    }

    private func fetchSessionItems(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        limit: Int
    ) async throws -> [ActivityFeedItem] {
        if !NetworkMonitor.shared.isOnline {
            guard !includeMembers else { return [] }
            let localRows = await SessionRepository.shared.fetchRecentSessions(limit: limit)
            return localRows.map { row in
                let durationSeconds = max(60, row.durationSeconds)
                let durationMinutes = max(1, Int(durationSeconds / 60))
                let doors = row.doorsCount
                let conversations = max(0, row.conversations ?? 0)
                let title = row.end_time == nil ? "Your session active" : "Your session complete"
                var subtitle = "\(doors) homes • \(durationMinutes) min"
                if conversations > 0 {
                    subtitle += " • \(conversations) conv"
                }
                return ActivityFeedItem(
                    id: "session-\(row.id?.uuidString ?? UUID().uuidString)",
                    title: title,
                    subtitle: subtitle,
                    timestamp: row.start_time,
                    kind: .session,
                    sessionId: row.id,
                    sessionDurationSeconds: durationSeconds
                )
            }
        }

        var query = client
            .from("session_analytics")
            .select()

        if includeMembers, let workspaceId {
            query = query.eq("workspace_id", value: workspaceId.uuidString)
        } else {
            query = query.eq("user_id", value: userId.uuidString)
        }

        let response = try await query
            .order("start_time", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder.supabaseDates
        let rows = try decoder.decode([SessionRecord].self, from: response.data)

        return rows.map { row in
            guard let sessionId = row.id else {
                return ActivityFeedItem(
                    id: "session-missing-id-\(row.start_time.timeIntervalSince1970)",
                    title: "Session",
                    subtitle: "Missing session id",
                    timestamp: row.start_time,
                    kind: .session,
                    sessionId: nil,
                    sessionDurationSeconds: max(60, row.durationSeconds)
                )
            }

            let durationSeconds = max(60, row.durationSeconds)
            let durationMinutes = max(1, Int(durationSeconds / 60))
            let doors = row.doorsCount
            let conversations = max(0, row.conversations ?? 0)
            let memberPrefix = includeMembers && row.user_id != userId ? "Team" : "Your"
            let title = row.end_time == nil ? "\(memberPrefix) session active" : "\(memberPrefix) session complete"
            var subtitle = "\(doors) homes • \(durationMinutes) min"
            if conversations > 0 {
                subtitle += " • \(conversations) conv"
            }
            return ActivityFeedItem(
                id: "session-\(sessionId.uuidString)",
                title: title,
                subtitle: subtitle,
                timestamp: row.start_time,
                kind: .session,
                sessionId: sessionId,
                sessionDurationSeconds: durationSeconds
            )
        }
    }

    func fetchSessionRecord(sessionId: UUID) async throws -> SessionRecord? {
        if !NetworkMonitor.shared.isOnline {
            return await SessionRepository.shared.fetchSessionRecord(sessionId: sessionId)
        }

        do {
            let response = try await client
                .from("session_analytics")
                .select()
                .eq("id", value: sessionId.uuidString)
                .limit(1)
                .execute()

            let decoder = JSONDecoder.supabaseDates
            let rows = try decoder.decode([SessionRecord].self, from: response.data)
            if let row = rows.first {
                return row
            }
            return await SessionRepository.shared.fetchSessionRecord(sessionId: sessionId)
        } catch {
            if let local = await SessionRepository.shared.fetchSessionRecord(sessionId: sessionId) {
                return local
            }
            throw error
        }
    }

    private func fetchContactRows(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        limit: Int
    ) async throws -> [ContactFeedRow] {
        let decoder = JSONDecoder.supabaseDates
        do {
            var query = client
                .from("contacts")
                .select("id,user_id,full_name,address,status,reminder_date,updated_at,created_at")
            if includeMembers, let workspaceId {
                query = query.eq("workspace_id", value: workspaceId.uuidString)
            } else {
                query = query.eq("user_id", value: userId.uuidString)
            }
            let response = try await query
                .order("updated_at", ascending: false)
                .limit(limit)
                .execute()
            let contacts = try decoder.decode([ContactFeedRow].self, from: response.data)
            if !contacts.isEmpty {
                return contacts
            }
        } catch {
            // Fall through to legacy field_leads when contacts are empty/unavailable.
        }

        var legacyQuery = client
            .from("field_leads")
            .select("id,user_id,name,address,status,updated_at,created_at")
        if includeMembers, let workspaceId {
            legacyQuery = legacyQuery.eq("workspace_id", value: workspaceId.uuidString)
        } else {
            legacyQuery = legacyQuery.eq("user_id", value: userId.uuidString)
        }
        let legacyResponse = try await legacyQuery
            .order("updated_at", ascending: false)
            .limit(limit)
            .execute()
        let legacyRows = try decoder.decode([LegacyLeadRow].self, from: legacyResponse.data)
        return legacyRows.map {
            ContactFeedRow(
                id: $0.id,
                userId: $0.userId,
                fullName: $0.name,
                address: $0.address,
                status: $0.status,
                reminderDate: nil,
                updatedAt: $0.updatedAt,
                createdAt: $0.createdAt
            )
        }
    }

    private func fetchAppointmentRows(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        limit: Int
    ) async throws -> [AppointmentActivityRow] {
        var query = client
            .from("contact_activities")
            .select("id,contact_id,note,timestamp,created_at,contacts!inner(id,full_name,address,user_id,workspace_id)")
            .eq("type", value: ActivityType.meeting.rawValue)

        if includeMembers, let workspaceId {
            query = query.eq("contacts.workspace_id", value: workspaceId.uuidString)
        } else {
            query = query.eq("contacts.user_id", value: userId.uuidString)
        }

        let response = try await query
            .order("timestamp", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder.supabaseDates
        return try decoder.decode([AppointmentActivityRow].self, from: response.data)
    }

    private func displayName(for row: ContactFeedRow) -> String {
        let trimmed = row.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? row.address : trimmed
    }

    private func displayName(for row: AppointmentContactRow) -> String {
        let trimmed = row.fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? row.address : trimmed
    }

    private func prettyStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "not_home": return "Not home"
        case "no_answer": return "No answer"
        case "qr_scanned": return "QR scanned"
        case "follow_up": return "Follow up"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func isAppointmentStatus(_ raw: String) -> Bool {
        let normalized = raw.lowercased()
        return normalized == "interested" || normalized == "hot" || normalized == "appointment"
    }

    private func needsFollowUp(_ row: ContactFeedRow) -> Bool {
        if row.reminderDate != nil {
            return true
        }
        let normalized = row.status.lowercased()
        return normalized == "follow_up" || normalized == "not_home" || normalized == "no_answer" || normalized == "warm"
    }

    private func appointmentSubtitle(for row: AppointmentActivityRow) -> String {
        let parsed = parseAppointmentNote(row.note)
        let subject = parsed.subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = parsed.start?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = (parsed.address?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? row.contact.address

        if let subject, !subject.isEmpty {
            return "\(address) • \(subject)"
        }
        if let start, !start.isEmpty {
            return "\(address) • \(start)"
        }
        return "\(address) • Appointment"
    }

    private func parseAppointmentNote(_ note: String?) -> (subject: String?, start: String?, address: String?) {
        guard let note, !note.isEmpty else {
            return (nil, nil, nil)
        }

        let segments = note
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var subject: String?
        var start: String?
        var address: String?

        for segment in segments {
            if segment.caseInsensitiveCompare("Appointment") == .orderedSame {
                continue
            }
            if segment.hasPrefix("Start:") {
                start = String(segment.dropFirst("Start:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if segment.hasPrefix("Address:") {
                address = String(segment.dropFirst("Address:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            if segment.hasPrefix("End:") {
                continue
            }
            if subject == nil {
                subject = segment
            }
        }

        return (subject, start, address)
    }
}

private struct ContactFeedRow: Decodable {
    let id: UUID
    let userId: UUID?
    let fullName: String?
    let address: String
    let status: String
    let reminderDate: Date?
    let updatedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case address
        case status
        case reminderDate = "reminder_date"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

private struct LegacyLeadRow: Decodable {
    let id: UUID
    let userId: UUID?
    let name: String?
    let address: String
    let status: String
    let updatedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case address
        case status
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

private struct AppointmentActivityRow: Decodable {
    let id: UUID
    let contactId: UUID
    let note: String?
    let timestamp: Date
    let createdAt: Date
    let contact: AppointmentContactRow

    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "contact_id"
        case note
        case timestamp
        case createdAt = "created_at"
        case contact = "contacts"
    }
}

private struct AppointmentContactRow: Decodable {
    let id: UUID
    let fullName: String?
    let address: String
    let userId: UUID?
    let workspaceId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case address
        case userId = "user_id"
        case workspaceId = "workspace_id"
    }
}
