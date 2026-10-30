import Foundation

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
