import Foundation
import GRDB

enum OfflineDateCodec {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return formatter.date(from: string)
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
        do {
            let rootURL = try Self.makeStorageDirectory()
            let databaseURL = rootURL.appendingPathComponent("flyr-offline.sqlite")
            dbQueue = try DatabaseQueue(path: databaseURL.path)
            try OfflineMigrations.migrator().migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize offline database: \(error)")
        }
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
