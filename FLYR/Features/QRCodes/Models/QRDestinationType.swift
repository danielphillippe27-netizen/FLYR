import Foundation

/// QR Code destination types - defines what the QR code links to
public enum QRDestinationType: String, CaseIterable, Identifiable, CustomStringConvertible {
    case directLink = "direct_link"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .directLink:
            return "URL"
        }
    }
    
    /// Returns whether this destination type requires a campaign to be selected
    public var requiresCampaign: Bool {
        switch self {
        case .directLink:
            return false
        }
    }
    
    /// Returns whether this destination type requires a landing page to be selected
    public var requiresLandingPage: Bool {
        false
    }
    
    /// Builds the appropriate URL for this destination type
    /// - Parameters:
    ///   - value: The destination value (URL)
    ///   - campaignId: Optional campaign ID (unused for direct link)
    ///   - landingPageId: Optional landing page ID (unused for direct link)
    /// - Returns: The complete URL string
    public func buildURL(
        value: String?,
        campaignId: UUID? = nil,
        landingPageId: UUID? = nil
    ) -> String {
        switch self {
        case .directLink:
            return value ?? "https://flyrpro.app"
        }
    }
    
    /// Returns placeholder text for the destination value input field
    public var valuePlaceholder: String {
        switch self {
        case .directLink:
            return "https://example.com"
        }
    }
    
    /// Returns the input field label
    public var valueLabel: String {
        switch self {
        case .directLink:
            return "URL"
        }
    }
}
