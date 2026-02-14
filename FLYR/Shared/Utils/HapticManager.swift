import UIKit

/// Central haptic feedback for the app. Use for tab switches, buttons, success/error, segmented controls, etc.
enum HapticManager {

    // MARK: - Impact (buttons, taps, selections)

    /// Tab switches
    static func tabSwitch() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
    }

    /// General button presses, segmented control changes, campaign/farm selection
    static func light() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    /// Alias for light(); used by shared button styles and pressAnimation()
    static func lightImpact() {
        light()
    }

    /// Start Session primary action
    static func medium() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }

    /// Door tap in session, subtle interactions
    static func soft() {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()
    }

    /// Pull to refresh completed
    static func rigid() {
        let impact = UIImpactFeedbackGenerator(style: .rigid)
        impact.impactOccurred()
    }

    // MARK: - Notification (success / error)

    /// Save, complete, success actions
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    /// Error actions
    static func error() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
    }

    /// Warning (optional)
    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }
}
