import Foundation

/// Utility for slugifying strings for use in filenames
struct StringSlugifier {
    /// Convert a string to a URL-safe filename slug
    /// Example: "161 Sprucewood Crescent" -> "161_sprucewood_crescent"
    static func slugify(_ string: String) -> String {
        // Normalize and keep only lowercase ASCII letters and digits.
        var slug = string
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        
        // Remove multiple consecutive underscores
        while slug.contains("__") {
            slug = slug.replacingOccurrences(of: "__", with: "_")
        }
        
        // Remove leading/trailing underscores
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        
        // Limit length to 100 characters
        if slug.count > 100 {
            slug = String(slug.prefix(100))
            slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        }
        
        // If empty after processing, use a default
        if slug.isEmpty {
            slug = "address"
        }
        
        return slug
    }
}
