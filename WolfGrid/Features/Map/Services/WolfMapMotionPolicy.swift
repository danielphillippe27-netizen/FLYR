import Foundation

/// Continuous motion while walking; four seconds of idle motion every 24 seconds.
struct WolfMapMotionPolicy {
    struct Schedule {
        let animated: Bool
        let nextUpdate: TimeInterval?
    }

    private var idleStartedAt: TimeInterval?

    mutating func reset() { idleStartedAt = nil }

    mutating func schedule(now: TimeInterval, speed: Double, constrained: Bool) -> Schedule {
        if constrained {
            reset()
            return Schedule(animated: false, nextUpdate: nil)
        }
        if speed >= 0.5 {
            reset()
            return Schedule(animated: true, nextUpdate: 1.0 / 30)
        }
        if idleStartedAt == nil || now - idleStartedAt! >= 24 {
            idleStartedAt = now
        }
        let elapsed = max(0, now - idleStartedAt!)
        if elapsed < 4 {
            return Schedule(animated: true, nextUpdate: 1.0 / 30)
        }
        return Schedule(animated: false, nextUpdate: 24 - elapsed)
    }
}
