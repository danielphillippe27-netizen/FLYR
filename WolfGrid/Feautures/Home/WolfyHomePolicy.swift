import Foundation

enum WolfyHomePolicy {
    /// Compares with completed calendar days; today remains available to work.
    static func weeklyPaceDelta(target: Int, completed: Int, now: Date, calendar: Calendar = .current) -> Int {
        let elapsedDays = 7 - remainingDays(now: now, calendar: calendar)
        return completed - Int(ceil(Double(max(0, target)) * Double(elapsedDays) / 7))
    }
    static func crossedMilestone(from old: Int, to new: Int, target: Int) -> Bool {
        guard target > 0, new > old else { return false }
        return min(4, max(0, new) * 4 / target) > min(4, max(0, old) * 4 / target)
    }
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
