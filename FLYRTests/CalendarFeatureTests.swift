import XCTest
import GRDB
@testable import FLYR

final class CalendarFeatureTests: XCTestCase {
    func testJune2026MonthGridStartsOnMondayAndContainsFortyTwoCells() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.firstWeekday = 2

        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
        let grid = FlyrCalendarDateHelpers.monthGrid(for: month, calendar: calendar)

        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(calendar.component(.month, from: grid[0].date), 6)
        XCTAssertEqual(calendar.component(.day, from: grid[0].date), 1)
        XCTAssertTrue(grid[0].isInDisplayedMonth)
        XCTAssertEqual(calendar.component(.day, from: grid[29].date), 30)
        XCTAssertTrue(grid[29].isInDisplayedMonth)
        XCTAssertEqual(calendar.component(.month, from: grid[30].date), 7)
        XCTAssertFalse(grid[30].isInDisplayedMonth)
    }

    func testCalendarItemSearchHaystackIncludesTitleNotesContactAndAddress() {
        let item = CalendarItem(
            id: "test",
            sourceId: UUID(),
            kind: .standalone,
            eventType: FlyrCalendarEventType.appointment.rawValue,
            title: "Listing Appointment",
            startAt: Date(timeIntervalSince1970: 0),
            endAt: Date(timeIntervalSince1970: 3600),
            isAllDay: false,
            notes: "Bring CMA packet",
            location: "123 Main Street",
            colorKey: "red",
            contactName: "Sarah Johnson",
            contactId: nil,
            address: "123 Main Street"
        )

        XCTAssertTrue(item.searchHaystack.contains("listing"))
        XCTAssertTrue(item.searchHaystack.contains("packet"))
        XCTAssertTrue(item.searchHaystack.contains("sarah"))
        XCTAssertTrue(item.searchHaystack.contains("main street"))
    }

    func testOverlappingEventsTileIntoColumns() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))
        let nine = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
        let nineThirty = try XCTUnwrap(calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day))
        let ten = try XCTUnwrap(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day))
        let eleven = try XCTUnwrap(calendar.date(bySettingHour: 11, minute: 0, second: 0, of: day))

        let items = [
            makeItem(id: "a", start: nine, end: ten),
            makeItem(id: "b", start: nineThirty, end: eleven),
            makeItem(id: "c", start: ten, end: eleven)
        ]

        let layouts = await CalendarEventLayoutCache.shared.layouts(for: day, items: items, calendar: calendar)

        XCTAssertEqual(layouts.count, 3)
        XCTAssertEqual(layouts.first { $0.id == "a" }?.column, 0)
        XCTAssertEqual(layouts.first { $0.id == "b" }?.column, 1)
        XCTAssertEqual(layouts.first { $0.id == "c" }?.column, 0)
        XCTAssertEqual(layouts.first { $0.id == "a" }?.columnCount, 2)
        XCTAssertEqual(layouts.first { $0.id == "b" }?.columnCount, 2)
    }

    func testTimelineSlotResolverUsesPressedDayAndSnapsToNearestQuarterHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))

        let slot = try XCTUnwrap(TimelineSlotResolver.date(
            for: CGPoint(x: 250, y: 514),
            timelineWidth: 374,
            gutterWidth: 74,
            hourHeight: 56,
            days: [firstDay, secondDay],
            calendar: calendar
        ))

        XCTAssertTrue(calendar.isDate(slot, inSameDayAs: secondDay))
        XCTAssertEqual(calendar.component(.hour, from: slot), 9)
        XCTAssertEqual(calendar.component(.minute, from: slot), 15)
    }

    func testFlyrCalendarEventPersistsTypeAndLinkedContactFields() {
        let contactId = UUID()
        let event = FlyrCalendarEvent(
            title: FlyrCalendarEventType.showing.defaultTitle(contactName: "Sarah Johnson"),
            startAt: Date(timeIntervalSince1970: 1_812_000_000),
            endAt: Date(timeIntervalSince1970: 1_812_003_600),
            eventType: FlyrCalendarEventType.showing.rawValue,
            contactId: contactId,
            contactName: "Sarah Johnson",
            contactAddress: "123 Main Street",
            sourceKind: CalendarEventSourceKind.contactAppointment.rawValue,
            sourceId: contactId,
            location: "123 Main Street",
            colorKey: CalendarColorKey.green.rawValue
        )

        XCTAssertEqual(event.eventType, FlyrCalendarEventType.showing.rawValue)
        XCTAssertEqual(event.contactId, contactId)
        XCTAssertEqual(event.contactName, "Sarah Johnson")
        XCTAssertEqual(event.contactAddress, "123 Main Street")
        XCTAssertEqual(event.sourceKind, CalendarEventSourceKind.contactAppointment.rawValue)
        XCTAssertEqual(event.sourceId, contactId)
        XCTAssertEqual(event.colorKey, CalendarColorKey.green.rawValue)
    }

    func testManualCalendarEventTypesAreLimitedToDoorKnockAndFlyerSchedule() {
        XCTAssertEqual(FlyrCalendarEventType.manualCreationTypes, [.doorKnock, .flyerSchedule])
        XCTAssertEqual(FlyrCalendarEventType.flyerSchedule.rawValue, "flyer_schedule")
        XCTAssertEqual(FlyrCalendarEventType.flyerSchedule.defaultColorKey, CalendarColorKey.blue.rawValue)
    }

    func testLinkedCalendarEventIdIsStableAndTypeScoped() {
        let contactId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let appointmentId = FlyrCalendarEvent.linkedId(
            sourceKind: CalendarEventSourceKind.contactAppointment.rawValue,
            sourceId: contactId,
            eventType: .appointment
        )
        let appointmentIdAgain = FlyrCalendarEvent.linkedId(
            sourceKind: CalendarEventSourceKind.contactAppointment.rawValue,
            sourceId: contactId,
            eventType: .appointment
        )
        let followUpId = FlyrCalendarEvent.linkedId(
            sourceKind: CalendarEventSourceKind.contactFollowUp.rawValue,
            sourceId: contactId,
            eventType: .followUp
        )

        XCTAssertEqual(appointmentId, appointmentIdAgain)
        XCTAssertNotEqual(appointmentId, followUpId)
    }

    func testExternalCalendarItemSourceIdIsStableAndSourceScoped() {
        let appleEventId = "A1B2C3"
        let appleId = CalendarItem.stableExternalSourceId(source: "apple_calendar", externalId: appleEventId)
        let appleIdAgain = CalendarItem.stableExternalSourceId(source: "apple_calendar", externalId: appleEventId)
        let otherSourceId = CalendarItem.stableExternalSourceId(source: "google_calendar", externalId: appleEventId)

        XCTAssertEqual(appleId, appleIdAgain)
        XCTAssertNotEqual(appleId, otherSourceId)
    }

    func testOfflineCalendarMigrationCreatesTypeAndContactColumns() throws {
        let dbQueue = try DatabaseQueue()
        var migrator = OfflineMigrations.migrator()
        try migrator.migrate(dbQueue)

        try dbQueue.read { db in
            let columnNames = Set(try db.columns(in: "cached_calendar_events").map(\.name))
            XCTAssertTrue(columnNames.contains("event_type"))
            XCTAssertTrue(columnNames.contains("contact_id"))
            XCTAssertTrue(columnNames.contains("contact_name"))
            XCTAssertTrue(columnNames.contains("contact_address"))
            XCTAssertTrue(columnNames.contains("source_kind"))
            XCTAssertTrue(columnNames.contains("source_id"))
        }
    }

    private func makeItem(id: String, start: Date, end: Date) -> CalendarItem {
        CalendarItem(
            id: id,
            sourceId: UUID(),
            kind: .standalone,
            eventType: FlyrCalendarEventType.appointment.rawValue,
            title: id,
            startAt: start,
            endAt: end,
            isAllDay: false,
            notes: nil,
            location: nil,
            colorKey: "red",
            contactName: nil,
            contactId: nil,
            address: nil
        )
    }
}
