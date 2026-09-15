import Foundation
import AudioToolbox

@MainActor enum WolfyFeedback {
    static func perform() {
        if UserDefaults.standard.object(forKey:"wolfy.haptics") as? Bool ?? true { HapticManager.light() }
        // System feedback follows the device's sound policy. Never reconfigure the call audio session.
        if UserDefaults.standard.bool(forKey:"wolfy.sound") { AudioServicesPlaySystemSound(1104) }
    }
}
