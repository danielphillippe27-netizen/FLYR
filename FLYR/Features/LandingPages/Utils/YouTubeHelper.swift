import Foundation

/// Helper utilities for YouTube URL parsing and thumbnail generation
public struct YouTubeHelper {
    /// Extract YouTube video ID from various URL formats
    /// Supports:
    /// - https://www.youtube.com/watch?v=VIDEO_ID
    /// - https://youtube.com/watch?v=VIDEO_ID
    /// - https://youtu.be/VIDEO_ID
    /// - https://www.youtube.com/embed/VIDEO_ID
    /// - http:// variants
    public static func extractYouTubeId(from urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        
        // Patterns to match various YouTube URL formats
        let patterns = [
            #"youtube\.com/watch\?v=([\w-]+)"#,
            #"youtu\.be/([\w-]+)"#,
            #"youtube\.com/embed/([\w-]+)"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(urlString.startIndex..., in: urlString)
                if let match = regex.firstMatch(in: urlString, options: [], range: range),
                   let videoIdRange = Range(match.range(at: 1), in: urlString) {
                    return String(urlString[videoIdRange])
                }
            }
        }
        
        return nil
    }
    
    /// Generate YouTube thumbnail URL from video ID
    /// Returns: https://img.youtube.com/vi/{videoId}/maxresdefault.jpg
    public static func youtubeThumbnailURL(videoId: String) -> String {
        return "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg"
    }
    
    /// Validate YouTube URL format
    public static func isValidYouTubeURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty else { return false }
        
        let patterns = [
            #"^https?://(www\.)?youtube\.com/watch\?v=[\w-]+"#,
            #"^https?://youtu\.be/[\w-]+"#,
            #"^https?://(www\.)?youtube\.com/embed/[\w-]+"#
        ]
        
        for pattern in patterns {
            if urlString.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Get YouTube thumbnail URL from a YouTube URL string
    /// Returns nil if URL is invalid, otherwise returns thumbnail URL
    public static func thumbnailURL(from urlString: String) -> String? {
        guard let videoId = extractYouTubeId(from: urlString) else {
            return nil
        }
        return youtubeThumbnailURL(videoId: videoId)
    }
}


