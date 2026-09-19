import EventKit
import Foundation

enum AppleCalendarAccessState: Equatable, Sendable {
    case notDetermined
    case fullAccess
    case writeOnly
    case denied
    case restricted
    case unavailable
}

actor AppleCalendarService {
    static let shared = AppleCalendarService()

    private let eventStore = EKEventStore()

    private init() {}

    func currentAccessState() -> AppleCalendarAccessState {
        accessState(for: EKEventStore.authorizationStatus(for: .event))
    }

    func requestFullAccess() async -> AppleCalendarAccessState {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch accessState(for: status) {
        case .fullAccess:
            return .fullAccess
        case .notDetermined:
            do {
                let granted = try await requestFullAccessToEvents()
                return granted ? .fullAccess : accessState(for: EKEventStore.authorizationStatus(for: .event))
            } catch {
                return accessState(for: EKEventStore.authorizationStatus(for: .event))
            }
        case .writeOnly, .denied, .restricted, .unavailable:
            return accessState(for: status)
        }
    }

    func addMeeting(
        title: String,
        startAt: Date,
        endAt: Date,
        notes: String?,
        joinURL: URL
    ) async throws {
        let access = try await requestWriteAccess()
        guard access == .fullAccess || access == .writeOnly else {
            throw AppleCalendarWriteError.accessDenied
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw AppleCalendarWriteError.noWritableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startAt
        event.endDate = max(endAt, startAt.addingTimeInterval(60))
        event.location = "Zoom"
        event.url = joinURL
        event.notes = [notes?.trimmingCharacters(in: .whitespacesAndNewlines), "Join Zoom: \(joinURL.absoluteString)"]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")
        event.addAlarm(EKAlarm(relativeOffset: -10 * 60))
        try eventStore.save(event, span: .thisEvent, commit: true)
    }

    #if !WOLFGRID_SALES
    func fetchItems(start: Date, end: Date) async -> [CalendarItem] {
        guard currentAccessState() == .fullAccess else { return [] }

        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate)
            .map(makeCalendarItem)
            .filter { FlyrCalendarDateHelpers.intersects($0, start: start, end: end) }
            .sorted { lhs, rhs in
                if lhs.startAt == rhs.startAt {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.startAt < rhs.startAt
            }
    }

    #endif

    private func requestFullAccessToEvents() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestWriteAccess() async throws -> AppleCalendarAccessState {
        let current = accessState(for: EKEventStore.authorizationStatus(for: .event))
        switch current {
        case .fullAccess, .writeOnly:
            return current
        case .notDetermined:
            let granted: Bool = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                eventStore.requestWriteOnlyAccessToEvents { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
            return granted ? .writeOnly : accessState(for: EKEventStore.authorizationStatus(for: .event))
        case .denied, .restricted, .unavailable:
            return current
        }
    }

    #if !WOLFGRID_SALES
    private func makeCalendarItem(from event: EKEvent) -> CalendarItem {
        let externalId = event.eventIdentifier ?? "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)"
        let calendarName = event.calendar.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)

        return CalendarItem(
            id: "apple-calendar-\(externalId)",
            sourceId: CalendarItem.stableExternalSourceId(source: "apple_calendar", externalId: externalId),
            kind: .appleCalendar,
            eventType: FlyrCalendarEventType.personal.rawValue,
            title: event.title?.nilIfEmpty ?? "Apple Calendar Event",
            startAt: event.startDate,
            endAt: max(event.endDate, event.startDate.addingTimeInterval(60)),
            isAllDay: event.isAllDay,
            notes: notes?.nilIfEmpty,
            location: location?.nilIfEmpty,
            colorKey: CalendarColorKey.gray.rawValue,
            contactName: nil,
            contactId: nil,
            campaignName: calendarName.nilIfEmpty,
            campaignId: nil,
            address: location?.nilIfEmpty ?? calendarName.nilIfEmpty
        )
    }

    #endif

    private func accessState(for status: EKAuthorizationStatus) -> AppleCalendarAccessState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .fullAccess
        case .fullAccess:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .unavailable
        }
    }
}

private enum AppleCalendarWriteError: LocalizedError {
    case accessDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Allow WolfGrid to add events in Settings to use Apple Calendar."
        case .noWritableCalendar:
            return "No writable Apple Calendar is available on this device."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
