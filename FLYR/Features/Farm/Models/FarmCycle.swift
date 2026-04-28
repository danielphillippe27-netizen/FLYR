import Foundation

struct FarmCycle: Identifiable, Codable, Equatable {
    let id: String
    let farmId: UUID
    let cycleNumber: Int
    let cycleName: String
    let startDate: Date
    let endDate: Date
    let touchCount: Int
    let completedTouchCount: Int
    let results: [String: AnyCodable]?

    var plannedSessionCount: Int {
        intResult(for: "planned_sessions") ?? touchCount
    }

    var executedSessionCount: Int {
        intResult(for: "sessions_count") ?? completedTouchCount
    }

    var doorsHitCount: Int {
        intResult(for: "doors_hit") ?? 0
    }

    init(
        farmId: UUID,
        cycleNumber: Int,
        startDate: Date,
        endDate: Date,
        touchCount: Int,
        completedTouchCount: Int,
        results: [String: AnyCodable]? = nil
    ) {
        self.id = "\(farmId.uuidString.lowercased())-cycle-\(cycleNumber)"
        self.farmId = farmId
        self.cycleNumber = cycleNumber
        self.cycleName = "Cycle \(cycleNumber)"
        self.startDate = startDate
        self.endDate = endDate
        self.touchCount = touchCount
        self.completedTouchCount = completedTouchCount
        self.results = results
    }

    private func intResult(for key: String) -> Int? {
        guard let value = results?[key]?.value else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }
}
