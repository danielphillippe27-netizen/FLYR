import Foundation

/// Reuses derived geometry until its caller's complete source key changes.
final class SessionMapGeometryCache {
    private var key: String?
    private var values: [String: Any] = [:]

    func value<T>(for name: String, key: String, compute: () -> T) -> T {
        if self.key != key {
            self.key = key
            values.removeAll(keepingCapacity: true)
        }
        if let cached = values[name] as? T { return cached }
        let result = compute()
        values[name] = result
        return result
    }
}

/// A synchronous preparation pass sees one snapshot. Nothing survives the pass,
/// so feature/link edits are always visible to the next pass. Never hold across await.
final class SessionMapPreparationCache {
    private var depth = 0
    private var values: [String: Any] = [:]

    func withSnapshot<T>(_ work: () throws -> T) rethrows -> T {
        depth += 1
        defer {
            depth -= 1
            if depth == 0 { values.removeAll(keepingCapacity: true) }
        }
        return try work()
    }

    func value<T>(for key: String, compute: () -> T) -> T {
        guard depth > 0 else { return compute() }
        if let cached = values[key] as? T { return cached }
        let result = compute()
        values[key] = result
        return result
    }
}

/// Ordered alias lookup: build once, then touch only matching features per home.
struct SessionMapFeatureIndex<Element> {
    private let elements: [Element]
    private let positions: [String: [Int]]

    init(_ elements: [Element], identifiers: (Element) -> [String]) {
        self.elements = elements
        var positions: [String: [Int]] = [:]
        for (position, element) in elements.enumerated() {
            for identifier in Set(identifiers(element)) {
                positions[identifier, default: []].append(position)
            }
        }
        self.positions = positions
    }

    func matching(_ identifiers: Set<String>) -> [Element] {
        Set(identifiers.flatMap { positions[$0] ?? [] }).sorted().map { elements[$0] }
    }
}

/// A farm cycle has a default appearance, plus sparse outcomes. Scope the paint
/// expressions instead of sending one reset to every feature in the territory.
struct FarmCycleStyleScope: Equatable {
    let id: String
    let defaultStatus: String
    static let stateKeys = ["status", "scans_total", "qr_scanned", "visit_owner", "suppress_selected_highlight"]

    func expression(_ value: Any) -> Any {
        guard let values = value as? [Any], let op = values.first as? String else { return value }
        // Literal arrays are data, never expression trees.
        if op == "literal" { return value }
        if values.count == 2, let key = values[1] as? String {
            let fallback: Any
            switch key {
            case "status", "address_status", "building_status", "home_status": fallback = defaultStatus
            case "scans_total": fallback = 0
            case "qr_scanned", "suppress_selected_highlight": fallback = false
            case "visit_owner": fallback = ""
            default: return values.map { expression($0) }
            }
            if op == "get" { return fallback }
            if op == "feature-state" {
                return ["case", ["==", ["feature-state", "farm_cycle"], id],
                        ["coalesce", ["feature-state", "farm_" + key], fallback], fallback] as [Any]
            }
        }
        return values.map { expression($0) }
    }

    func stamp(_ state: [String: Any]) -> [String: Any] {
        var result = state
        result["farm_cycle"] = id
        for key in Self.stateKeys { result["farm_" + key] = state[key] }
        return result
    }

    static func renderedState(_ state: [String: Any]) -> [String: Any] {
        guard state["farm_cycle"] != nil else { return state }
        // Keep historical, non-cycle feature state intact in the renderer.
        return state.filter { !stateKeys.contains($0.key) }
    }
}
