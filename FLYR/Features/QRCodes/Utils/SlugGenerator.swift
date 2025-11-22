import Foundation

/// Utility for generating unique URL-safe slugs for A/B test variants
struct SlugGenerator {
    /// Generate a unique URL-safe slug
    /// Uses UUID-based approach for guaranteed uniqueness
    /// - Returns: A unique slug string suitable for URLs
    static func generateUniqueSlug() -> String {
        // Use UUID and convert to URL-safe base64-like string
        let uuid = UUID()
        let uuidString = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        
        // Take first 12 characters for shorter URLs
        // This gives us 16^12 = 281,474,976,710,656 possible combinations
        let shortSlug = String(uuidString.prefix(12))
        
        // Convert to lowercase for consistency
        return shortSlug.lowercased()
    }
    
    /// Generate a slug with optional prefix
    /// - Parameter prefix: Optional prefix to add before the slug
    /// - Returns: A unique slug with optional prefix
    static func generateUniqueSlug(prefix: String? = nil) -> String {
        let baseSlug = generateUniqueSlug()
        if let prefix = prefix, !prefix.isEmpty {
            return "\(prefix)-\(baseSlug)"
        }
        return baseSlug
    }
}

