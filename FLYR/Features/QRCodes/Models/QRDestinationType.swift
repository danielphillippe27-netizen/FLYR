import Foundation

/// QR Code destination types - defines what the QR code links to
public enum QRDestinationType: String, CaseIterable, Identifiable, CustomStringConvertible {
    case landingPage = "landing_page"
    case directLink = "direct_link"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .landingPage:
            return "Landing Page"
        case .directLink:
            return "URL"
        }
    }
    
    /// Returns whether this destination type requires a campaign to be selected
    public var requiresCampaign: Bool {
        switch self {
        case .landingPage:
            return true
        case .directLink:
            return false
        }
    }
    
    /// Returns whether this destination type requires a landing page to be selected
    public var requiresLandingPage: Bool {
        switch self {
        case .landingPage:
            return true
        case .directLink:
            return false
        }
    }
    
    /// Builds the appropriate URL for this destination type
    /// - Parameters:
    ///   - value: The destination value (URL, phone number, etc.)
    ///   - campaignId: Optional campaign ID
    ///   - landingPageId: Optional landing page ID
    /// - Returns: The complete URL string
    public func buildURL(
        value: String?,
        campaignId: UUID? = nil,
        landingPageId: UUID? = nil
    ) -> String {
        switch self {
        case .landingPage:
            // For landing page, use the slug-based redirect
            if let slug = value {
                return "https://flyrpro.app/q/\(slug)"
            } else {
                return "https://flyrpro.app/q/unknown"
            }
            
        case .directLink:
            // Direct URL - use as-is
            return value ?? "https://flyrpro.app"
        }
    }
    
    /// Returns placeholder text for the destination value input field
    public var valuePlaceholder: String {
        switch self {
        case .landingPage:
            return "Select from campaign"
        case .directLink:
            return "https://example.com"
        }
    }
    
    /// Returns the input field label
    public var valueLabel: String {
        switch self {
        case .landingPage:
            return "Select"
        case .directLink:
            return "URL"
        }
    }
}

