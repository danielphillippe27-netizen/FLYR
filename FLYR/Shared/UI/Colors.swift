import SwiftUI

extension Color {
    // MARK: - Base Colors (Monochrome)
    
    /// Primary background - white in light mode, near-black in dark mode
    static let bg = Color(uiColor: .systemBackground)
    
    /// Secondary background - light gray in light mode, dark gray in dark mode
    static let bgSecondary = Color(uiColor: .secondarySystemBackground)
    
    /// Tertiary background - lighter gray in light mode, darker gray in dark mode
    static let bgTertiary = Color(uiColor: .tertiarySystemBackground)
    
    // MARK: - Text Colors (WCAG AA Compliant)
    
    /// Primary text - dark charcoal in light mode, off-white in dark mode
    static let text = Color(uiColor: .label)
    
    /// Secondary text - medium gray in light mode, light gray in dark mode
    static let muted = Color(uiColor: .secondaryLabel)
    
    /// Tertiary text - light gray in light mode, medium gray in dark mode
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    
    // MARK: - Border Colors
    
    /// Standard border - light gray in light mode, dark gray in dark mode
    static let border = Color(uiColor: .separator)
    
    // MARK: - Semantic Colors
    
    /// Success state - green
    static let success = Color(red: 0.20, green: 0.78, blue: 0.35) // #34C759
    
    /// Warning state - orange
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.04) // #FF9F0A
    
    /// Error state - red
    static let error = Color(red: 1.0, green: 0.23, blue: 0.19) // #FF3B30
    
    /// Info state - blue
    static let info = Color(red: 0.04, green: 0.52, blue: 1.0) // #0A84FF
    
    // MARK: - Accent Color (Dynamic)
    
    /// Default accent color - Electric Red
    static let accentDefault = Color(red: 1.0, green: 0.23, blue: 0.19) // #FF3B30
    
    // MARK: - Legacy Support (Deprecated)
    
    @available(*, deprecated, message: "Use .accent instead")
    static let brandPrimary = accentDefault
    
    @available(*, deprecated, message: "Use .bg instead")
    static let backgroundPrimary = bg
    
    @available(*, deprecated, message: "Use .text instead")
    static let textPrimary = text
    
    @available(*, deprecated, message: "Use .muted instead")
    static let textSecondary = muted
}

// MARK: - Color Utilities

extension Color {
    /// Create color from hex string
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

