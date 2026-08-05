import Foundation

// MARK: - Secrets Configuration

/// Configuration for API keys and secrets
/// All tokens are read from Info.plist for single source of truth
enum Secrets {
    /// Mapbox access token - stored in Info.plist under MBXAccessToken
    static var mapboxToken: String {
        Config.mapboxAccessToken
    }
}
