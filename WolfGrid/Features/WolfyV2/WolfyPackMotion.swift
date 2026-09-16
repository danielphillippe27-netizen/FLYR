import Foundation

/// Independent of Mapbox and GPS collection. Permission-filtered fixes are its only input.
struct WolfyPackMotionV2 {
    struct Input {
        let id: UUID
        let stage: WolfyStage
        let fix: WolfyPackFixV2?
        let session: UUID
        let activity: WolfyActivityV2
        let firstName: String
    }
    enum Detail: Int { case full, simplified, marker }
    struct Pose: Identifiable {
        let id: UUID
        let stage: WolfyStage
        let latitude: Double
        let longitude: Double
        let heading: Double
        let clip: String
        let opacity: Double
        let detail: Detail
        let firstName: String
        let animated: Bool
    }
    private struct Track {
        var input: Input
        var accepted: WolfyPackFixV2
        var from: WolfyPackFixV2
        var receivedAt: Date
    }
    private var tracks: [UUID: Track] = [:]
    var count: Int { tracks.count }
    mutating func clear() { tracks.removeAll() }
    mutating func replace(_ inputs: [Input], now: Date) {
        let permitted = Set(inputs.filter { $0.fix != nil && $0.activity != .paused && $0.activity != .ended }.map(\.id))
        tracks = tracks.filter { permitted.contains($0.key) }
        for input in inputs {
            guard permitted.contains(input.id), let fix = input.fix else { continue }
            let previous = tracks[input.id]
            if let previous, previous.input.session == input.session, previous.accepted.sequence == fix.sequence {
                // A fresh heartbeat can change explicit activity; it cannot refresh a coordinate.
                tracks[input.id]?.input = input
                continue
            }
            let sameSession = previous?.input.session == input.session
            if !sameSession { tracks.removeValue(forKey:input.id) }
            guard WolfyPackPresencePolicyV2.accepts(fix, previous: sameSession ? previous?.accepted : nil, now: now) else { continue }
            let from = sameSession ? previous.map { interpolated($0, now: now) } ?? fix : fix
            tracks[input.id] = Track(input: input, accepted: fix, from: from, receivedAt: now)
        }
    }
    func poses(now: Date, center: WolfyPackFixV2, selected: UUID?, local: UUID?, reduceMotion: Bool,
               constrained: Bool, visible: (Double, Double) -> Bool = { _, _ in true }) -> [Pose] {
        let ordered = tracks.values.filter {
            now.timeIntervalSince($0.accepted.fixedAt) < 180 && visible($0.accepted.latitude, $0.accepted.longitude)
        }.sorted { a, b in
            func rank(_ t: Track) -> Int { t.input.id == selected ? 0 : t.input.id == local ? 1 : 2 }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            let ad = a.accepted.distance(to: center), bd = b.accepted.distance(to: center)
            return ad == bd ? a.input.id.uuidString < b.input.id.uuidString : ad < bd
        }
        return ordered.enumerated().map { index, track in
            let stale = now.timeIntervalSince(track.accepted.fixedAt) >= 60
            let fix = reduceMotion ? track.accepted : interpolated(track, now: now)
            let fullCount = constrained ? 3 : 6, simpleCount = constrained ? 2 : 2
            let detail: Detail = index < fullCount ? .full : index < fullCount + simpleCount ? .simplified : .marker
            let clip: String
            if stale || reduceMotion { clip = "idle" }
            else if track.input.activity == .moving {
                clip = fix.speed >= 3 ? "run" : fix.speed >= 1.6 ? "trot" : "walk"
            } else { clip = "idle" } // Stationarity does not imply knocking or a conversation.
            return Pose(id: track.input.id, stage: track.input.stage, latitude: fix.latitude, longitude: fix.longitude,
                        heading: fix.heading ?? 0, clip: clip, opacity: stale ? 0.35 : 1, detail: detail,
                        firstName: track.input.firstName, animated: !reduceMotion && !stale)
        }
    }
    private func interpolated(_ track: Track, now: Date) -> WolfyPackFixV2 {
        let target = track.accepted
        // Extrapolation is capped at two seconds measured from the actual GPS fix.
        let seconds = max(0, min(2, now.timeIntervalSince(target.fixedAt)))
        let moving = track.input.activity == .moving
        let meters = moving && target.heading != nil ? min(12, target.speed) * seconds : 0
        let radians = (target.heading ?? 0) * .pi / 180
        let latitude = max(-90, min(90, target.latitude + cos(radians) * meters / 111_320))
        let longitude = target.longitude + sin(radians) * meters / (111_320 * max(0.01, cos(target.latitude * .pi / 180)))
        let t = max(0, min(1, now.timeIntervalSince(track.receivedAt)))
        let blend = t * t * (3 - 2 * t)
        let oldHeading = track.from.heading ?? target.heading ?? 0
        let turn = ((target.heading ?? 0) - oldHeading + 540).truncatingRemainder(dividingBy: 360) - 180
        let longitudeDelta = (longitude-track.from.longitude+540).truncatingRemainder(dividingBy:360)-180
        return .init(latitude: track.from.latitude + (latitude-track.from.latitude)*blend,
                     longitude: (track.from.longitude + longitudeDelta*blend+540).truncatingRemainder(dividingBy:360)-180,
                     accuracy: target.accuracy, heading: (oldHeading + turn*blend + 360).truncatingRemainder(dividingBy: 360),
                     speed: target.speed, fixedAt: target.fixedAt, sequence: target.sequence)
    }
}
