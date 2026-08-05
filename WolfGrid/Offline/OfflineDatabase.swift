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

    private static let storageDirectoryName = "WolfGridOffline"
    private static let legacyStorageDirectoryName = "FLYROffline"
    private static let databaseFileName = "wolfgrid-offline.sqlite"
    private static let legacyDatabaseFileName = "flyr-offline.sqlite"

    let dbQueue: DatabaseQueue
    let storageDirectory: URL

    private init() {
        let initializedQueue: DatabaseQueue
        let initializedStorageDirectory: URL
        do {
            let rootURL = try Self.makeStorageDirectory()
            let databaseURL = try Self.makeDatabaseURL(in: rootURL)
            let queue = try DatabaseQueue(path: databaseURL.path)
            try OfflineMigrations.migrator().migrate(queue)
            initializedQueue = queue
            initializedStorageDirectory = rootURL
        } catch {
            print("⚠️ [OfflineDatabase] Persistent store failed (\(error)). Falling back to in-memory — offline data will not persist across sessions.")
            do {
                let queue = try DatabaseQueue()
                try OfflineMigrations.migrator().migrate(queue)
                initializedQueue = queue
                initializedStorageDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(Self.storageDirectoryName, isDirectory: true)
            } catch let memoryError {
                preconditionFailure("[OfflineDatabase] In-memory fallback also failed: \(memoryError)")
            }
        }
        dbQueue = initializedQueue
        storageDirectory = initializedStorageDirectory
    }

    private static func makeStorageDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let rootURL = baseURL.appendingPathComponent(storageDirectoryName, isDirectory: true)
        let legacyRootURL = baseURL.appendingPathComponent(legacyStorageDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: rootURL.path),
           FileManager.default.fileExists(atPath: legacyRootURL.path) {
            try FileManager.default.moveItem(at: legacyRootURL, to: rootURL)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private static func makeDatabaseURL(in rootURL: URL) throws -> URL {
        let databaseURL = rootURL.appendingPathComponent(databaseFileName)
        let legacyDatabaseURL = rootURL.appendingPathComponent(legacyDatabaseFileName)
        if !FileManager.default.fileExists(atPath: databaseURL.path),
           FileManager.default.fileExists(atPath: legacyDatabaseURL.path) {
            try FileManager.default.moveItem(at: legacyDatabaseURL, to: databaseURL)
        }
        return databaseURL
    }
}
