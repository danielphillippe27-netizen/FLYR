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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
