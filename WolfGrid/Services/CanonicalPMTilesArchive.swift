import Foundation
import zlib

/// Bounded PMTiles v3 reader for the MVT/gzip archives produced by our compiler.
/// Format: https://github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md
/// Reads tile bytes directly. It never expands MVT into GeoJSON.
final class CanonicalPMTilesArchive: @unchecked Sendable {
    enum ArchiveError: Error { case invalidArchive, unsupportedCompression, truncated, oversized }
    private struct Entry { var id: UInt64 = 0; var run: UInt64 = 0; var length = 0; var offset = 0 }
    private let bytes: Data
    private let leafOffset: Int
    private let tileOffset: Int
    private let internalCompression: UInt8
    private let tileCompression: UInt8
    private let root: [Entry]
    private let lock = NSLock()
    private var leaves: [Int: [Entry]] = [:]

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 127, String(data: data.prefix(7), encoding: .utf8) == "PMTiles", data[7] == 3,
              data[99] == 1, [1, 2].contains(data[97]), [1, 2].contains(data[98]) else { throw ArchiveError.invalidArchive }
        func integer(_ offset: Int) throws -> Int {
            let value = (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
            guard value <= UInt64(Int.max) else { throw ArchiveError.oversized }
            return Int(value)
        }
        let offset = try integer(8), length = try integer(16)
        guard offset <= data.count, length <= data.count - offset else { throw ArchiveError.truncated }
        bytes = data
        leafOffset = try integer(40); tileOffset = try integer(56)
        internalCompression = data[97]; tileCompression = data[98]
        root = try Self.directory(Self.decompress(Data(data[offset..<(offset + length)]), compression: data[97]))
    }

    func tile(z: Int, x: Int, y: Int) throws -> Data? {
        guard (0...26).contains(z), x >= 0, y >= 0, x < (1 << z), y < (1 << z) else { return nil }
        let id = Self.tileID(z: z, x: x, y: y)
        var entries = root
        for _ in 0..<4 {
            var low = 0, high = entries.count
            while low < high { let middle = (low + high) / 2; if entries[middle].id <= id { low = middle + 1 } else { high = middle } }
            guard low > 0 else { return nil }
            let entry = entries[low - 1]
            if entry.run > 0 {
                guard id - entry.id < entry.run else { return nil }
                return try Self.decompress(read(base: tileOffset, offset: entry.offset, length: entry.length), compression: tileCompression)
            }
            lock.lock(); let cached = leaves[entry.offset]; lock.unlock()
            if let cached { entries = cached } else {
                entries = try Self.directory(Self.decompress(read(base: leafOffset, offset: entry.offset, length: entry.length), compression: internalCompression))
                lock.lock()
                if leaves.count >= 32 { leaves.removeAll(keepingCapacity: true) }
                leaves[entry.offset] = entries
                lock.unlock()
            }
        }
        throw ArchiveError.invalidArchive
    }

    private func read(base: Int, offset: Int, length: Int) throws -> Data {
        guard base >= 0, offset >= 0, length >= 0, base <= bytes.count,
              offset <= bytes.count - base, length <= bytes.count - base - offset else { throw ArchiveError.truncated }
        return Data(bytes[(base + offset)..<(base + offset + length)])
    }

    static func tileID(z: Int, x: Int, y: Int) -> UInt64 {
        var x = x, y = y, distance: UInt64 = 0
        var scale = (1 << z) / 2
        while scale > 0 {
            let rx = (x & scale) > 0 ? 1 : 0, ry = (y & scale) > 0 ? 1 : 0
            distance += UInt64(scale) * UInt64(scale) * UInt64((3 * rx) ^ ry)
            if ry == 0 { if rx == 1 { x = scale - 1 - x; y = scale - 1 - y }; swap(&x, &y) }
            scale /= 2
        }
        return ((UInt64(1) << (2 * z)) - 1) / 3 + distance
    }

    private static func directory(_ data: Data) throws -> [Entry] {
        var cursor = 0
        func variable() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 64, by: 7) {
                guard cursor < data.count else { throw ArchiveError.truncated }
                let byte = data[cursor]; cursor += 1
                if shift == 63 && byte > 1 { throw ArchiveError.oversized }
                value |= UInt64(byte & 127) << shift
                if byte < 128 { return value }
            }
            throw ArchiveError.invalidArchive
        }
        func integer() throws -> Int { let value = try variable(); guard value <= UInt64(Int.max) else { throw ArchiveError.oversized }; return Int(value) }
        let count = try integer()
        guard count <= data.count / 4, count < 2_000_000 else { throw ArchiveError.oversized }
        var entries = Array(repeating: Entry(), count: count), last: UInt64 = 0
        for i in entries.indices { let delta = try variable(); guard delta <= UInt64.max - last else { throw ArchiveError.oversized }; last += delta; entries[i].id = last }
        for i in entries.indices { entries[i].run = try variable() }
        for i in entries.indices { entries[i].length = try integer() }
        for i in entries.indices {
            let offset = try integer()
            if offset == 0 {
                guard i > 0, entries[i - 1].offset <= Int.max - entries[i - 1].length else { throw ArchiveError.invalidArchive }
                entries[i].offset = entries[i - 1].offset + entries[i - 1].length
            } else { entries[i].offset = offset - 1 }
        }
        return entries
    }

    static func decompress(_ data: Data, compression: UInt8) throws -> Data {
        if compression == 1 { return data }
        guard compression == 2 else { throw ArchiveError.unsupportedCompression }
        guard data.count <= Int(UInt32.max) else { throw ArchiveError.oversized }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw ArchiveError.invalidArchive }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var output = Data(), chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let status = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(buffer.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let written = chunk.count - Int(stream.avail_out)
                guard output.count + written <= 64 * 1024 * 1024 else { throw ArchiveError.oversized }
                output.append(contentsOf: chunk.prefix(written))
                if status == Z_STREAM_END { return output }
                guard status == Z_OK, written > 0 else { throw ArchiveError.invalidArchive }
            }
        }
    }
}
