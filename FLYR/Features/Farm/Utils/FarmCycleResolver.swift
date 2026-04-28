import Foundation

enum FarmCycleResolver {
    struct ResolvedTouch {
        let touch: FarmTouch
        let cycleNumber: Int
    }

    struct CycleWindow {
        let cycleNumber: Int
        let startDate: Date
        let endDate: Date
    }

    static func effectiveDate(for touch: FarmTouch) -> Date {
        touch.date
    }

    static func resolveCycleNumber(
        for touch: FarmTouch,
        among touches: [FarmTouch],
        touchesPerInterval: Int
    ) -> Int {
        let resolved = resolveTouches(touches, touchesPerInterval: touchesPerInterval)
        return resolved.first(where: { $0.touch.id == touch.id })?.cycleNumber ?? max(1, touch.cycleNumber ?? 1)
    }

    static func resolveTouches(
        _ touches: [FarmTouch],
        touchesPerInterval: Int
    ) -> [ResolvedTouch] {
        _ = touchesPerInterval
        let ordered = touches.sorted { lhs, rhs in
            let lhsDate = effectiveDate(for: lhs)
            let rhsDate = effectiveDate(for: rhs)
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var cycleById: [UUID: Int] = [:]
        for (index, touch) in ordered.enumerated() {
            let fallback = index + 1
            cycleById[touch.id] = max(1, touch.cycleNumber ?? fallback)
        }

        return touches.map { touch in
            ResolvedTouch(
                touch: touch,
                cycleNumber: cycleById[touch.id] ?? max(1, touch.cycleNumber ?? 1)
            )
        }
    }

    static func nextCycleNumber(
        existingTouches: [FarmTouch],
        touchesPerInterval: Int
    ) -> Int {
        _ = touchesPerInterval
        let resolved = resolveTouches(existingTouches, touchesPerInterval: touchesPerInterval)
        guard !resolved.isEmpty else { return 1 }

        let currentCycle = resolved.map(\.cycleNumber).max() ?? 1
        return currentCycle + 1
    }

    static func buildCycles(
        farm: Farm,
        touches: [FarmTouch]
    ) -> [FarmCycle] {
        let cycleWindows = generateCycleWindows(for: farm)
        guard !cycleWindows.isEmpty else { return [] }

        let resolvedTouches = resolveTouches(
            touches,
            touchesPerInterval: max(1, farm.touchesPerInterval ?? farm.frequency)
        )
        let touchesByCycle = Dictionary(grouping: resolvedTouches, by: \.cycleNumber)

        return cycleWindows.map { window in
            let bucket = touchesByCycle[window.cycleNumber] ?? []
            let completedTouchCount = bucket.filter(\.touch.completed).count
            let cycleTouches = bucket.map(\.touch)
            let plannedSessionCount = cycleTouches.count
            let executedSessionCount = completedSessionCount(for: cycleTouches)
            let doorsHitCount = totalDoorsHit(for: cycleTouches)
            let results: [String: AnyCodable] = [
                "planned_touches": AnyCodable(bucket.count),
                "completed_touches": AnyCodable(completedTouchCount),
                "planned_sessions": AnyCodable(plannedSessionCount),
                "sessions_count": AnyCodable(executedSessionCount),
                "doors_hit": AnyCodable(doorsHitCount),
                "flyers_delivered": AnyCodable(bucket.filter { $0.touch.type == .flyer && $0.touch.completed }.count),
                "knocks": AnyCodable(bucket.filter { $0.touch.type == .doorKnock && $0.touch.completed }.count)
            ]

            return FarmCycle(
                farmId: farm.id,
                cycleNumber: window.cycleNumber,
                startDate: window.startDate,
                endDate: window.endDate,
                touchCount: bucket.count,
                completedTouchCount: completedTouchCount,
                results: results
            )
        }
    }

    private static func completedSessionCount(for touches: [FarmTouch]) -> Int {
        let completedTouches = touches.filter(\.completed)
        let uniqueSessionIds = Set(completedTouches.compactMap(\.sessionId))
        let standaloneCompletedTouches = completedTouches.filter { $0.sessionId == nil }.count
        return uniqueSessionIds.count + standaloneCompletedTouches
    }

    private static func totalDoorsHit(for touches: [FarmTouch]) -> Int {
        let completedTouches = touches.filter(\.completed)
        var doorsBySessionId: [UUID: Int] = [:]
        var standaloneDoors = 0

        for touch in completedTouches {
            let doorsHit = intMetric(named: "doors_hit", in: touch)
                ?? intMetric(named: "flyers_delivered", in: touch)
                ?? 0

            if let sessionId = touch.sessionId {
                doorsBySessionId[sessionId] = max(doorsBySessionId[sessionId] ?? 0, doorsHit)
            } else {
                standaloneDoors += doorsHit
            }
        }

        return standaloneDoors + doorsBySessionId.values.reduce(0, +)
    }

    private static func intMetric(named key: String, in touch: FarmTouch) -> Int? {
        guard let value = touch.executionMetrics?[key]?.value else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func generateCycleWindows(for farm: Farm) -> [CycleWindow] {
        let calendar = Calendar.current
        let interval = (farm.touchesInterval ?? "month").lowercased()

        let component: Calendar.Component
        let step: Int

        switch interval {
        case "week", "weeks":
            component = .weekOfYear
            step = 1
        case "day", "days":
            component = .day
            step = max(1, farm.frequency)
        case "quarter", "quarters":
            component = .month
            step = 3
        case "year", "years":
            component = .year
            step = 1
        default:
            component = .month
            step = 1
        }

        var windows: [CycleWindow] = []
        var cycleStart = farm.startDate
        var cycleNumber = 1

        while cycleStart < farm.endDate {
            let proposedEnd = calendar.date(byAdding: component, value: step, to: cycleStart) ?? farm.endDate
            let cycleEnd = min(proposedEnd, farm.endDate)

            windows.append(
                CycleWindow(
                    cycleNumber: cycleNumber,
                    startDate: cycleStart,
                    endDate: cycleEnd
                )
            )

            guard cycleEnd > cycleStart else { break }
            cycleStart = cycleEnd
            cycleNumber += 1
        }

        if windows.isEmpty {
            windows.append(
                CycleWindow(
                    cycleNumber: 1,
                    startDate: farm.startDate,
                    endDate: farm.endDate
                )
            )
        }

        return windows
    }
}
