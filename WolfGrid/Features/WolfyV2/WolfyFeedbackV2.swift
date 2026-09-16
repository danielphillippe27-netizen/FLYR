import UIKit

/// Foreground-only feedback. Never configures the audio session or plays a howl unexpectedly.
@MainActor final class WolfyFeedbackV2 {
    static let shared = WolfyFeedbackV2()
    private var task: Task<Void, Never>?
    private var personalUntil = Date.distantPast
    private var teamUntil = Date.distantPast
    private let light = UIImpactFeedbackGenerator(style: .soft)
    private let strong = UIImpactFeedbackGenerator(style: .medium)
    private init() {}
    func personal(kind: String, mode: WolfyHapticMode) {
        guard mode != .off, UIApplication.shared.applicationState == .active else { return }
        task?.cancel()
        let pulse: [(Double, Float)]
        switch kind {
        case "door": pulse = [(0,0.18)]
        case "conversation": pulse = [(0,0.25),(0.10,0.25)]
        case "follow_up": pulse = [(0,0.45)]
        case "lead": pulse = [(0,0.65),(0.14,0.25)]
        case "appointment": pulse = [(0,0.75),(0.23,0.75)]
        case "doors_10": pulse = [(0,0.3),(0.10,0.3),(0.20,0.3)]
        case "evolution": pulse = [(0,0.3),(0.13,0.5),(0.35,0.85)]
        case "personal_best": pulse = [(0,0.7),(0.18,0.3),(0.4,0.9)]
        default: pulse = [(0,0.6),(0.15,0.3),(0.32,0.65)]
        }
        personalUntil = Date().addingTimeInterval((pulse.last?.0 ?? 0)+0.5)
        task = Task { [weak self] in
            var previous = 0.0
            for (offset,intensity) in pulse {
                do { try await Task.sleep(for: .seconds(offset-previous)) } catch { return }
                guard !Task.isCancelled, UIApplication.shared.applicationState == .active, let self else { return }
                let value = intensity * (mode == .subtle ? 0.5 : 1)
                if value > 0.4 { self.strong.impactOccurred(intensity:CGFloat(value)) }
                else { self.light.impactOccurred(intensity:CGFloat(value)) }
                previous = offset
            }
        }
    }
    func team(mode: WolfyHapticMode, enabled: Bool, now: Date = Date()) {
        guard mode != .off, enabled, UIApplication.shared.applicationState == .active,
              now >= personalUntil, now >= teamUntil else { return }
        teamUntil = now.addingTimeInterval(60)
        light.impactOccurred(intensity: 0.12)
    }
    func stop() { task?.cancel(); task = nil }
}
