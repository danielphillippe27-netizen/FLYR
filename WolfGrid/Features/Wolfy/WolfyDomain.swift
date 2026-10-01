import Foundation
import UIKit

enum WolfyColor: String, Codable, CaseIterable, Identifiable {
    case classic, silver, charcoal, brown, arctic, auburn
    case amber, blue, green, violet, black, darkBrown, rose
    var id:String { rawValue }
    var title:String { self == .darkBrown ? "Dark Brown" : rawValue.capitalized }
    var uiColor:UIColor {
        switch self {
        case .classic: UIColor(red:0.96,green:0.97,blue:0.98,alpha:1)
        case .silver: UIColor(red:0.62,green:0.69,blue:0.77,alpha:1)
        case .charcoal: UIColor(red:0.33,green:0.36,blue:0.41,alpha:1)
        case .brown: UIColor(red:0.57,green:0.39,blue:0.27,alpha:1)
        case .arctic: UIColor(red:0.36,green:0.68,blue:0.83,alpha:1)
        case .auburn: UIColor(red:0.72,green:0.34,blue:0.22,alpha:1)
        case .amber: UIColor(red:0.95,green:0.64,blue:0.12,alpha:1)
        case .blue: UIColor(red:0.16,green:0.48,blue:0.91,alpha:1)
        case .green: UIColor(red:0.20,green:0.67,blue:0.43,alpha:1)
        case .violet: UIColor(red:0.61,green:0.37,blue:0.84,alpha:1)
        case .black: UIColor(red:0.08,green:0.09,blue:0.11,alpha:1)
        case .darkBrown: UIColor(red:0.24,green:0.14,blue:0.09,alpha:1)
        case .rose: UIColor(red:0.84,green:0.38,blue:0.45,alpha:1)
        }
    }
}

struct WolfyAppearance:Codable,Equatable {
    var fur:WolfyColor = .classic
    var eyes:WolfyColor = .amber
    var nose:WolfyColor = .black
    func normalized() -> Self {
        var result=self
        if nose == .brown { result.nose = .darkBrown }
        else if nose != .black && nose != .darkBrown { result.nose = .black }
        return result
    }
    static func saved(user:UUID,workspace:UUID) -> Self {
        let key="wolfy.appearance.\(workspace).\(user)"
        guard let data=UserDefaults.standard.data(forKey:key),
              let value=try? JSONDecoder().decode(Self.self,from:data) else { return Self() }
        let normalized=value.normalized()
        if normalized != value { normalized.save(user:user,workspace:workspace) }
        return normalized
    }
    func save(user:UUID,workspace:UUID) {
        let key="wolfy.appearance.\(workspace).\(user)"
        if let data=try? JSONEncoder().encode(normalized()) { UserDefaults.standard.set(data,forKey:key) }
    }
}

struct WolfyAssetManifest: Decodable {
    struct Clip: Decodable { let name: String; let file: String; let loop: Bool; let duration: Double }
    struct FileInfo: Decodable { let sha256: String; let bytes: Int; let url: String? }
    let version: Int
    let compatibility: String
    let base: String
    let poster: String
    let growthStages: [String: String]?
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
    /// Lifetime completed doors determine Wolfy's growth; spending XP never changes it.
    static let growthDoorThresholds = [0, 100, 500, 2_500, 10_000]
    static let growthStages = ["Pup", "Young Wolf", "Street Wolf", "Alpha", "Legend"]
    /// Portrait store and XP rank retain their separate legacy level ladder.
    static let growthLevels = [1, 10, 25, 50, 100]
    static func growthStage(doors: Int) -> Int {
        growthDoorThresholds.filter { max(0, doors) >= $0 }.count
    }
    static func growthStage(xp: Int) -> Int { growthLevels.filter { $0 <= level(xp: xp) }.count }
    static func doorsUntilNextStage(doors: Int) -> Int? {
        let stage = growthStage(doors: doors)
        guard stage < growthDoorThresholds.count else { return nil }
        return max(0, growthDoorThresholds[stage] - max(0, doors))
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
