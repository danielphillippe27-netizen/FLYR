import Foundation

@main
struct WolfMapMotionTests {
    static func main() {
        var policy = WolfMapMotionPolicy()
        assert(policy.schedule(now: 0, speed: 0, constrained: false).animated)
        let rest = policy.schedule(now: 4, speed: 0, constrained: false)
        assert(!rest.animated && rest.nextUpdate == 20)
        // Location/heading updates during a rest must not start another burst.
        let stillResting = policy.schedule(now: 12, speed: 0.1, constrained: false)
        assert(!stillResting.animated && stillResting.nextUpdate == 12)
        assert(policy.schedule(now: 24, speed: 0, constrained: false).animated)
        // Walking immediately interrupts rest and continues beyond the idle window.
        assert(policy.schedule(now: 28, speed: 0.5, constrained: false).animated)
        assert(policy.schedule(now: 60, speed: 3, constrained: false).animated)
        assert(policy.schedule(now: 61, speed: 0, constrained: false).animated)
        assert(!policy.schedule(now: 65, speed: 0, constrained: false).animated)
        // Power/accessibility/thermal constraints cancel all scheduled wakeups.
        for speed in [0.0, 1.0, 3.0] {
            let constrained = policy.schedule(now: 66, speed: speed, constrained: true)
            assert(!constrained.animated && constrained.nextUpdate == nil)
        }
        assert(policy.schedule(now: 70, speed: 0, constrained: false).animated)
        policy.reset()
        assert(policy.schedule(now: 100, speed: -1, constrained: false).animated)
        // A delayed wake starts a fresh burst rather than scheduling in the past.
        assert(policy.schedule(now: 200, speed: 0, constrained: false).animated)
        print("PASS: idle bursts, rest deadlines, walking, constraints, lifecycle reset, delayed wake")
    }
}
