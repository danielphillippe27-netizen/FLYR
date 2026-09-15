import Foundation

enum WolfyHomePolicy {
    static func weekStart(now: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }
    static func remainingDays(now: Date, calendar: Calendar = .current) -> Int {
        7 - (calendar.component(.weekday, from: now) + 5) % 7
    }
    static func pace(target: Int, completed: Int, days: Int) -> Int {
        Int(ceil(Double(max(0, target - completed)) / Double(max(1, days))))
    }
}

