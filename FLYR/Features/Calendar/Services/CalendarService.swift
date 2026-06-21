import Foundation
import Supabase

struct CalendarEventOutboxPayload: Codable, Sendable {
    let eventJSON: String
}

struct DeleteCalendarEventOutboxPayload: Codable, Sendable {
    let eventId: String
}

actor FlyrCalendarService {
    static let shared = FlyrCalendarService()

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private let eventRepository = CalendarEventRepository.shared
    private let contactRepository = ContactRepository.shared
    private let outboxRepository = OutboxRepository.shared
    private let appleCalendarDefaultsKey = "flyr.calendar.appleCalendarPullEnabled"

    private init() {}

    func isAppleCalendarPullEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: appleCalendarDefaultsKey)
    }

    func setAppleCalendarPullEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: appleCalendarDefaultsKey)
    }

    func appleCalendarAccessState() async -> AppleCalendarAccessState {
        await AppleCalendarService.shared.currentAccessState()
    }

    func requestAppleCalendarPull() async -> AppleCalendarAccessState {
        let state = await AppleCalendarService.shared.requestFullAccess()
        setAppleCalendarPullEnabled(state == .fullAccess)
        return state
    }

    func fetchCalendarItems(start: Date, end: Date) async -> [CalendarItem] {
        guard let userId = await MainActor.run(body: { AuthManager.shared.user?.id }) else {
            return []
        }
        let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId })

        async let standaloneEvents = fetchStandaloneEvents(userId: userId, workspaceId: workspaceId, start: start, end: end)
        async let contacts = fetchContacts(userId: userId, workspaceId: workspaceId)
        async let sessions = fetchSessionItems(userId: userId, workspaceId: workspaceId, start: start, end: end)
        async let appleCalendarItems = fetchAppleCalendarItemsIfEnabled(start: start, end: end)

        let resolvedEvents = await standaloneEvents
        let resolvedContacts = await contacts
        let sessionItems = await sessions
        let externalItems = await appleCalendarItems
        let contactItems = await makeContactItems(from: resolvedContacts, start: start, end: end)
        let standaloneItems = expandStandaloneEvents(resolvedEvents, start: start, end: end)
        let fallbackItems = contactItems.filter { !isLegacyContactItem($0, duplicatedBy: resolvedEvents) }
        return (standaloneItems + fallbackItems + sessionItems + externalItems)
            .sorted { lhs, rhs in
                if lhs.startAt == rhs.startAt { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                return lhs.startAt < rhs.startAt
            }
    }

    func createEvent(_ event: FlyrCalendarEvent) async throws -> FlyrCalendarEvent {
        let userId = await MainActor.run(body: { AuthManager.shared.user?.id })
        let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId })
        let saved = await eventRepository.upsertEventLocally(event, userId: userId, workspaceId: workspaceId)
        if let eventJSON = OfflineJSONCodec.encode(saved) {
            await outboxRepository.enqueue(
                entityType: "calendar_event",
                entityId: saved.id.uuidString,
                operation: .upsertCalendarEvent,
                payload: CalendarEventOutboxPayload(eventJSON: eventJSON),
                dependencyKey: "calendar_event:\(saved.id.uuidString.lowercased())"
            )
        }
        await scheduleSyncIfPossible()
        return saved
    }

    func updateEvent(
        from item: CalendarItem,
        title: String,
        location: String,
        startAt: Date,
        notes: String?
    ) async throws -> FlyrCalendarEvent {
        let existing = await eventRepository.fetchEvent(id: item.sourceId)
        let duration = max(15 * 60, item.endAt.timeIntervalSince(item.startAt))
        let endAt = startAt.addingTimeInterval(duration)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let eventType = FlyrCalendarEventType(rawValue: existing?.eventType ?? item.eventType) ?? .appointment
        let resolvedTitle = trimmedTitle.nilIfEmpty
            ?? existing?.title.nilIfEmpty
            ?? eventType.defaultTitle(contactName: existing?.contactName ?? item.contactName, campaignName: existing?.campaignName ?? item.campaignName)

        let updated = FlyrCalendarEvent(
            id: existing?.id ?? item.sourceId,
            userId: existing?.userId,
            workspaceId: existing?.workspaceId,
            title: resolvedTitle,
            startAt: startAt,
            endAt: endAt,
            isAllDay: existing?.isAllDay ?? item.isAllDay,
            eventType: existing?.eventType ?? item.eventType,
            contactId: existing?.contactId ?? item.contactId,
            contactName: existing?.contactName ?? item.contactName,
            contactAddress: trimmedLocation ?? existing?.contactAddress ?? item.address,
            campaignId: existing?.campaignId ?? item.campaignId,
            campaignName: existing?.campaignName ?? item.campaignName,
            recurrenceRule: existing?.recurrenceRule ?? CalendarRecurrenceRule.none.rawValue,
            recurrenceUntil: existing?.recurrenceUntil,
            sourceKind: existing?.sourceKind,
            sourceId: existing?.sourceId,
            notes: normalizedNotes,
            location: trimmedLocation ?? existing?.location ?? item.location,
            colorKey: existing?.colorKey ?? item.colorKey,
            createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date(),
            deletedAt: existing?.deletedAt
        )
        return try await createEvent(updated)
    }

    func deleteEvent(id: UUID) async throws {
        _ = await eventRepository.softDeleteEventLocally(id: id)
        await outboxRepository.enqueue(
            entityType: "calendar_event",
            entityId: id.uuidString,
            operation: .deleteCalendarEvent,
            payload: DeleteCalendarEventOutboxPayload(eventId: id.uuidString),
            dependencyKey: "calendar_event:\(id.uuidString.lowercased())"
        )
        await scheduleSyncIfPossible()
    }

    func performRemoteUpsertEvent(_ event: FlyrCalendarEvent) async throws -> FlyrCalendarEvent {
        var payload: [String: AnyCodable] = [
            "id": AnyCodable(event.id),
            "user_id": AnyCodable(event.userId as Any),
            "workspace_id": AnyCodable(event.workspaceId as Any),
            "title": AnyCodable(event.title),
            "start_at": AnyCodable(event.startAt),
            "end_at": AnyCodable(event.endAt),
            "is_all_day": AnyCodable(event.isAllDay),
            "event_type": AnyCodable(event.eventType),
            "contact_id": AnyCodable(event.contactId as Any),
            "contact_name": AnyCodable(event.contactName as Any),
            "contact_address": AnyCodable(event.contactAddress as Any),
            "campaign_id": AnyCodable(event.campaignId as Any),
            "campaign_name": AnyCodable(event.campaignName as Any),
            "recurrence_rule": AnyCodable(event.recurrenceRule),
            "recurrence_until": AnyCodable(event.recurrenceUntil as Any),
            "source_kind": AnyCodable(event.sourceKind as Any),
            "source_id": AnyCodable(event.sourceId as Any),
            "notes": AnyCodable(event.notes as Any),
            "location": AnyCodable(event.location as Any),
            "color_key": AnyCodable(event.colorKey),
            "updated_at": AnyCodable(event.updatedAt),
            "deleted_at": AnyCodable(event.deletedAt as Any)
        ]
        if event.createdAt.timeIntervalSince1970 > 0 {
            payload["created_at"] = AnyCodable(event.createdAt)
        }

        let response: [FlyrCalendarEvent] = try await client
            .from("calendar_events")
            .upsert(payload, onConflict: "id")
            .select()
            .execute()
            .value
        return response.first ?? event
    }

    func performRemoteDeleteEvent(id: UUID) async throws {
        try await client
            .from("calendar_events")
            .update(["deleted_at": AnyCodable(Date()), "updated_at": AnyCodable(Date())])
            .eq("id", value: id)
            .execute()
    }

    private func fetchStandaloneEvents(userId: UUID, workspaceId: UUID?, start: Date, end: Date) async -> [FlyrCalendarEvent] {
        if await isOffline() {
            return await eventRepository.fetchEvents(userId: userId, workspaceId: workspaceId, start: start, end: end)
        }

        do {
            var query = client
                .from("calendar_events")
                .select()
                .lt("start_at", value: OfflineDateCodec.string(from: end))
                .is("deleted_at", value: nil)

            if let workspaceId {
                query = query.or("workspace_id.eq.\(workspaceId.uuidString),and(user_id.eq.\(userId.uuidString),workspace_id.is.null)")
            } else {
                query = query.eq("user_id", value: userId)
            }

            let events: [FlyrCalendarEvent] = try await query
                .order("start_at", ascending: true)
                .execute()
                .value
            await eventRepository.upsertEvents(events, dirty: false, syncedAt: Date())
            return events
        } catch {
            return await eventRepository.fetchEvents(userId: userId, workspaceId: workspaceId, start: start, end: end)
        }
    }

    private func fetchAppleCalendarItemsIfEnabled(start: Date, end: Date) async -> [CalendarItem] {
        guard isAppleCalendarPullEnabled() else { return [] }
        let state = await AppleCalendarService.shared.currentAccessState()
        guard state == .fullAccess else {
            setAppleCalendarPullEnabled(false)
            return []
        }
        return await AppleCalendarService.shared.fetchItems(start: start, end: end)
    }

    private func fetchContacts(userId: UUID, workspaceId: UUID?) async -> [Contact] {
        do {
            return try await ContactsService.shared.fetchContacts(userID: userId, workspaceId: workspaceId)
        } catch {
            return await contactRepository.fetchContacts(userId: userId, workspaceId: workspaceId)
        }
    }

    private func fetchSessionItems(userId: UUID, workspaceId: UUID?, start: Date, end: Date) async -> [CalendarItem] {
        let recentLocalRows = await SessionRepository.shared.fetchRecentSessions(limit: 1000)
        let localRows = recentLocalRows.filter { session in
            session.user_id == userId && sessionIntersects(session, start: start, end: end)
        }

        let remoteRows: [SessionRecord]
        if await isOffline() {
            remoteRows = []
        } else {
            remoteRows = (try? await SessionsAPI.shared.fetchUserSessions(
                userId: userId,
                workspaceId: workspaceId,
                start: start,
                end: end,
                limit: 1000
            )) ?? []
        }

        let mergedRows = mergeSessions(remoteRows + localRows)
        return mergedRows.compactMap { CalendarItem(session: $0) }
    }

    private func makeContactItems(from contacts: [Contact], start: Date, end: Date) async -> [CalendarItem] {
        let reminders = contacts.compactMap { contact -> CalendarItem? in
            guard let reminderDate = contact.followUpAt ?? contact.reminderDate else { return nil }
            let itemEnd = Calendar.current.date(byAdding: .minute, value: 30, to: reminderDate) ?? reminderDate
            guard itemEnd > start && reminderDate < end else { return nil }
            return CalendarItem(
                id: "reminder-\(contact.id.uuidString)",
                sourceId: contact.id,
                kind: .reminder,
                eventType: FlyrCalendarEventType.followUp.rawValue,
                title: "Follow up: \(contact.fullName)",
                startAt: reminderDate,
                endAt: itemEnd,
                isAllDay: false,
                notes: contact.notes,
                location: contact.address,
                colorKey: "yellow",
                contactName: contact.fullName,
                contactId: contact.id,
                campaignName: nil,
                campaignId: nil,
                address: contact.address
            )
        }

        let contactIds = contacts.map(\.id)
        let activities: [ContactActivity]
        if let remoteActivities = try? await ContactsService.shared.fetchActivities(contactIDs: contactIds, type: .meeting, limit: 500) {
            activities = remoteActivities
        } else {
            activities = await contactRepository.fetchActivities(contactIds: contactIds, type: .meeting, limit: 500)
        }
        let contactsById = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
        let meetings = activities.compactMap { activity -> CalendarItem? in
            let itemEnd = Calendar.current.date(byAdding: .hour, value: 1, to: activity.timestamp) ?? activity.timestamp
            guard itemEnd > start && activity.timestamp < end else { return nil }
            let contact = contactsById[activity.contactId]
            return CalendarItem(
                id: "meeting-\(activity.id.uuidString)",
                sourceId: activity.id,
                kind: .meeting,
                eventType: FlyrCalendarEventType.appointment.rawValue,
                title: meetingTitle(from: activity.note, fallback: contact?.fullName),
                startAt: activity.timestamp,
                endAt: itemEnd,
                isAllDay: false,
                notes: activity.note,
                location: contact?.address,
                colorKey: "yellow",
                contactName: contact?.fullName,
                contactId: activity.contactId,
                campaignName: nil,
                campaignId: nil,
                address: contact?.address
            )
        }

        return reminders + meetings
    }

    private func expandStandaloneEvents(_ events: [FlyrCalendarEvent], start: Date, end: Date) -> [CalendarItem] {
        let calendar = FlyrCalendarDateHelpers.configuredCalendar()
        return events.flatMap { event -> [CalendarItem] in
            let rule = CalendarRecurrenceRule(rawValue: event.recurrenceRule) ?? .none
            guard rule != .none, let component = rule.component else {
                return FlyrCalendarDateHelpers.intersects(event, start: start, end: end) ? [CalendarItem(event: event)] : []
            }

            let duration = max(60, event.endAt.timeIntervalSince(event.startAt))
            let recurrenceEnd = min(event.recurrenceUntil ?? end, end)
            guard event.startAt < end, recurrenceEnd >= start else { return [] }

            var occurrences: [CalendarItem] = []
            var occurrenceStart = event.startAt
            var safetyCounter = 0

            while occurrenceStart < end, safetyCounter < 1000 {
                let occurrenceEnd = occurrenceStart.addingTimeInterval(duration)
                if occurrenceEnd > start && occurrenceStart < end {
                    occurrences.append(makeOccurrenceItem(event: event, start: occurrenceStart, end: occurrenceEnd, calendar: calendar))
                }

                guard let next = calendar.date(byAdding: component, value: 1, to: occurrenceStart),
                      next > occurrenceStart else { break }
                occurrenceStart = next
                safetyCounter += 1
                if occurrenceStart > recurrenceEnd { break }
            }

            return occurrences
        }
    }

    private func makeOccurrenceItem(event: FlyrCalendarEvent, start: Date, end: Date, calendar: Calendar) -> CalendarItem {
        CalendarItem(
            id: "event-\(event.id.uuidString)-\(dayKey(start, calendar: calendar))",
            sourceId: event.id,
            kind: .standalone,
            eventType: event.eventType,
            title: event.title,
            startAt: start,
            endAt: end,
            isAllDay: event.isAllDay,
            notes: event.notes,
            location: event.location,
            colorKey: event.colorKey,
            contactName: event.contactName,
            contactId: event.contactId,
            campaignName: event.campaignName,
            campaignId: event.campaignId,
            address: event.contactAddress ?? event.location
        )
    }

    private func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }

    private func isLegacyContactItem(_ item: CalendarItem, duplicatedBy events: [FlyrCalendarEvent]) -> Bool {
        guard item.kind == .reminder || item.kind == .meeting else { return false }
        guard let itemContactId = item.contactId else { return false }

        return events.contains { event in
            guard event.deletedAt == nil, event.eventType == item.eventType else { return false }
            let eventContactId = event.contactId ?? event.sourceId
            guard eventContactId == itemContactId else { return false }

            switch item.kind {
            case .reminder:
                return abs(event.startAt.timeIntervalSince(item.startAt)) <= 30 * 60
            case .meeting:
                if abs(event.startAt.timeIntervalSince(item.startAt)) <= 60 * 60 {
                    return true
                }
                let note = item.notes ?? ""
                return note.range(of: "Appointment", options: .caseInsensitive) != nil
                    || note.range(of: "Starts:", options: .caseInsensitive) != nil
                    || note.range(of: "Start:", options: .caseInsensitive) != nil
            case .standalone:
                return false
            case .session:
                return false
            case .appleCalendar:
                return false
            }
        }
    }

    private func mergeSessions(_ sessions: [SessionRecord]) -> [SessionRecord] {
        var seen = Set<String>()
        var merged: [SessionRecord] = []
        for session in sessions {
            let key = session.id?.uuidString ?? "\(session.user_id.uuidString)-\(session.start_time.timeIntervalSince1970)"
            guard seen.insert(key).inserted else { continue }
            merged.append(session)
        }
        return merged.sorted { $0.start_time < $1.start_time }
    }

    private func sessionIntersects(_ session: SessionRecord, start: Date, end: Date) -> Bool {
        let duration = max(60, session.durationSeconds)
        let sessionEnd = session.end_time ?? session.start_time.addingTimeInterval(duration)
        return session.start_time < end && sessionEnd > start
    }

    private func meetingTitle(from note: String?, fallback: String?) -> String {
        guard let note else {
            return fallback.map { "Meeting: \($0)" } ?? "Meeting"
        }
        let pieces = note
            .replacingOccurrences(of: "Appointment | ", with: "")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return pieces.first(where: { !$0.hasPrefix("Start:") && !$0.hasPrefix("End:") && !$0.hasPrefix("Address:") })
            ?? fallback.map { "Meeting: \($0)" }
            ?? "Meeting"
    }

    private func isOffline() async -> Bool {
        await MainActor.run { !NetworkMonitor.shared.isOnline }
    }

    private func scheduleSyncIfPossible() async {
        let shouldSchedule = await MainActor.run { NetworkMonitor.shared.isOnline }
        guard shouldSchedule else { return }
        await MainActor.run {
            OfflineSyncCoordinator.shared.scheduleProcessOutbox()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
