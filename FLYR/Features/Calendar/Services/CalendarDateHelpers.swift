import Foundation

enum CalendarLevel: String {
    case year
    case month
    case day
}

enum MonthDisplayMode: String, CaseIterable, Identifiable {
    case compact
    case stacked
    case details
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .stacked: return "Stacked"
        case .details: return "Monthly"
        case .list: return "List"
        }
    }

    var symbol: String {
        switch self {
        case .compact: return "square.grid.2x2"
        case .stacked: return "rectangle.grid.1x2"
        case .details: return "list.bullet.below.rectangle"
        case .list: return "list.bullet"
        }
    }
}

enum DayDisplayMode: String, CaseIterable, Identifiable {
    case singleDay
    case multiDay
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .singleDay: return "Single Day"
        case .multiDay: return "Multi Day"
        case .list: return "List"
        }
    }

    var symbol: String {
        switch self {
        case .singleDay: return "rectangle.grid.1x2"
        case .multiDay: return "rectangle.split.3x1"
        case .list: return "list.bullet"
        }
    }
}

struct CalendarDayCell: Identifiable, Equatable {
    let id: Date
    let date: Date
    let isInDisplayedMonth: Bool
}

enum FlyrCalendarDateHelpers {
    static func configuredCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
    }

    static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func startOfYear(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func monthGrid(for month: Date, calendar: Calendar) -> [CalendarDayCell] {
        let monthStart = startOfMonth(for: month, calendar: calendar)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let firstWeekdayIndex = calendar.firstWeekday
        let leadingDays = (firstWeekday - firstWeekdayIndex + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let inMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            return CalendarDayCell(id: calendar.startOfDay(for: date), date: date, isInDisplayedMonth: inMonth)
        }
    }

    static func visibleRange(around date: Date, monthsBefore: Int = 3, monthsAfter: Int = 3, calendar: Calendar) -> (Date, Date) {
        let startMonth = calendar.date(byAdding: .month, value: -monthsBefore, to: startOfMonth(for: date, calendar: calendar)) ?? date
        let endMonth = calendar.date(byAdding: .month, value: monthsAfter + 1, to: startOfMonth(for: date, calendar: calendar)) ?? date
        return (startMonth, endMonth)
    }

    static func dayRange(for date: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }

    static func intersects(_ item: CalendarItem, start: Date, end: Date) -> Bool {
        item.endAt > start && item.startAt < end
    }

    static func intersects(_ event: FlyrCalendarEvent, start: Date, end: Date) -> Bool {
        event.endAt > start && event.startAt < end
    }
}
