import Foundation
import GRDB

enum OfflineDateCodec {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return fractionalFormatter.date(from: normalized)
            ?? standardFormatter.date(from: normalized)
    }
}

enum OfflineJSONCodec {
    static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string,
              let data = string.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder.supabaseDates
        return try? decoder.decode(T.self, from: data)
    }
}

final class OfflineDatabase {
    static let shared = OfflineDatabase()

    let dbQueue: DatabaseQueue

    private init() {
        let initializedQueue: DatabaseQueue
        do {
            let rootURL = try Self.makeStorageDirectory()
            let databaseURL = rootURL.appendingPathComponent("flyr-offline.sqlite")
            let queue = try DatabaseQueue(path: databaseURL.path)
            try OfflineMigrations.migrator().migrate(queue)
            initializedQueue = queue
        } catch {
            print("⚠️ [OfflineDatabase] Persistent store failed (\(error)). Falling back to in-memory — offline data will not persist across sessions.")
            do {
                let queue = try DatabaseQueue()
                try OfflineMigrations.migrator().migrate(queue)
                initializedQueue = queue
            } catch let memoryError {
                preconditionFailure("[OfflineDatabase] In-memory fallback also failed: \(memoryError)")
            }
        }
        dbQueue = initializedQueue
    }

    private static func makeStorageDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent("FLYROffline", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }
}
