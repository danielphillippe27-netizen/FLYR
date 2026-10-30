import Foundation

@main struct SessionPreparationTests {
    static func main() throws {
        // Sparse overlay selection must include shared buildings only once,
        // and preserve status, GPS and coverage candidates in source order.
        let overlayIndex = SessionMapFeatureIndex(Array(0..<14_000)) { id in
            ["building:\(id)", "address:\(id)", "address:shared-\(id / 2)"]
        }
        let sparseKeys: Set<String> = ["address:12", "building:800", "address:shared-500", "address:missing"]
        precondition(overlayIndex.matching(sparseKeys) == [12, 800, 1000, 1001])
        precondition(overlayIndex.matching([]).isEmpty)
        print("PASS: sparse overlay selects status/GPS/shared-address candidates without unrelated buildings")
        // Separate taps must reuse the geometry index, while a changed edit or
        // source key must replace removed links instead of returning stale homes.
        let selectionCache = SessionMapGeometryCache()
        var selectionBuilds = 0
        func selectionIndex(_ key: String, _ aliases: [String]) -> SessionMapFeatureIndex<Int> {
            selectionCache.value(for: "selection", key: key) {
                selectionBuilds += 1
                return SessionMapFeatureIndex(Array(aliases.indices)) { [aliases[$0]] }
            }
        }
        for _ in 0..<100 {
            precondition(selectionIndex("geometry1-edit1", ["old", "shared"]).matching(["old"]) == [0])
        }
        precondition(selectionBuilds == 1, "Repeated taps must not rebuild the lookup")
        let editedSelection = selectionIndex("geometry1-edit2", ["new", "shared"])
        precondition(editedSelection.matching(["old"]).isEmpty)
        precondition(editedSelection.matching(["new"]) == [0])
        precondition(selectionBuilds == 2, "Edits must invalidate the lookup")
        print("PASS: selection indexes reuse across taps and invalidate removed links on edits")
        let cache = SessionMapPreparationCache()
        var geometryReads = 0
        var generation = 1
        func geometry() -> [Int] {
            cache.value(for: "geometry") {
                geometryReads += 1
                return Array(repeating: generation, count: 667)
            }
        }
        cache.withSnapshot {
            for _ in 0..<667 {
                precondition(geometry().count == 667)
                cache.withSnapshot { precondition(geometry()[0] == 1) }
            }
        }
        precondition(geometryReads == 1, "667 homes must share one geometry snapshot")
        generation = 2
        cache.withSnapshot { precondition(geometry()[0] == 2) }
        precondition(geometryReads == 2, "A new pass must see link/geometry edits")
        enum Failure: Error { case cancelled }
        do {
            try cache.withSnapshot {
                _ = geometry()
                throw Failure.cancelled
            }
        } catch Failure.cancelled {}
        generation = 3
        precondition(geometry()[0] == 3)
        generation = 4
        precondition(geometry()[0] == 4, "Unscoped reads must never keep stale data")
        struct Home {
            let id: Int
            let aliases: [String]
        }
        let homes = (0..<667).map { Home(id: $0, aliases: ["home-\($0)", "shared", "home-\($0)"]) }
        var identifierReads = 0
        let start = Date()
        let index = SessionMapFeatureIndex(homes) { home in
            identifierReads += 1
            return home.aliases
        }
        for id in 0..<667 {
            precondition(index.matching(["home-\(id)"]).map(\.id) == [id])
        }
        precondition(identifierReads == 667, "Each home's aliases must be read once, rather than once per lookup")
        precondition(index.matching(["shared", "home-7"]).map(\.id) == Array(0..<667),
                     "Overlapping aliases must preserve source order without duplicate homes")
        precondition(index.matching(["missing"]).isEmpty)
        // Match the corrected-farm workload: every building asks for links,
        // including aliases, unlinked homes and buildings with several units.
        let farmSize = 14_000
        var indexedRows = 0
        let farmRows = (0..<farmSize).map { Home(id: $0, aliases: ["b-\($0)", "group-\($0 / 3)"]) }
        let farmStart = Date()
        cache.withSnapshot {
            for id in 0..<farmSize {
                let farmIndex: SessionMapFeatureIndex<Home> = cache.value(for: "correctedFarm") {
                    SessionMapFeatureIndex(farmRows) { row in
                        indexedRows += 1
                        return row.aliases
                    }
                }
                precondition(farmIndex.matching(["b-\(id)"]).map(\.id) == [id])
                if id % 1000 == 0 {
                    let wanted: Set<String> = ["b-\(id)", "group-\(id / 3)", "unlinked"]
                    let reference = farmRows.filter { !wanted.isDisjoint(with: $0.aliases) }.map(\.id)
                    precondition(farmIndex.matching(wanted).map(\.id) == reference)
                }
            }
        }
        precondition(indexedRows == farmSize, "14,000 building lookups must index rows once, not 196 million times")
        print("14,000 corrected-home lookups: \(Int(Date().timeIntervalSince(farmStart) * 1000)) ms; indexed rows=\(indexedRows)")
        cache.withSnapshot {
            let edited: SessionMapFeatureIndex<Home> = cache.value(for: "correctedFarm") {
                SessionMapFeatureIndex([Home(id: 7, aliases: ["relocated"])]) { $0.aliases }
            }
            precondition(edited.matching(["b-7"]).isEmpty)
            precondition(edited.matching(["relocated"]).map(\.id) == [7], "A new pass must see corrected links")
        }
        func evaluate(_ expression: Any, state: [String: Any], properties: [String: Any]) -> Any? {
            guard let items = expression as? [Any], let op = items.first as? String else { return expression }
            func eval(_ value: Any) -> Any? { evaluate(value, state: state, properties: properties) }
            switch op {
            case "feature-state": return state[items[1] as! String]
            case "get": return properties[items[1] as! String]
            case "coalesce": return items.dropFirst().compactMap(eval).first
            case "==": return (eval(items[1]) as? String) == (eval(items[2]) as? String)
            case "case": return eval(items[(eval(items[1]) as? Bool) == true ? 2 : 3])
            default: preconditionFailure("Unexpected test expression \(op)")
            }
        }
        let statusExpression: [Any] = ["coalesce", ["feature-state", "status"], ["get", "status"], "not_visited"]
        let scope = FarmCycleStyleScope(id: "farm-a|1", defaultStatus: "not_visited")
        let properties: [String: Any] = ["status": "visited", "scans_total": 9]
        let oldState: [String: Any] = ["status": "lead", "scans_total": 2, "selected": true, "card_engaged": true]
        precondition(evaluate(scope.expression(statusExpression), state: oldState, properties: properties) as? String == "not_visited")
        let updated = scope.stamp(oldState)
        let rendered = FarmCycleStyleScope.renderedState(updated)
        precondition(rendered["status"] == nil && rendered["scans_total"] == nil)
        precondition(rendered["selected"] as? Bool == true && rendered["card_engaged"] as? Bool == true)
        precondition(evaluate(scope.expression(statusExpression), state: rendered, properties: properties) as? String == "lead")
        let nextCycle = FarmCycleStyleScope(id: "farm-a|2", defaultStatus: "not_visited")
        precondition(evaluate(nextCycle.expression(statusExpression), state: rendered, properties: properties) as? String == "not_visited")
        let otherFarm = FarmCycleStyleScope(id: "farm-b|1", defaultStatus: "not_visited")
        precondition(evaluate(otherFarm.expression(statusExpression), state: rendered, properties: properties) as? String == "not_visited")
        let flyerScope = FarmCycleStyleScope(id: "farm-a|2", defaultStatus: "flyer_unvisited")
        precondition(evaluate(flyerScope.expression(statusExpression), state: rendered, properties: properties) as? String == "flyer_unvisited")
        precondition(evaluate(statusExpression, state: oldState, properties: properties) as? String == "lead", "Exiting a cycle must retain the original expression")
        precondition(evaluate(nextCycle.expression(["feature-state", "scans_total"]), state: rendered, properties: properties) as? Int == 0)
        print("PASS: sparse cycle styling ignores historical tile states; current outcomes, cycle/farm switches, flyer defaults and selection remain correct")
        let geometryCache = SessionMapGeometryCache()
        var rebuilds = 0
        func filtered(_ key: String) -> Int {
            geometryCache.value(for: "buildings", key: key) {
                rebuilds += 1
                return rebuilds
            }
        }
        for _ in 0..<100 { precondition(filtered("campaign:revision-1:boundary-a") == 1) }
        precondition(filtered("campaign:revision-2:boundary-a") == 2)
        precondition(filtered("campaign:revision-2:boundary-b") == 3)
        precondition(rebuilds == 3, "Geometry must be reused until its source or boundary changes")
        print("667-home index plus 667 lookups: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        print("PASS: 667-home preparation reads geometry once; nested scopes, edits, thrown errors, and unscoped reads stay fresh")
    }
}
