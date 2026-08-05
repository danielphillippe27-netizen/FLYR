import Foundation

/// Legacy compatibility wrapper for the retired farm phase concept.
/// New farm execution uses touch-based cycles via `FarmCycle`.
struct FarmPhase: Identifiable, Codable, Equatable {
    let id: UUID
    let farmId: UUID
    let phaseName: String
    let startDate: Date
    let endDate: Date
    let campaignId: UUID?
    let results: [String: AnyCodable]?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        farmId: UUID,
        phaseName: String,
        startDate: Date,
        endDate: Date,
        campaignId: UUID? = nil,
        results: [String: AnyCodable]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.farmId = farmId
        self.phaseName = phaseName
        self.startDate = startDate
        self.endDate = endDate
        self.campaignId = campaignId
        self.results = results
        self.createdAt = createdAt
    }

    init(cycle: FarmCycle, campaignId: UUID? = nil, createdAt: Date = Date()) {
        self.init(
            farmId: cycle.farmId,
            phaseName: cycle.cycleName,
            startDate: cycle.startDate,
            endDate: cycle.endDate,
            campaignId: campaignId,
            results: cycle.results,
            createdAt: createdAt
        )
    }

    func getResultInt(_ key: String) -> Int? {
        guard let value = results?[key]?.value else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double, double.isFinite { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    func getResultDouble(_ key: String) -> Double? {
        guard let value = results?[key]?.value else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    func getResultString(_ key: String) -> String? {
        guard let value = results?[key]?.value else { return nil }
        if let string = value as? String { return string }
        return String(describing: value)
    }
}
