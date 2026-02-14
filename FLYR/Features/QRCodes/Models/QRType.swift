import Foundation

/// QR code type for batch configuration
public enum QRType: String, Codable, CaseIterable {
    case directLink = "direct_link"
    case map = "map"
    case customURL = "custom_url"
    
    /// Display label for UI
    public var displayLabel: String {
        switch self {
        case .directLink:
            return "Direct Link"
        case .map:
            return "FLYR Map"
        case .customURL:
            return "Custom URL"
        }
    }
    
    /// System icon name for UI
    public var iconName: String {
        switch self {
        case .directLink:
            return "link"
        case .map:
            return "map.fill"
        case .customURL:
            return "pencil.line"
        }
    }
    
    /// Description text for UI
    public var description: String {
        switch self {
        case .directLink:
            return "Link directly to your website"
        case .map:
            return "Link to FLYR interactive map"
        case .customURL:
            return "Link to any custom URL"
        }
    }
}



