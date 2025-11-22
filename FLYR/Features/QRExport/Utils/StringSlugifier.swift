import Foundation

/// Utility for slugifying strings for use in filenames
struct StringSlugifier {
    /// Convert a string to a URL-safe filename slug
    /// Example: "161 Sprucewood Crescent" -> "161_sprucewood_crescent"
    static func slugify(_ string: String) -> String {
        // Convert to lowercase
        var slug = string.lowercased()
        
        // Replace spaces and common separators with underscores
        slug = slug.replacingOccurrences(of: " ", with: "_")
        slug = slug.replacingOccurrences(of: "-", with: "_")
        slug = slug.replacingOccurrences(of: ",", with: "_")
        
        // Remove invalid filename characters
        let invalidChars = CharacterSet(charactersIn: "/:?<>\\|*\"'")
        slug = slug.components(separatedBy: invalidChars).joined(separator: "")
        
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

