import Foundation

/// Screen-space grouping changes presentation only; it never alters a rep's GPS fix.
struct WolfyPackLayoutV2 {
    struct Point {
        let id: UUID
        let x: Double
        let y: Double
    }
    struct Group {
        let members: [UUID]
        let x: Double
        let y: Double
    }
    let individuals: [UUID]
    let groups: [Group]

    init(points: [Point], local: UUID?, selected: UUID?, zoom: Double, constrained: Bool) {
        let spacing = zoom < 18 ? 100.0 : zoom < 20 ? 76.0 : 56.0
        let budget = constrained ? 5 : 8
        var singles: [Point] = []
        var remaining = points
        for id in [local, selected].compactMap({ $0 }) {
            if let index = remaining.firstIndex(where: { $0.id == id }),
               !singles.contains(where: { hypot($0.x-remaining[index].x, $0.y-remaining[index].y) < spacing }) {
                singles.append(remaining.remove(at: index))
            }
        }
        var groups: [Group] = []
        while !remaining.isEmpty {
            let first = remaining.removeFirst()
            var component = [first]
            var index = 0
            // Connected components avoid overlapping badges at cell boundaries.
            while index < component.count {
                let seed = component[index]
                let neighbors = remaining.filter { hypot($0.x-seed.x, $0.y-seed.y) < spacing }
                let ids = Set(neighbors.map(\.id))
                remaining.removeAll { ids.contains($0.id) }
                component.append(contentsOf: neighbors)
                index += 1
            }
            if component.count == 1 && singles.count < budget &&
                !singles.contains(where: { hypot($0.x-first.x, $0.y-first.y) < spacing }) {
                singles.append(first)
            } else {
                let x = component.map(\.x).reduce(0,+)/Double(component.count)
                var y = component.map(\.y).reduce(0,+)/Double(component.count)
                // Move the badge, never a wolf, clear of the local/selected avatar.
                while singles.contains(where: { hypot($0.x-x, $0.y-y) < spacing }) ||
                    groups.contains(where: { hypot($0.x-x, $0.y-y) < spacing }) { y += spacing }
                groups.append(Group(members: component.map(\.id), x: x, y: y))
            }
        }
        individuals = singles.map(\.id)
        self.groups = groups
    }
}
