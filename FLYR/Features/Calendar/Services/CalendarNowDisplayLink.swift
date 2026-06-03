import Combine
import Foundation
import QuartzCore

@MainActor
final class CalendarNowDisplayLink: ObservableObject {
    @Published private(set) var now = Date()
    private var displayLink: CADisplayLink?
    private var lastPublishedSecond: Int = -1

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 2, preferred: 1)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        let date = Date()
        let second = Calendar.current.component(.second, from: date)
        guard second != lastPublishedSecond else { return }
        lastPublishedSecond = second
        now = date
    }

    deinit {
        displayLink?.invalidate()
    }
}

