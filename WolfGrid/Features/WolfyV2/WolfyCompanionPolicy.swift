import Foundation

/// Platform-independent rules shared by the personal character and remote Pack presentation.
/// Business rewards are authoritative on the server; these defaults are only presentation fallback.
enum WolfyStage: Int, Codable, CaseIterable {
    case pup = 1, young, street, alpha, legend
    var title: String { ["Wolf Pup", "Young Wolf", "Street Wolf", "Alpha", "Grid Legend"][rawValue - 1] }
}
struct WolfyRulesV2: Codable, Equatable {
    let version: Int
    let thresholds: [Int]
    let rewards: [String: Int]
    static let initial = WolfyRulesV2(version: 2, thresholds: [0, 2500, 12000, 40000, 100000], rewards: [
        "door": 2, "conversation": 5, "follow_up": 10, "lead": 25, "appointment": 75,
        "verified_sale": 200, "doors_10": 20, "doors_25": 50, "doors_50": 100,
        "daily_goal": 150, "personal_best": 250
    ])
    var isValid: Bool {
        version >= 2 && thresholds.count == 5 && thresholds.first == 0 &&
        zip(thresholds, thresholds.dropFirst()).allSatisfy { $0 < $1 } && rewards.values.allSatisfy { $0 >= 0 }
    }
    func stage(xp: Int) -> WolfyStage {
        let values = isValid ? thresholds : Self.initial.thresholds
        return WolfyStage(rawValue: values.filter { max(0,xp) >= $0 }.count) ?? .pup
    }
    func remaining(xp: Int) -> Int? {
        let values = isValid ? thresholds : Self.initial.thresholds
        return values.first(where: { $0 > max(0,xp) }).map { $0 - max(0,xp) }
    }
}
enum WolfyGait: String, Codable { case idle, walk, trot, run, catchUp }
enum WolfyPosture: String, Codable { case standing, sitting, lying, stretching }
enum WolfyActivityV2: String, Codable { case moving, idle, atDoor, conversation, paused, ended }
enum WolfyHapticMode: String, Codable, CaseIterable { case off, subtle, full }
enum WolfySoundMode: String, Codable, CaseIterable { case off, hapticsOnly, full }
struct WolfyReactionV2: Codable, Equatable, Identifiable {
    let id: String
    let kind: String
    let occurredAt: Date
    let expiresAt: Date
    let duration: TimeInterval
    var priority: Int {
        switch kind {
        case "campaign_complete", "pack_goal": 110
        case "evolution", "personal_best": 100
        case "verified_sale": 90
        case "appointment": 80
        case "doors_50", "doors_25", "conversations_25", "pack_milestone": 70
        case "daily_goal": 60
        case "lead": 50
        case "follow_up": 45
        case "conversation": 40
        case "door": 20
        default: 30
        }
    }
    var major: Bool { priority >= 60 }
}
struct WolfyBehaviorV2 {
    private(set) var gait: WolfyGait = .idle
    private(set) var posture: WolfyPosture = .standing
    private(set) var reaction: WolfyReactionV2?
    private(set) var pendingMajor: WolfyReactionV2?
    private var reactionEnds = Date.distantPast
    private var seen: [String: Date] = [:]
    private var previousClip: [String: String] = [:]

    mutating func update(speed: Double, distanceBehind: Double, inactiveFor: TimeInterval,
                         activity: WolfyActivityV2, now: Date) {
        let moving = activity == .moving && speed.isFinite && speed >= 0.35
        if activity == .paused || activity == .ended { gait = .idle; posture = .sitting }
        else if moving {
            gait = distanceBehind > 20 ? .catchUp : speed > 3 ? .run : speed > 1.6 ? .trot : .walk
            posture = .standing
        } else {
            gait = .idle
            if activity == .atDoor || activity == .conversation { posture = .standing }
            else { posture = inactiveFor >= 900 && inactiveFor < 905 ? .stretching : inactiveFor >= 600 ? .lying : inactiveFor >= 300 ? .sitting : .standing }
        }
        seen = seen.filter { $0.value > now }
        if now >= reactionEnds || reaction.map({ $0.expiresAt <= now }) == true {
            reaction = nil
            if let pending = pendingMajor, pending.expiresAt > now { start(pending, now: now) }
            pendingMajor = nil
        }
    }
    @discardableResult mutating func request(_ event: WolfyReactionV2, now: Date) -> Bool {
        guard event.expiresAt > now, event.occurredAt <= now.addingTimeInterval(5), seen[event.id] == nil else { return false }
        seen[event.id] = max(event.expiresAt, now.addingTimeInterval(180))
        if seen.count > 256, let oldest = seen.min(by: { $0.value < $1.value })?.key { seen.removeValue(forKey: oldest) }
        if let active = reaction, now < reactionEnds, event.priority <= active.priority {
            if event.major && event.priority >= (pendingMajor?.priority ?? 0) { pendingMajor = event }
            return false
        }
        start(event, now: now); return true
    }
    private mutating func start(_ event: WolfyReactionV2, now: Date) {
        reaction = event
        reactionEnds = min(event.expiresAt, now.addingTimeInterval(max(0.1, min(4, event.duration))))
    }
    mutating func clip(pool: String, candidates: [String], randomIndex: Int) -> String? {
        let unique = Array(Set(candidates)).sorted()
        let alternatives = unique.filter { $0 != previousClip[pool] }
        let choices = alternatives.isEmpty ? unique : alternatives
        guard !choices.isEmpty else { return nil }
        let selected = choices[Int(randomIndex.magnitude % UInt(choices.count))]
        previousClip[pool] = selected; return selected
    }
    mutating func resume() { reaction = nil; pendingMajor = nil; reactionEnds = .distantPast }
}

struct WolfyPackFixV2: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let heading: Double?
    let speed: Double
    let fixedAt: Date
    let sequence: Int64
    var valid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
        accuracy.isFinite && accuracy >= 0 && accuracy <= 50 && speed.isFinite && speed >= 0 && speed <= 12 &&
        (heading == nil || (heading!.isFinite && (0..<360).contains(heading!))) && sequence >= 0
    }
    func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let a = sin((other.latitude-latitude)*radians/2)
        let b = sin((other.longitude-longitude)*radians/2)
        let h = a*a + cos(latitude*radians)*cos(other.latitude*radians)*b*b
        return 6371000 * 2 * atan2(sqrt(max(0,min(1,h))),sqrt(max(0,1-h)))
    }
}
enum WolfyPackFreshnessV2: Equatable { case live, stale, hidden }
struct WolfyPackPresencePolicyV2 {
    static func freshness(fix: WolfyPackFixV2?, permitted: Bool, activeSession: Bool, now: Date) -> WolfyPackFreshnessV2 {
        guard permitted, activeSession, let fix, fix.valid else { return .hidden }
        let age = now.timeIntervalSince(fix.fixedAt)
        guard age >= -5, age < 180 else { return .hidden }
        return age >= 60 ? .stale : .live
    }
    static func accepts(_ next: WolfyPackFixV2, previous: WolfyPackFixV2?, now: Date) -> Bool {
        guard next.valid, next.fixedAt <= now.addingTimeInterval(5), now.timeIntervalSince(next.fixedAt) < 180 else { return false }
        guard let previous else { return true }
        let elapsed = next.fixedAt.timeIntervalSince(previous.fixedAt)
        guard next.sequence > previous.sequence, elapsed > 0 else { return false }
        return previous.distance(to: next) <= 12 * elapsed + min(50,previous.accuracy + next.accuracy)
    }
    static func shouldPublish(now: Date, lastSent: Date?, moving: Bool, eligibilityChanged: Bool) -> Bool {
        if eligibilityChanged || lastSent == nil { return true }
        return now.timeIntervalSince(lastSent!) >= (moving ? 5 : 30)
    }
    static func nearby(_ a: WolfyPackFixV2?, _ b: WolfyPackFixV2?, now: Date) -> Bool {
        guard freshness(fix:a,permitted:true,activeSession:true,now:now) == .live,
              freshness(fix:b,permitted:true,activeSession:true,now:now) == .live,
              let a, let b else { return false }
        return a.distance(to:b) <= 250
    }
}
struct WolfyPackPresentationBudgetV2 {
    private var lastBanner: Date?
    private var lastHaptic: Date?
    mutating func banner(now: Date) -> Bool {
        guard lastBanner.map({now.timeIntervalSince($0) >= 30}) ?? true else { return false }
        lastBanner = now; return true
    }
    mutating func haptic(now: Date, personalMode: WolfyHapticMode, teamEnabled: Bool, foreground: Bool, personalFeedbackActive: Bool) -> Bool {
        guard personalMode != .off, teamEnabled, foreground, !personalFeedbackActive,
              lastHaptic.map({now.timeIntervalSince($0) >= 60}) ?? true else { return false }
        lastHaptic = now; return true
    }
}
