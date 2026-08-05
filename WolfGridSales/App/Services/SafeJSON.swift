import Foundation

/// Safe JSON sanitization utility for handling non-serializable objects
/// Converts UUIDs, Dates, URLs, and other types to JSON-safe strings
enum SafeJSON {
    
    /// Recursively sanitize a value to be JSON-safe
    /// - Parameter value: Any value that might contain non-serializable objects
    /// - Returns: A JSON-safe value (String, Number, Bool, Array, Dictionary, or NSNull)
    static func sanitize(_ value: Any?) -> Any {
        guard let value = value else {
            return NSNull()
        }
        
        // Handle NSNull explicitly
        if value is NSNull {
            return NSNull()
        }
        
        // Handle primitives that are already JSON-safe
        if value is String || value is NSString {
            return value
        }
        
        if value is NSNumber {
            return value
        }
        
        if value is Bool {
            return value
        }
        
        // Handle UUID -> String
        if let uuid = value as? UUID {
            return uuid.uuidString
        }
        
        // Handle Date -> ISO8601 String
        if let date = value as? Date {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
        
        // Handle URL -> String
        if let url = value as? URL {
            return url.absoluteString
        }
        
        // Handle Data -> Base64 String
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        
        // Handle Array recursively
        if let array = value as? [Any] {
            return array.map { sanitize($0) }
        }
        
        // Handle Dictionary recursively
        if let dict = value as? [String: Any] {
            var sanitized: [String: Any] = [:]
            for (key, val) in dict {
                sanitized[key] = sanitize(val)
            }
            return sanitized
        }
        
        // Handle NSDictionary recursively
        if let nsDict = value as? NSDictionary {
            var sanitized: [String: Any] = [:]
            for (key, val) in nsDict {
                if let stringKey = key as? String {
                    sanitized[stringKey] = sanitize(val)
                } else {
                    // Convert non-string keys to strings
                    sanitized["\(key)"] = sanitize(val)
                }
            }
            return sanitized
        }
        
        // Handle NSArray recursively
        if let nsArray = value as? NSArray {
            var sanitized: [Any] = []
            for item in nsArray {
                sanitized.append(sanitize(item))
            }
            return sanitized
        }
        
        // Handle CLLocationCoordinate2D
        if let coord = value as? CLLocationCoordinate2D {
            return [
                "latitude": coord.latitude,
                "longitude": coord.longitude
            ]
        }
        
        // Fallback: convert to string description
        // This handles any custom objects we haven't explicitly handled
        return "\(value)"
    }
    
    /// Check if a value is valid for JSONSerialization
    /// - Parameter value: Value to check
    /// - Returns: true if the value can be serialized to JSON
    static func isValidJSONObject(_ value: Any) -> Bool {
        return JSONSerialization.isValidJSONObject(value)
    }
    
    /// Safely serialize value to JSON data
    /// - Parameter value: Value to serialize
    /// - Returns: JSON data if successful, nil otherwise
    static func data(from value: Any, options: JSONSerialization.WritingOptions = []) -> Data? {
        let sanitized = sanitize(value)
        
        // Double-check that sanitization worked
        guard JSONSerialization.isValidJSONObject(sanitized) else {
            print("⚠️ [SafeJSON] Sanitized value is still not valid for JSON serialization")
            return nil
        }
        
        do {
            return try JSONSerialization.data(withJSONObject: sanitized, options: options)
        } catch {
            print("❌ [SafeJSON] Failed to serialize: \(error)")
            return nil
        }
    }
}

// MARK: - Import for CLLocationCoordinate2D

import CoreLocation
