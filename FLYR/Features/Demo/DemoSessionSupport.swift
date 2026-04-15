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
        case .fast: return 0.4
        }
    }

    var detailLabel: String {
        "\(title) (\(secondsPerHome.formattedDemoSpeed)s per home)"
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
        return []
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

    private var runTask: Task<Void, Never>?
    private var suppressFinishCallback = false

    func start(
        steps: [DemoSessionStep],
        speed: DemoSessionSpeed,
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
                onTargetWillAdvance(target)

                let totalDuration = speed.secondsPerHome
                let moveDuration = max(0.12, totalDuration * 0.62)
                let pulseDuration = max(0.08, totalDuration - moveDuration)
                let travelPath = step.travelPath

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
                    try? await Task.sleep(nanoseconds: UInt64(moveDuration * 1_000_000_000))
                }

                try? await Task.sleep(nanoseconds: UInt64(pulseDuration * 1_000_000_000))
                guard !Task.isCancelled else {
                    self.finish(.stopped, onFinish: onFinish)
                    return
                }

                await onTargetHit(target)
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
        isRunning = false
        if notify {
            onFinish?(.stopped)
        }
    }

    private func finish(_ reason: FinishReason, onFinish: @escaping (FinishReason) -> Void) {
        runTask = nil
        currentTarget = nil
        isRunning = false
        if !suppressFinishCallback {
            onFinish(reason)
        }
        suppressFinishCallback = false
    }

    private func interpolate(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        progress: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress
        )
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
                        Text("\(Int(homeCount)) / \(availableHomeCount)")
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: $homeCount,
                        in: Double(min(10, availableHomeCount))...Double(availableHomeCount),
                        step: 1
                    )
                        .tint(.red)
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

                Button {
                    guard let selectedCampaign else { return }
                    onStart(
                        DemoSessionLaunchConfiguration(
                            campaign: selectedCampaign,
                            homeCount: Int(homeCount),
                            speed: speed
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
            .onChange(of: selectedCampaignID) { _, _ in
                homeCount = Double(availableHomeCount)
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
