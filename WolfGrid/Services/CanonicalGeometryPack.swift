import Foundation

/// Immutable WGP1 package: indexed, independently compressed exact WGS84 WKB
/// shapes. A field operation inflates only the requested feature.
final class CanonicalGeometryPack: Sendable {
    enum PackError: Error { case invalidHeader, invalidRecord, truncated }
    private struct Entry: Sendable { let offset: Int; let length: Int }
    private let bytes: Data
    private let entries: [String: Entry]

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 8, Data(data.prefix(4)) == Data("WGP1".utf8) else { throw PackError.invalidHeader }
        func uint16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func uint32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        let count = uint32(4)
        guard count <= (data.count - 8) / 7 else { throw PackError.invalidHeader }
        var parsed: [String: Entry] = [:]
        var cursor = 8
        for _ in 0..<count {
            guard cursor <= data.count - 2 else { throw PackError.truncated }
            let idLength = uint16(cursor); cursor += 2
            guard idLength > 0, idLength <= data.count - cursor, data.count - cursor - idLength >= 4,
                  let id = String(data: data[cursor..<(cursor + idLength)], encoding: .utf8) else { throw PackError.invalidRecord }
            cursor += idLength
            let length = uint32(cursor); cursor += 4
            guard length > 0, length <= data.count - cursor, parsed[id] == nil else { throw PackError.invalidRecord }
            parsed[id] = Entry(offset: cursor, length: length)
            cursor += length
        }
        guard cursor == data.count else { throw PackError.invalidRecord }
        bytes = data
        entries = parsed
    }

    var count: Int { entries.count }
    var ids: [String] { Array(entries.keys) }

    func wkb(for id: String) throws -> Data? {
        guard let entry = entries[id] else { return nil }
        let data = try CanonicalPMTilesArchive.decompress(
            Data(bytes[entry.offset..<(entry.offset + entry.length)]), compression: 2
        )
        guard data.count >= 5, data[0] == 0 || data[0] == 1 else { throw PackError.invalidRecord }
        return data
    }
}
