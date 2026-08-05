import Foundation
import CoreGraphics

struct CalendarTimedEventLayout: Identifiable, Equatable {
    let id: String
    let item: CalendarItem
    let column: Int
    let columnCount: Int
    let startMinute: Int
    let durationMinutes: Int
}

actor CalendarEventLayoutCache {
    static let shared = CalendarEventLayoutCache()

    private var cache: [String: [CalendarTimedEventLayout]] = [:]

    func layouts(for day: Date, items: [CalendarItem], calendar: Calendar) async -> [CalendarTimedEventLayout] {
        let key = cacheKey(day: day, items: items, calendar: calendar)
        if let cached = cache[key] {
            return cached
        }

        let layouts = Self.computeLayouts(for: day, items: items, calendar: calendar)
        cache[key] = layouts
        return layouts
    }

    private func cacheKey(day: Date, items: [CalendarItem], calendar: Calendar) -> String {
        let dayKey = ISO8601DateFormatter().string(from: calendar.startOfDay(for: day))
        let itemKey = items
            .map { "\($0.id)-\($0.startAt.timeIntervalSince1970)-\($0.endAt.timeIntervalSince1970)" }
            .joined(separator: "|")
        return "\(dayKey):\(itemKey)"
    }

    private static func computeLayouts(for day: Date, items: [CalendarItem], calendar: Calendar) -> [CalendarTimedEventLayout] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let timed = items
            .filter { !$0.isAllDay && FlyrCalendarDateHelpers.intersects($0, start: dayStart, end: dayEnd) }
            .sorted { lhs, rhs in
                if lhs.startAt == rhs.startAt { return lhs.endAt < rhs.endAt }
                return lhs.startAt < rhs.startAt
            }

        var active: [(item: CalendarItem, column: Int)] = []
        var results: [(item: CalendarItem, column: Int, group: Int)] = []
        var groupIndex = 0
        var groupMaxColumn: [Int: Int] = [:]

        for item in timed {
            active.removeAll { $0.item.endAt <= item.startAt }
            if active.isEmpty, !results.isEmpty {
                groupIndex += 1
            }
            let used = Set(active.map(\.column))
            var column = 0
            while used.contains(column) {
                column += 1
            }
            active.append((item, column))
            results.append((item, column, groupIndex))
            groupMaxColumn[groupIndex] = max(groupMaxColumn[groupIndex] ?? 0, column)
        }

        return results.map { entry in
            let clippedStart = max(entry.item.startAt, dayStart)
            let clippedEnd = min(entry.item.endAt, dayEnd)
            let startMinute = max(0, calendar.dateComponents([.minute], from: dayStart, to: clippedStart).minute ?? 0)
            let duration = max(15, calendar.dateComponents([.minute], from: clippedStart, to: clippedEnd).minute ?? 30)
            return CalendarTimedEventLayout(
                id: entry.item.id,
                item: entry.item,
                column: entry.column,
                columnCount: (groupMaxColumn[entry.group] ?? 0) + 1,
                startMinute: startMinute,
                durationMinutes: duration
            )
        }
    }
}

