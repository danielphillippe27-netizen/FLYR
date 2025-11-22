import Foundation

/// Utility for generating URL-safe slugs for landing pages
public struct LandingPageSlugGenerator {
    /// Generate a slug from campaign title and address
    /// Format: /camp/{campaignSlug}/{addressSlug}
    /// - Parameters:
    ///   - campaignTitle: Campaign title
    ///   - addressFormatted: Formatted address string
    /// - Returns: URL-safe slug path
    public static func generateSlug(campaignTitle: String, addressFormatted: String) -> String {
        let campaignSlug = slugify(campaignTitle)
        let addressSlug = slugify(addressFormatted)
        return "/camp/\(campaignSlug)/\(addressSlug)"
    }
    
    /// Generate a slug from campaign ID and address ID
    /// Format: /camp/{campaignId}/{addressId}
    /// - Parameters:
    ///   - campaignId: Campaign UUID
    ///   - addressId: Address UUID
    /// - Returns: URL-safe slug path
    public static func generateSlug(campaignId: UUID, addressId: UUID) -> String {
        // Use short UUIDs for cleaner URLs
        let campaignShort = String(campaignId.uuidString.prefix(8))
        let addressShort = String(addressId.uuidString.prefix(8))
        return "/camp/\(campaignShort)/\(addressShort)"
    }
    
    /// Convert a string to a URL-safe slug
    /// - Parameter text: Input text
    /// - Returns: URL-safe slug
    private static func slugify(_ text: String) -> String {
        var slug = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Replace spaces and special chars with hyphens
        slug = slug.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        
        // Remove leading/trailing hyphens
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        // Limit length
        if slug.count > 50 {
            slug = String(slug.prefix(50))
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        
        // Fallback if empty
        if slug.isEmpty {
            slug = "page"
        }
        
        return slug
    }
    
    /// Parse a slug to extract campaign and address identifiers
    /// - Parameter slug: Slug path (e.g., "/camp/main/5875")
    /// - Returns: Tuple of (campaignSlug, addressSlug) or nil if invalid
    public static func parseSlug(_ slug: String) -> (campaignSlug: String, addressSlug: String)? {
        let components = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/")
        guard components.count >= 3, components[0] == "camp" else {
            return nil
        }
        return (campaignSlug: components[1], addressSlug: components[2])
    }
}

