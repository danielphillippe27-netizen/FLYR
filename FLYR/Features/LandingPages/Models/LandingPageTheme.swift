import Foundation
import SwiftUI

/// Preset theme definitions for landing page designer
public enum LandingPageTheme: String, CaseIterable, Identifiable {
    case air = "Air"
    case astrid = "Astrid"
    case aura = "Aura"
    case breeze = "Breeze"
    case grid = "Grid"
    case haven = "Haven"
    case lake = "Lake"
    case mineral = "Mineral"
    case custom = "Custom"
    
    public var id: String { rawValue }
    
    /// Display name for the theme
    public var displayName: String {
        rawValue
    }
    
    /// Default wallpaper color for this theme (hex string)
    public var defaultWallpaperColor: String {
        switch self {
        case .air:
            return "#F5F5F7" // Light gray
        case .astrid:
            return "#1C1C1E" // Dark gray
        case .aura:
            return "#6366F1" // Indigo
        case .breeze:
            return "#06B6D4" // Cyan
        case .grid:
            return "#FFFFFF" // White
        case .haven:
            return "#10B981" // Green
        case .lake:
            return "#3B82F6" // Blue
        case .mineral:
            return "#8B5CF6" // Purple
        case .custom:
            return "#FFFFFF"
        }
    }
    
    /// Default title color for this theme (hex string)
    public var defaultTitleColor: String {
        switch self {
        case .air, .grid, .custom:
            return "#000000"
        case .astrid:
            return "#FFFFFF"
        case .aura, .breeze, .haven, .lake, .mineral:
            return "#FFFFFF"
        }
    }
    
    /// Default text color for this theme (hex string)
    public var defaultTextColor: String {
        switch self {
        case .air, .grid, .custom:
            return "#666666"
        case .astrid:
            return "#E5E5EA"
        case .aura, .breeze, .haven, .lake, .mineral:
            return "#F5F5F7"
        }
    }
    
    /// Default button style for this theme
    public var defaultButtonStyle: String {
        switch self {
        case .air, .grid:
            return "Solid"
        case .astrid, .aura, .breeze, .haven, .lake, .mineral:
            return "Glass"
        case .custom:
            return "Solid"
        }
    }
    
    /// Default button background color (hex string)
    public var defaultButtonBackgroundColor: String {
        switch self {
        case .air:
            return "#007AFF"
        case .astrid:
            return "#FFFFFF"
        case .aura:
            return "#FFFFFF"
        case .breeze:
            return "#FFFFFF"
        case .grid:
            return "#000000"
        case .haven:
            return "#FFFFFF"
        case .lake:
            return "#FFFFFF"
        case .mineral:
            return "#FFFFFF"
        case .custom:
            return "#007AFF"
        }
    }
    
    /// Default button text color (hex string)
    public var defaultButtonTextColor: String {
        switch self {
        case .air, .grid:
            return "#FFFFFF"
        case .astrid, .aura, .breeze, .haven, .lake, .mineral:
            return "#000000"
        case .custom:
            return "#FFFFFF"
        }
    }
    
    /// Default button corner radius
    public var defaultButtonCornerRadius: Double {
        switch self {
        case .air, .astrid, .aura:
            return 16.0
        case .breeze, .grid:
            return 12.0
        case .haven, .lake, .mineral:
            return 20.0
        case .custom:
            return 12.0
        }
    }
    
    /// Preview background gradient colors (for theme cards)
    public var previewGradient: [Color] {
        switch self {
        case .air:
            return [Color(hex: "#F5F5F7"), Color(hex: "#E5E5EA")]
        case .astrid:
            return [Color(hex: "#1C1C1E"), Color(hex: "#2C2C2E")]
        case .aura:
            return [Color(hex: "#6366F1"), Color(hex: "#8B5CF6")]
        case .breeze:
            return [Color(hex: "#06B6D4"), Color(hex: "#3B82F6")]
        case .grid:
            return [Color(hex: "#FFFFFF"), Color(hex: "#F5F5F7")]
        case .haven:
            return [Color(hex: "#10B981"), Color(hex: "#059669")]
        case .lake:
            return [Color(hex: "#3B82F6"), Color(hex: "#2563EB")]
        case .mineral:
            return [Color(hex: "#8B5CF6"), Color(hex: "#6366F1")]
        case .custom:
            return [Color(hex: "#FFFFFF"), Color(hex: "#F5F5F7")]
        }
    }
    
    /// Create metadata with theme defaults
    public func toMetadata() -> LandingPageMetadata {
        var metadata = LandingPageMetadata()
        metadata.themeStyle = rawValue
        metadata.wallpaperStyle = "Fill"
        metadata.wallpaperColor = defaultWallpaperColor
        metadata.titleColor = defaultTitleColor
        metadata.pageTextColor = defaultTextColor
        metadata.buttonStyle = defaultButtonStyle
        metadata.buttonBackgroundColor = defaultButtonBackgroundColor
        metadata.buttonTextColor = defaultButtonTextColor
        metadata.buttonCornerRadius = defaultButtonCornerRadius
        return metadata
    }
}

