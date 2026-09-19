import Foundation

@main struct WolfyHomePolicyTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        let iso = ISO8601DateFormatter()
        let monday = iso.date(from: "2026-09-14T04:00:00Z")!
        let sunday = iso.date(from: "2026-09-21T03:59:59Z")!
        assert(WolfyHomePolicy.weekStart(now: monday, calendar: calendar) == monday)
        assert(WolfyHomePolicy.weekStart(now: sunday, calendar: calendar) == monday)
        assert(WolfyHomePolicy.remainingDays(now: monday, calendar: calendar) == 7)
        assert(WolfyHomePolicy.remainingDays(now: sunday, calendar: calendar) == 1)
        let nextMonday = iso.date(from: "2026-09-21T04:00:00Z")!
        assert(WolfyHomePolicy.weekStart(now: nextMonday, calendar: calendar) == nextMonday)
        assert(WolfyHomePolicy.pace(target: 500, completed: 212, days: 3) == 96)
        assert(WolfyHomePolicy.pace(target: 500, completed: 500, days: 1) == 0)
        assert(WolfyHomePolicy.pace(target: 500, completed: 501, days: 1) == 0)
        assert(WolfyHomePolicy.pace(target: 100, completed: 0, days: 7) == 15)
        let dstSunday = iso.date(from: "2026-03-08T16:00:00Z")!
        assert(WolfyHomePolicy.weekStart(now: dstSunday, calendar: calendar) == iso.date(from: "2026-03-02T05:00:00Z")!)
        assert(WolfyHomePolicy.crossedMilestone(from: 18, to: 19, target: 75))
        assert(!WolfyHomePolicy.crossedMilestone(from: 19, to: 20, target: 75))
        assert(WolfyHomePolicy.crossedMilestone(from: 74, to: 75, target: 75))
        assert(!WolfyHomePolicy.crossedMilestone(from: 75, to: 80, target: 75))
        assert(!WolfyHomePolicy.crossedMilestone(from: 1, to: 2, target: 0))
        assert(!WolfyHomePolicy.crossedMilestone(from: 30, to: 20, target: 75))
        assert(WolfyHomePolicy.weeklyPaceDelta(target: 700, completed: 0, now: monday, calendar: calendar) == 0)
        assert(WolfyHomePolicy.weeklyPaceDelta(target: 700, completed: 550, now: sunday, calendar: calendar) == -50)
        print("PASS: Monday/Sunday/midnight/DST boundaries and goal pace")
    }
}
