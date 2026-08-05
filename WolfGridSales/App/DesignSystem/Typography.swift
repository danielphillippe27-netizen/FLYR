// MARK: - Rollback
// To revert: (1) Set AppFont.isInterEnabled = false for instant fallback, or
// (2) Remove UIAppFonts key and entries from Info.plist, remove the four Inter .ttf
// files from the project and Copy Bundle Resources, delete this file, and revert
// the two font changes in StatsView (back to .font(.system(...))).

import SwiftUI

/// Centralized app typography. Toggle Inter via `AppFont.isInterEnabled`.
enum AppFont {
    /// Set to false to fall back to system fonts (e.g. rollback or if Inter fails to load).
    static var isInterEnabled: Bool = true

    private static let interRegular = "Inter-Regular"
    private static let interMedium = "Inter-Medium"
    private static let interSemiBold = "Inter-SemiBold"
    private static let interBold = "Inter-Bold"

    static func heading(_ size: CGFloat) -> Font {
        if isInterEnabled {
            return .custom(interSemiBold, size: size)
        }
        return .system(size: size, weight: .semibold)
    }

    static func title(_ size: CGFloat) -> Font {
        if isInterEnabled {
            return .custom(interBold, size: size)
        }
        return .system(size: size, weight: .bold)
    }

    static func body(_ size: CGFloat) -> Font {
        if isInterEnabled {
            return .custom(interRegular, size: size)
        }
        return .system(size: size, weight: .regular)
    }

    static func label(_ size: CGFloat) -> Font {
        if isInterEnabled {
            return .custom(interMedium, size: size)
        }
        return .system(size: size, weight: .medium)
    }

    static func number(_ size: CGFloat) -> Font {
        if isInterEnabled {
            return .custom(interMedium, size: size)
        }
        return .system(size: size, weight: .medium)
    }
}
