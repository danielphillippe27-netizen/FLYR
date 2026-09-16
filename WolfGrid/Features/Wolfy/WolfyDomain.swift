import Foundation

struct WolfyAssetManifest: Decodable {
    struct Clip: Decodable { let name: String; let file: String; let loop: Bool; let duration: Double }
    struct FileInfo: Decodable { let sha256: String; let bytes: Int; let url: String? }
    let version: Int
    let compatibility: String
    let base: String
    let poster: String
    let animations: [Clip]
    let files: [String: FileInfo]
}

struct WolfyCatalogItem: Codable, Identifiable {
    let id: String
    let name: String
    let category: String
    let socket: String
    let rarity: String
    let price: Int
    let required_level: Int
    let required_achievement: String?
    let asset: String?
    var render_kind: String? = nil
    var price_currency: String? = nil
}
struct WolfyWallet: Codable {
    let xp: Int
    let coins: Int
    var spendable_xp: Int? = nil
    let happiness: Int
    let work_start: Int
    let work_end: Int
    let dnd: Bool
}
struct WolfyReward: Codable { let id: String; let source_event: String }
struct WolfySnapshot: Codable {
    let rewards: [WolfyReward]?
    let profile: WolfyWallet
    let owned: [String]
    let equipped: [String: String]
    let achievements: [String]
    let catalog: [WolfyCatalogItem]?
}

enum WolfyProgression {
    /// The five supplied portraits follow the existing permanent-XP rank milestones.
    static let growthLevels = [1, 10, 25, 50, 100]
    static func growthStage(xp: Int) -> Int {
        growthLevels.filter { $0 <= level(xp: xp) }.count
    }
    static func level(xp: Int) -> Int { min(100, 1 + Int(sqrt(Double(max(0, xp)) / 100))) }
    static func floorXP(level: Int) -> Int { max(0, level - 1) * max(0, level - 1) * 100 }
    static func rank(level: Int) -> String {
        switch level { case 100...: "Grid Legend"; case 50...: "Alpha"; case 25...: "Territory Wolf"; case 10...: "Street Wolf"; default: "Rookie" }
    }
}

enum WolfySemanticState: String, CaseIterable {
    case neutral = "idle_neutral", energized = "idle_happy", focused = "idle_focused", resting = "idle_tired"
    case thinking, talking, listening, encouraging, concerned
    case lead = "celebrate_lead", appointment = "celebrate_appointment", sale = "celebrate_sale"
    case goal = "goal_completed", rank = "rank_up", level = "level_up", training = "train"
    case customizing = "equip_item", sleeping = "sleep", feed = "eat_treat", play, wave
    var priority: Int {
        switch self {
        case .rank: 100; case .sale: 90; case .goal: 80; case .level: 75; case .appointment: 70; case .lead: 60
        case .feed,.play,.wave,.training,.customizing: 50
        case .talking,.listening,.thinking: 40; case .concerned,.encouraging: 30; case .focused: 20; default: 10
        }
    }
    var label: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

struct WolfyCharacterStateMachine {
    private(set) var state: WolfySemanticState = .neutral
    private(set) var expires: Date = .distantPast
    private var seen: Set<String> = []
    mutating func request(_ next: WolfySemanticState, eventID: String? = nil, now: Date = Date(), duration: Double = 3) -> Bool {
        if let eventID, seen.contains(eventID) { return false }
        guard now >= expires || next.priority >= state.priority else { return false }
        if let eventID { seen.insert(eventID) }
        state = next; expires = now.addingTimeInterval(duration)
        return true
    }
}
struct WolfyMood: Equatable {
    let state: WolfySemanticState
    let energy: Int
    let happiness: Int
    let health: Int?
    static func resolve(hour: Int, workStart: Int, workEnd: Int, dnd: Bool, active: Bool,
                        doors: Int?, target: Int?, overdue: Int?, happiness: Int) -> WolfyMood {
        let working = workStart <= workEnd ? (hour >= workStart && hour < workEnd) : (hour >= workStart || hour < workEnd)
        // No persistent time-decay job: rest cannot remove attributes, XP or inventory.
        let state: WolfySemanticState
        if dnd || !working { state = .resting }
        else if (overdue ?? 0) > 0 { state = .concerned }
        else if active { state = .focused }
        else if let doors, let target, doors >= target { state = .energized }
        else if let doors, let target, doors < target / 2 { state = .encouraging }
        else { state = .neutral }
        return WolfyMood(state: state, energy: active ? 75 : working ? 60 : 70,
                         happiness: min(100,max(0,happiness)), health: overdue.map { max(40,100 - $0 * 5) })
    }
}

enum WolfyFeatureDefaults {
    #if DEBUG
    static let enabled = true
    #else
    static let enabled = false
    #endif
}
