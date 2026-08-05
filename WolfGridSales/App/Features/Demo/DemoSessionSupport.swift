import Foundation
import CoreLocation
import SwiftUI
import Combine

enum DemoSessionSpeed: String, CaseIterable, Identifiable {
    case slow
    case medium
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: return "Slow"
        case .medium: return "Medium"
        case .fast: return "Fast"
        }
    }

    var secondsPerHome: TimeInterval {
        switch self {
        case .slow: return 2.0
        case .medium: return 1.0
        case .fast: return 0.1
        }
    }

    var detailLabel: String {
        "\(title) (\(secondsPerHome.formattedDemoSpeed)s per home)"
    }
}

enum DemoPathMode: String, CaseIterable, Identifiable {
    case pauseAtHomes
    case continuous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pauseAtHomes: return "Stops"
        case .continuous: return "Continuous"
        }
    }

    var detailLabel: String {
        switch self {
        case .pauseAtHomes: return "Pause briefly as each home gets hit"
        case .continuous: return "Glide through the route without stopping at homes"
        }
    }
}

enum DemoRecordingViewStyle: String, CaseIterable, Identifiable {
    case fieldHUD
    case cleanMap
    case creatorOverlay
    case landscapeMap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fieldHUD: return "HUD"
        case .cleanMap: return "Clean"
        case .creatorOverlay: return "Creator"
        case .landscapeMap: return "Wide"
        }
    }

    var detailLabel: String {
        switch self {
        case .fieldHUD: return "Live session controls with route progress"
        case .cleanMap: return "Map-first capture with minimal overlays"
        case .creatorOverlay: return "Polished recording card with live stats"
        case .landscapeMap: return "Horizontal map-only capture with no on-screen controls"
        }
    }
}

enum DemoCameraAngle: String, CaseIterable, Identifiable {
    case birdsEye
    case normal3D
    case streetSide
    case fixed
    case fixedPullback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .birdsEye: return "Bird"
        case .normal3D: return "3D"
        case .streetSide: return "Street"
        case .fixed: return "Orbit"
        case .fixedPullback: return "Back"
        }
    }

    var detailLabel: String {
        switch self {
        case .birdsEye: return "Top-down route reveal"
        case .normal3D: return "Angled 3D campaign fly-through"
        case .streetSide: return "Low street-side tracking shot"
        case .fixed: return "Frame the camera yourself, then orbit from that position"
        case .fixedPullback: return "Frame the camera yourself, then crane back to a high overhead view"
        }
    }
}

enum DemoHitPattern: String, CaseIterable, Identifiable {
    case allGreen
    case streetSegments
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allGreen: return "All green"
        case .streetSegments: return "Segments"
        case .random: return "Random"
        }
    }

    var detailLabel: String {
        switch self {
        case .allGreen: return "Every home gets hit and turns green"
        case .streetSegments: return "Hide the marker and sweep homes green by street segment"
        case .random: return "Mixed canvassing outcomes across the route"
        }
    }
}

private extension TimeInterval {
    var formattedDemoSpeed: String {
        if self >= 1 {
            return String(format: "%.0f", self)
        }
        return String(format: "%.1f", self)
    }
}

struct DemoSessionLaunchConfiguration: Identifiable, Equatable {
    let campaign: CampaignV2
    let homeCount: Int
    let speed: DemoSessionSpeed
    let pathMode: DemoPathMode
    let recordingViewStyle: DemoRecordingViewStyle
    let cameraAngle: DemoCameraAngle
    let hitPattern: DemoHitPattern

    var id: UUID { campaign.id }
}

struct DemoSessionStep {
    let target: ResolvedCampaignTarget
    let travelPath: [CLLocationCoordinate2D]
}

enum DemoSessionRoutePlanner {
    private enum Parity: Int {
        case even = 0
        case odd = 1
        case unknown = 2
    }

    private struct SegmentKey: Hashable {
        let street: String
        let parity: Parity
    }

    private struct Segment {
        let key: SegmentKey
        let targets: [ResolvedCampaignTarget]

        var centroid: CLLocationCoordinate2D {
            let lat = targets.reduce(0.0) { $0 + $1.coordinate.latitude } / Double(targets.count)
            let lon = targets.reduce(0.0) { $0 + $1.coordinate.longitude } / Double(targets.count)
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    static func orderedTargets(_ targets: [ResolvedCampaignTarget], limit: Int? = nil) -> [ResolvedCampaignTarget] {
        let cappedTargets = Array(targets.prefix(limit ?? targets.count))
        guard cappedTargets.count > 1 else { return cappedTargets }

        let grouped = Dictionary(grouping: cappedTargets) { target in
            SegmentKey(
                street: normalizedStreetName(for: target),
                parity: parity(for: target)
            )
        }

        var segments = grouped.map { key, members in
            Segment(key: key, targets: members.sorted(by: compareTargetsOnStreet))
        }

        segments.sort {
            let lhsStreet = $0.key.street
            let rhsStreet = $1.key.street
            if lhsStreet == rhsStreet {
                return $0.key.parity.rawValue < $1.key.parity.rawValue
            }
            return lhsStreet < rhsStreet
        }

        var orderedSegments: [Segment] = []
        var remaining = segments
        var anchor: CLLocationCoordinate2D? = nil

        while !remaining.isEmpty {
            let nextIndex: Int
            if let anchor {
                nextIndex = remaining.enumerated().min { lhs, rhs in
                    distance(from: anchor, to: lhs.element.centroid) < distance(from: anchor, to: rhs.element.centroid)
                }?.offset ?? 0
            } else {
                nextIndex = remaining.enumerated().min { lhs, rhs in
                    if lhs.element.centroid.latitude == rhs.element.centroid.latitude {
                        return lhs.element.centroid.longitude < rhs.element.centroid.longitude
                    }
                    return lhs.element.centroid.latitude < rhs.element.centroid.latitude
                }?.offset ?? 0
            }

            let nextSegment = remaining.remove(at: nextIndex)
            orderedSegments.append(nextSegment)
            anchor = nextSegment.targets.last?.coordinate ?? nextSegment.centroid
        }

        return orderedSegments.flatMap(\.targets)
    }

    static func buildSteps(
        for orderedTargets: [ResolvedCampaignTarget],
        corridors: [StreetCorridor]
    ) -> [DemoSessionStep] {
        guard !orderedTargets.isEmpty else { return [] }

        let roadGraph = makeRoadGraph(corridors: corridors)
        let projectionService = CorridorProjectionService(corridors: corridors, maxLateralDeviation: 120)
        var previousCoordinate: CLLocationCoordinate2D?
        var previousTarget: ResolvedCampaignTarget?

        return orderedTargets.map { target in
            let travelPath = path(
                fromTarget: previousTarget,
                from: previousCoordinate,
                to: target.coordinate,
                toTarget: target,
                graph: roadGraph,
                projectionService: projectionService,
                corridors: corridors
            )
            previousCoordinate = target.coordinate
            previousTarget = target
            return DemoSessionStep(target: target, travelPath: travelPath)
        }
    }

    static func streetSegmentBatches(for steps: [DemoSessionStep]) -> [[DemoSessionStep]] {
        guard !steps.isEmpty else { return [] }

        var batches: [[DemoSessionStep]] = []
        var currentBatch: [DemoSessionStep] = []
        var currentKey: SegmentKey?

        for step in steps {
            let nextKey = SegmentKey(
                street: normalizedStreetName(for: step.target),
                parity: parity(for: step.target)
            )
            if let currentKey, currentKey != nextKey, !currentBatch.isEmpty {
                batches.append(currentBatch)
                currentBatch = []
            }
            currentKey = nextKey
            currentBatch.append(step)
        }

        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    private static func makeRoadGraph(corridors: [StreetCorridor]) -> RoadGraph? {
        guard !corridors.isEmpty else { return nil }
        let graph = RoadGraph()
        for corridor in corridors where corridor.polyline.count >= 2 {
            graph.addRoad(lineString: corridor.polyline, roadClass: corridor.roadClass)
        }
        return graph
    }

    private static func path(
        fromTarget startTarget: ResolvedCampaignTarget?,
        from start: CLLocationCoordinate2D?,
        to end: CLLocationCoordinate2D,
        toTarget endTarget: ResolvedCampaignTarget,
        graph: RoadGraph?,
        projectionService: CorridorProjectionService,
        corridors: [StreetCorridor]
    ) -> [CLLocationCoordinate2D] {
        guard let start else { return [] }
        if let startTarget,
           let corridorPath = sameStreetCorridorPath(
                fromTarget: startTarget,
                from: start,
                toTarget: endTarget,
                to: end,
                projectionService: projectionService,
                corridors: corridors
           ),
           corridorPath.count >= 2 {
            return corridorPath
        }
        if let graph, let detailedPath = graph.findDetailedPath(from: start, to: end)?.path, !detailedPath.isEmpty {
            return detailedPath
        }
        return interpolatedPath(from: start, to: end, segments: 8)
    }

    private static func interpolatedPath(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int
    ) -> [CLLocationCoordinate2D] {
        let segmentCount = max(1, segments)
        return (0...segmentCount).map { index in
            let progress = Double(index) / Double(segmentCount)
            return CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * progress,
                longitude: start.longitude + (end.longitude - start.longitude) * progress
            )
        }
    }

    private static func sameStreetCorridorPath(
        fromTarget startTarget: ResolvedCampaignTarget,
        from start: CLLocationCoordinate2D,
        toTarget endTarget: ResolvedCampaignTarget,
        to end: CLLocationCoordinate2D,
        projectionService: CorridorProjectionService,
        corridors: [StreetCorridor]
    ) -> [CLLocationCoordinate2D]? {
        let startStreet = normalizedStreetName(for: startTarget)
        let endStreet = normalizedStreetName(for: endTarget)
        guard !startStreet.isEmpty, startStreet == endStreet else { return nil }

        let candidateCorridors = candidateCorridorsForStreet(
            street: startStreet,
            corridors: corridors
        )
        guard !candidateCorridors.isEmpty else { return nil }

        var bestPath: [CLLocationCoordinate2D]?
        var bestScore = Double.infinity

        for corridor in candidateCorridors {
            guard let startProjection = projectionService.project(point: start, onCorridorId: corridor.id),
                  let endProjection = projectionService.project(point: end, onCorridorId: corridor.id) else {
                continue
            }

            let offsetScore = abs(startProjection.lateralOffsetMeters) + abs(endProjection.lateralOffsetMeters)
            let sliced = corridor.slice(
                fromProgressMeters: startProjection.progressMeters,
                toProgressMeters: endProjection.progressMeters
            )
            guard sliced.count >= 2 else { continue }

            if offsetScore < bestScore {
                bestScore = offsetScore
                bestPath = sliced
            }
        }

        return bestPath
    }

    private static func candidateCorridorsForStreet(
        street: String,
        corridors: [StreetCorridor]
    ) -> [StreetCorridor] {
        let normalizedNeedle = normalizeRoadName(street)
        guard !normalizedNeedle.isEmpty else { return [] }

        return corridors.filter { corridor in
            let roadName = normalizeRoadName(corridor.roadName ?? "")
            return !roadName.isEmpty && (roadName == normalizedNeedle || roadName.contains(normalizedNeedle) || normalizedNeedle.contains(roadName))
        }
    }

    private static func compareTargetsOnStreet(_ lhs: ResolvedCampaignTarget, _ rhs: ResolvedCampaignTarget) -> Bool {
        let lhsNumber = numericHouseNumber(for: lhs) ?? Int.max
        let rhsNumber = numericHouseNumber(for: rhs) ?? Int.max
        if lhsNumber == rhsNumber {
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
        return lhsNumber < rhsNumber
    }

    private static func normalizedStreetName(for target: ResolvedCampaignTarget) -> String {
        let explicitStreet = target.streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitStreet.isEmpty {
            return normalizeRoadName(explicitStreet)
        }

        let trimmed = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let noHouse = trimmed.replacingOccurrences(
            of: #"^\s*\d+[A-Za-z]?\s+"#,
            with: "",
            options: .regularExpression
        )
        let streetOnly = noHouse.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? noHouse
        return normalizeRoadName(streetOnly.isEmpty ? trimmed : streetOnly)
    }

    private static func parity(for target: ResolvedCampaignTarget) -> Parity {
        guard let number = numericHouseNumber(for: target) else { return .unknown }
        return number.isMultiple(of: 2) ? .even : .odd
    }

    private static func numericHouseNumber(for target: ResolvedCampaignTarget) -> Int? {
        let rawValue = target.houseNumber ?? target.label.extractHouseNumber()
        guard let rawValue else { return nil }
        let digits = rawValue.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func distance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        )
    }

    private static func normalizeRoadName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DemoFounderAccess {
    private static let founderEmails: Set<String> = [
        "danielfounder@gmail.com"
    ]

    private static let founderUserIDs: Set<String> = [
        "00000000-0000-0000-0000-000000000001"
    ]

    static func isAllowed(user: AppUser?) -> Bool {
        guard let user else { return false }
        if founderUserIDs.contains(user.id.uuidString.lowercased()) {
            return true
        }
        return founderEmails.contains(user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

@MainActor
final class DemoSessionSimulator: ObservableObject {
    enum FinishReason {
        case completed
        case stopped
    }

    @Published private(set) var isRunning = false
    @Published private(set) var currentTarget: ResolvedCampaignTarget?
    @Published private(set) var currentDisplayLabel: String?

    private var runTask: Task<Void, Never>?
    private var suppressFinishCallback = false

    func start(
        steps: [DemoSessionStep],
        speed: DemoSessionSpeed,
        pathMode: DemoPathMode,
        initialCoordinate: CLLocationCoordinate2D?,
        onTargetWillAdvance: @escaping @MainActor (ResolvedCampaignTarget) -> Void,
        onLocationUpdate: @escaping @MainActor (CLLocationCoordinate2D, Bool) async -> Void,
        onTargetHit: @escaping @MainActor (ResolvedCampaignTarget) async -> Void,
        onFinish: @escaping @MainActor (FinishReason) -> Void
    ) {
        stop(notify: false)
        guard !steps.isEmpty else {
            onFinish(.stopped)
            return
        }

        isRunning = true
        currentTarget = nil
        currentDisplayLabel = nil
        suppressFinishCallback = false

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for step in steps {
                guard !Task.isCancelled else {
                    self.finish(.stopped, onFinish: onFinish)
                    return
                }

                let target = step.target
                self.currentTarget = target
                self.currentDisplayLabel = target.label
                onTargetWillAdvance(target)

                let pausesAtHomes = pathMode == .pauseAtHomes
                let totalDuration = speed.secondsPerHome
                let moveDuration = pausesAtHomes ? max(0.12, totalDuration * 0.62) : max(0.12, totalDuration)
                let pulseDuration = pausesAtHomes ? max(0.08, totalDuration - moveDuration) : 0
                let travelPath = pausesAtHomes ? step.travelPath : Self.continuousTravelPath(for: step)

                if travelPath.count >= 2 {
                    let pathSteps = max(1, travelPath.count)
                    for coordinate in travelPath {
                        guard !Task.isCancelled else {
                            self.finish(.stopped, onFinish: onFinish)
                            return
                        }
                        await onLocationUpdate(coordinate, true)
                        try? await Task.sleep(nanoseconds: UInt64((moveDuration / Double(pathSteps)) * 1_000_000_000))
                    }
                } else {
                    await onLocationUpdate(target.coordinate, false)
                    if pausesAtHomes {
                        try? await Task.sleep(nanoseconds: UInt64(moveDuration * 1_000_000_000))
                    }
                }

                if pulseDuration > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(pulseDuration * 1_000_000_000))
                }
                guard !Task.isCancelled else {
                    self.finish(.stopped, onFinish: onFinish)
                    return
                }

                await onTargetHit(target)
            }

            self.finish(.completed, onFinish: onFinish)
        }
    }

    func startStreetSegmentSweep(
        steps: [DemoSessionStep],
        speed: DemoSessionSpeed,
        onSegmentWillAdvance: @escaping @MainActor ([ResolvedCampaignTarget]) -> Void,
        onLocationUpdate: @escaping @MainActor (CLLocationCoordinate2D, Bool) async -> Void,
        onTargetsHit: @escaping @MainActor ([ResolvedCampaignTarget]) async -> Void,
        onFinish: @escaping @MainActor (FinishReason) -> Void
    ) {
        stop(notify: false)
        let batches = DemoSessionRoutePlanner.streetSegmentBatches(for: steps)
        guard !batches.isEmpty else {
            onFinish(.stopped)
            return
        }

        isRunning = true
        currentTarget = nil
        currentDisplayLabel = nil
        suppressFinishCallback = false

        runTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let perHomeDelay = speed.secondsPerHome
            for batch in batches {
                guard !Task.isCancelled else {
                    self.finish(.stopped, onFinish: onFinish)
                    return
                }

                let targets = batch.map(\.target)
                guard let firstTarget = targets.first else { continue }
                self.currentTarget = nil
                self.currentDisplayLabel = Self.segmentDisplayLabel(for: targets)
                onSegmentWillAdvance(targets)

                await onLocationUpdate(Self.centroid(for: targets), false)

                for target in targets {
                    guard !Task.isCancelled else {
                        self.finish(.stopped, onFinish: onFinish)
                        return
                    }
                    self.currentDisplayLabel = Self.houseDisplayLabel(for: target, in: targets)
                    await onTargetsHit([target])
                    try? await Task.sleep(nanoseconds: UInt64(perHomeDelay * 1_000_000_000))
                }
            }

            self.finish(.completed, onFinish: onFinish)
        }
    }

    func stop(notify: Bool = true, onFinish: ((FinishReason) -> Void)? = nil) {
        guard runTask != nil || isRunning else { return }
        suppressFinishCallback = !notify
        runTask?.cancel()
        runTask = nil
        currentTarget = nil
        currentDisplayLabel = nil
        isRunning = false
        if notify {
            onFinish?(.stopped)
        }
    }

    private func finish(_ reason: FinishReason, onFinish: @escaping (FinishReason) -> Void) {
        runTask = nil
        currentTarget = nil
        currentDisplayLabel = nil
        isRunning = false
        if !suppressFinishCallback {
            onFinish(reason)
        }
        suppressFinishCallback = false
    }

    private static func continuousTravelPath(for step: DemoSessionStep) -> [CLLocationCoordinate2D] {
        let sourcePath = step.travelPath.isEmpty ? [step.target.coordinate] : step.travelPath
        guard sourcePath.count >= 2 else { return sourcePath }

        var densified: [CLLocationCoordinate2D] = []
        for index in 0..<(sourcePath.count - 1) {
            let start = sourcePath[index]
            let end = sourcePath[index + 1]
            let distanceMeters = CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
            let segmentCount = max(1, Int(ceil(distanceMeters / 12.0)))

            if densified.isEmpty {
                densified.append(start)
            }
            for segmentIndex in 1...segmentCount {
                let progress = Double(segmentIndex) / Double(segmentCount)
                densified.append(interpolate(from: start, to: end, progress: progress))
            }
        }

        return densified
    }

    private static func interpolate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        progress: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress
        )
    }

    private static func centroid(for targets: [ResolvedCampaignTarget]) -> CLLocationCoordinate2D {
        guard !targets.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        let latitude = targets.reduce(0.0) { $0 + $1.coordinate.latitude } / Double(targets.count)
        let longitude = targets.reduce(0.0) { $0 + $1.coordinate.longitude } / Double(targets.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func segmentDisplayLabel(for targets: [ResolvedCampaignTarget]) -> String {
        let street = streetDisplayName(for: targets.first)
        let homeText = targets.count == 1 ? "1 home" : "\(targets.count) homes"
        guard let street else { return homeText }
        return "\(homeText) on \(street)"
    }

    private static func houseDisplayLabel(for target: ResolvedCampaignTarget, in segmentTargets: [ResolvedCampaignTarget]) -> String {
        guard segmentTargets.count > 1,
              let position = segmentTargets.firstIndex(where: { $0.id == target.id }) else {
            return target.label
        }
        return "\(position + 1)/\(segmentTargets.count) \(target.label)"
    }

    private static func streetDisplayName(for target: ResolvedCampaignTarget?) -> String? {
        guard let target else { return nil }
        let explicitStreet = target.streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitStreet.isEmpty {
            return explicitStreet
        }

        let trimmed = target.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let noHouse = trimmed.replacingOccurrences(
            of: #"^\s*\d+[A-Za-z]?\s+"#,
            with: "",
            options: .regularExpression
        )
        let streetOnly = noHouse.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? noHouse
        return streetOnly.isEmpty ? nil : streetOnly
    }
}

struct DemoSessionConfigSheet: View {
    let campaigns: [CampaignV2]
    let defaultCampaignID: UUID
    let onStart: (DemoSessionLaunchConfiguration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCampaignID: UUID
    @State private var homeCount: Double = 20
    @State private var speed: DemoSessionSpeed = .medium
    @State private var pathMode: DemoPathMode = .pauseAtHomes
    @State private var recordingViewStyle: DemoRecordingViewStyle = .creatorOverlay
    @State private var cameraAngle: DemoCameraAngle = .normal3D
    @State private var hitPattern: DemoHitPattern = .allGreen

    init(
        campaigns: [CampaignV2],
        defaultCampaignID: UUID,
        onStart: @escaping (DemoSessionLaunchConfiguration) -> Void
    ) {
        self.campaigns = campaigns
        self.defaultCampaignID = defaultCampaignID
        self.onStart = onStart
        _selectedCampaignID = State(initialValue: defaultCampaignID)
        let defaultCount = campaigns.first(where: { $0.id == defaultCampaignID })?.addresses.count ?? 20
        _homeCount = State(initialValue: Double(max(1, defaultCount)))
    }

    private var selectedCampaign: CampaignV2? {
        campaigns.first(where: { $0.id == selectedCampaignID })
    }

    private var availableHomeCount: Int {
        max(1, selectedCampaign?.addresses.count ?? campaigns.first(where: { $0.id == defaultCampaignID })?.addresses.count ?? 1)
    }

    private var clampedHomeCount: Int {
        min(max(1, Int(homeCount)), availableHomeCount)
    }

    private func clampHomeCountToAvailable() {
        let upperBound = Double(max(1, availableHomeCount))
        guard homeCount.isFinite else {
            homeCount = upperBound
            return
        }
        homeCount = min(max(1, homeCount), upperBound)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("DEMO MODE")
                    .font(.flyrCaption)
                    .foregroundColor(.red)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Campaign")
                        .font(.flyrHeadline)
                    Picker("Campaign", selection: $selectedCampaignID) {
                        ForEach(campaigns) { campaign in
                            Text(campaign.name).tag(campaign.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Home count")
                            .font(.flyrHeadline)
                        Spacer()
                        Text("\(clampedHomeCount) / \(availableHomeCount)")
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                    }
                    if availableHomeCount > 1 {
                        Slider(
                            value: $homeCount,
                            in: 1...Double(availableHomeCount),
                            step: 1
                        )
                        .tint(.red)
                    } else {
                        Slider(value: .constant(1), in: 1...2, step: 1)
                            .tint(.red)
                            .disabled(true)
                            .opacity(0.45)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Speed")
                        .font(.flyrHeadline)
                    Picker("Speed", selection: $speed) {
                        ForEach(DemoSessionSpeed.allCases) { option in
                            Text(option.detailLabel).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Path mode")
                        .font(.flyrHeadline)
                    Picker("Path mode", selection: $pathMode) {
                        ForEach(DemoPathMode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(pathMode.detailLabel)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording view")
                        .font(.flyrHeadline)
                    Picker("Recording view", selection: $recordingViewStyle) {
                        ForEach(DemoRecordingViewStyle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(recordingViewStyle.detailLabel)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera angle")
                        .font(.flyrHeadline)
                    Picker("Camera angle", selection: $cameraAngle) {
                        ForEach(DemoCameraAngle.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(cameraAngle.detailLabel)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hit pattern")
                        .font(.flyrHeadline)
                    Picker("Hit pattern", selection: $hitPattern) {
                        ForEach(DemoHitPattern.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(hitPattern.detailLabel)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }

                Button {
                    guard let selectedCampaign else { return }
                    onStart(
                        DemoSessionLaunchConfiguration(
                            campaign: selectedCampaign,
                            homeCount: clampedHomeCount,
                            speed: speed,
                            pathMode: pathMode,
                            recordingViewStyle: recordingViewStyle,
                            cameraAngle: cameraAngle,
                            hitPattern: hitPattern
                        )
                    )
                    dismiss()
                } label: {
                    Text("Start Simulated Session")
                        .font(.flyrHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(selectedCampaign == nil)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Demo Session")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                clampHomeCountToAvailable()
            }
            .onChange(of: selectedCampaignID) { _, _ in
                clampHomeCountToAvailable()
            }
            .onChange(of: availableHomeCount) { _, _ in
                clampHomeCountToAvailable()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
