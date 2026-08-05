import Foundation

/// Utility for generating unique slugs for QR codes
public struct QRSlugGenerator {
    /// Generate a random alphanumeric slug of specified length
    /// - Parameter length: Length of the slug (default: 8)
    /// - Returns: Random alphanumeric string
    public static func generate(length: Int = 8) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
    
    /// Generate a lowercase alphanumeric slug (URL-safe)
    /// - Parameter length: Length of the slug (default: 8)
    /// - Returns: Random lowercase alphanumeric string
    public static func generateLowercase(length: Int = 8) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in characters.randomElement()! })
    }
}


