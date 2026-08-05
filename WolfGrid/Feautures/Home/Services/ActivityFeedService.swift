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
    let dueDate: Date?
    let kind: ActivityFeedKind
    let contactId: UUID?
    let activityId: UUID?
    let address: String?
    let notes: String?
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
            let contacts = try await contactsTask
            let localActivities = await fetchLocalAppointmentRows(
                contacts: contacts,
                limit: limit
            )
            let remoteActivities = (try? await appointmentActivities) ?? []
            let activities = mergeAppointmentRows(localActivities + remoteActivities, limit: limit)
            let contactIdsWithMeeting = Set(activities.map(\.contact.id))

            let activityItems = activities.map { row in
                ActivityFeedItem(
                    id: "appointment-activity-\(row.id.uuidString)",
                    title: displayName(for: row.contact),
                    subtitle: appointmentSubtitle(for: row),
                    timestamp: row.timestamp,
                    dueDate: row.timestamp,
                    kind: .appointment,
                    contactId: row.contact.id,
                    activityId: row.id,
                    address: row.contact.address,
                    notes: row.note,
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
                        dueDate: row.reminderDate,
                        kind: .appointment,
                        contactId: row.id,
                        activityId: nil,
                        address: row.address,
                        notes: row.notes,
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
                        dueDate: dueDate,
                        kind: .followUp,
                        contactId: row.id,
                        activityId: nil,
                        address: row.address,
                        notes: row.notes,
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
                    dueDate: nil,
                    kind: .session,
                    contactId: nil,
                    activityId: nil,
                    address: nil,
                    notes: nil,
                    sessionId: row.id,
                    sessionDurationSeconds: durationSeconds
                )
            }
        }

        var query = client
            .from("session_analytics")
            .select()

        query = query.eq("user_id", value: userId.uuidString)
        if let workspaceId {
            query = query.eq("workspace_id", value: workspaceId.uuidString)
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
                    dueDate: nil,
                    kind: .session,
                    contactId: nil,
                    activityId: nil,
                    address: nil,
                    notes: nil,
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
                dueDate: nil,
                kind: .session,
                contactId: nil,
                activityId: nil,
                address: nil,
                notes: nil,
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

    func saveEditedItem(
        _ item: ActivityFeedItem,
        title: String,
        address: String,
        dueDate: Date,
        notes: String?
    ) async throws {
        guard let contactId = item.contactId else {
            throw NSError(domain: "ActivityFeedService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing contact for this item"])
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        try await updateContactSummary(
            contactId: contactId,
            title: trimmedTitle,
            address: trimmedAddress,
            reminderDate: item.kind == .followUp ? dueDate : nil,
            notes: normalizedNotes
        )

        guard item.kind == .appointment else { return }

        let appointmentNote = makeAppointmentNote(
            title: trimmedTitle.nilIfEmpty ?? "Appointment",
            start: dueDate,
            end: Calendar.current.date(byAdding: .hour, value: 1, to: dueDate) ?? dueDate,
            address: trimmedAddress,
            notes: normalizedNotes
        )

        if let activityId = item.activityId {
            try await updateAppointmentActivity(
                activityId: activityId,
                timestamp: dueDate,
                note: appointmentNote
            )
        } else {
            _ = try await ContactsService.shared.performRemoteLogActivity(
                contactID: contactId,
                type: .meeting,
                note: appointmentNote,
                timestamp: dueDate
            )
        }
    }

    private func fetchContactRows(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool,
        limit: Int
    ) async throws -> [ContactFeedRow] {
        let localRows = await fetchLocalContactRows(
            userId: userId,
            workspaceId: workspaceId,
            includeMembers: includeMembers
        )
        let decoder = JSONDecoder.supabaseDates
        do {
            var query = client
                .from("contacts")
                .select("id,user_id,full_name,address,status,notes,reminder_date,updated_at,created_at")
            query = query.eq("user_id", value: userId.uuidString)
            if let workspaceId {
                query = query.eq("workspace_id", value: workspaceId.uuidString)
            }
            let response = try await query
                .order("updated_at", ascending: false)
                .limit(limit)
                .execute()
            let contacts = try decoder.decode([ContactFeedRow].self, from: response.data)
            let mergedContacts = mergeContactRows(localRows + contacts, limit: limit)
            if !mergedContacts.isEmpty {
                return mergedContacts
            }
        } catch {
            if !localRows.isEmpty {
                return mergeContactRows(localRows, limit: limit)
            }
            // Fall through to legacy field_leads when contacts are unavailable.
        }

        var legacyQuery = client
            .from("field_leads")
            .select("id,user_id,name,address,status,updated_at,created_at")
        legacyQuery = legacyQuery.eq("user_id", value: userId.uuidString)
        if let workspaceId {
            legacyQuery = legacyQuery.eq("workspace_id", value: workspaceId.uuidString)
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
                notes: nil,
                reminderDate: nil,
                updatedAt: $0.updatedAt,
                createdAt: $0.createdAt
            )
        }
    }

    private func fetchLocalContactRows(
        userId: UUID,
        workspaceId: UUID?,
        includeMembers: Bool
    ) async -> [ContactFeedRow] {
        let contacts = await ContactRepository.shared.fetchContacts(
            userId: userId,
            workspaceId: workspaceId
        )
        return contacts.map(ContactFeedRow.init(contact:))
    }

    private func mergeContactRows(_ rows: [ContactFeedRow], limit: Int) -> [ContactFeedRow] {
        var rowsById: [UUID: ContactFeedRow] = [:]
        for row in rows {
            guard let existing = rowsById[row.id] else {
                rowsById[row.id] = row
                continue
            }
            if row.sortDate >= existing.sortDate {
                rowsById[row.id] = row
            }
        }
        return Array(rowsById.values)
            .sorted { $0.sortDate > $1.sortDate }
            .prefix(limit)
            .map { $0 }
    }

    private func fetchLocalAppointmentRows(
        contacts: [ContactFeedRow],
        limit: Int
    ) async -> [AppointmentActivityRow] {
        let contactsById = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
        let activities = await ContactRepository.shared.fetchActivities(
            contactIds: Array(contactsById.keys),
            type: .meeting,
            limit: limit
        )

        return activities.compactMap { activity in
            guard let contact = contactsById[activity.contactId] else { return nil }
            return AppointmentActivityRow(activity: activity, contact: contact)
        }
    }

    private func mergeAppointmentRows(_ rows: [AppointmentActivityRow], limit: Int) -> [AppointmentActivityRow] {
        var rowsByKey: [String: AppointmentActivityRow] = [:]
        for row in rows {
            let key = appointmentFingerprint(for: row)
            guard let existing = rowsByKey[key] else {
                rowsByKey[key] = row
                continue
            }
            if row.timestamp >= existing.timestamp {
                rowsByKey[key] = row
            }
        }

        return Array(rowsByKey.values)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    private func appointmentFingerprint(for row: AppointmentActivityRow) -> String {
        [
            row.contact.id.uuidString.lowercased(),
            String(Int(row.timestamp.timeIntervalSince1970.rounded())),
            row.note?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        ].joined(separator: "|")
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

        query = query.eq("contacts.user_id", value: userId.uuidString)
        if let workspaceId {
            query = query.eq("contacts.workspace_id", value: workspaceId.uuidString)
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

    private func updateContactSummary(
        contactId: UUID,
        title: String,
        address: String,
        reminderDate: Date?,
        notes: String?
    ) async throws {
        var updateData: [String: AnyCodable] = [
            "full_name": AnyCodable(title),
            "address": AnyCodable(address),
            "notes": AnyCodable(notes as Any),
            "updated_at": AnyCodable(Date())
        ]
        if let reminderDate {
            updateData["reminder_date"] = AnyCodable(reminderDate)
        }

        try await client
            .from("contacts")
            .update(updateData)
            .eq("id", value: contactId)
            .execute()
    }

    private func updateAppointmentActivity(
        activityId: UUID,
        timestamp: Date,
        note: String
    ) async throws {
        try await client
            .from("contact_activities")
            .update([
                "timestamp": AnyCodable(timestamp),
                "note": AnyCodable(note)
            ])
            .eq("id", value: activityId)
            .execute()
    }

    private func makeAppointmentNote(
        title: String,
        start: Date,
        end: Date,
        address: String,
        notes: String?
    ) -> String {
        var segments = [
            "Appointment",
            title,
            "Start: \(activityNoteDateFormatter.string(from: start))",
            "End: \(activityNoteDateFormatter.string(from: end))",
            "Address: \(address)"
        ]
        if let notes, !notes.isEmpty {
            segments.append(notes)
        }
        return segments.joined(separator: " | ")
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

    private var activityNoteDateFormatter: DateFormatter {
        Self._activityNoteDateFormatter
    }

    private static let _activityNoteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy h:mm a")
        return formatter
    }()
}

private struct ContactFeedRow: Decodable {
    let id: UUID
    let userId: UUID?
    let fullName: String?
    let address: String
    let status: String
    let notes: String?
    let reminderDate: Date?
    let updatedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fullName = "full_name"
        case address
        case status
        case notes
        case reminderDate = "reminder_date"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    init(
        id: UUID,
        userId: UUID?,
        fullName: String?,
        address: String,
        status: String,
        notes: String?,
        reminderDate: Date?,
        updatedAt: Date?,
        createdAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.fullName = fullName
        self.address = address
        self.status = status
        self.notes = notes
        self.reminderDate = reminderDate
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    init(contact: Contact) {
        self.init(
            id: contact.id,
            userId: nil,
            fullName: contact.fullName,
            address: contact.address,
            status: contact.status.rawValue,
            notes: contact.notes,
            reminderDate: contact.reminderDate,
            updatedAt: contact.updatedAt,
            createdAt: contact.createdAt
        )
    }

    var sortDate: Date {
        updatedAt ?? createdAt
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

    init(activity: ContactActivity, contact: ContactFeedRow) {
        self.id = activity.id
        self.contactId = activity.contactId
        self.note = activity.note
        self.timestamp = activity.timestamp
        self.createdAt = activity.createdAt
        self.contact = AppointmentContactRow(contact: contact)
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

    init(contact: ContactFeedRow) {
        self.id = contact.id
        self.fullName = contact.fullName
        self.address = contact.address
        self.userId = contact.userId
        self.workspaceId = nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
