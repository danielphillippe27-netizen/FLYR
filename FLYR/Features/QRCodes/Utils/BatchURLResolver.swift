import Foundation

/// Utility for resolving batch URLs based on QR type
public struct BatchURLResolver {
    /// Resolve the target URL for a batch
    /// - Parameters:
    ///   - batch: The batch configuration
    ///   - userDefaultWebsite: User's default website URL (optional)
    ///   - addressId: Optional address ID to append as query parameter
    /// - Returns: The resolved URL string
    public static func resolveBatchURL(
        _ batch: Batch,
        userDefaultWebsite: String? = nil,
        addressId: UUID? = nil
    ) -> String {
        let baseURL: String
        
        switch batch.qrType {
        case .map:
            baseURL = "https://flyr.app/map/\(batch.id.uuidString)"
            
        case .customURL:
            guard let customURL = batch.customURL, !customURL.isEmpty else {
                // Fallback if custom URL is missing
                return "https://flyr.app"
            }
            baseURL = customURL
            
        case .directLink:
            // Use user's default website or fallback to flyr.app
            if let website = userDefaultWebsite, !website.isEmpty {
                baseURL = website
            } else {
                baseURL = "https://flyr.app"
            }
        }
        
        // Append address ID as query parameter if provided
        if let addressId = addressId {
            let separator = baseURL.contains("?") ? "&" : "?"
            return "\(baseURL)\(separator)addr=\(addressId.uuidString)"
        }
        
        return baseURL
    }
}



