import Foundation

/// Field geometry represented as native coordinates, not a rendered tile or a
/// campaign-wide GeoJSON collection. Nested collections retain their WKB type.
indirect enum CanonicalWKBGeometry: Equatable, Sendable {
    case point([Double])
    case lineString([[Double]])
    case polygon([[[Double]]])
    case multiPoint([CanonicalWKBGeometry])
    case multiLineString([CanonicalWKBGeometry])
    case multiPolygon([CanonicalWKBGeometry])
    case collection([CanonicalWKBGeometry])
}

enum CanonicalWKBError: Error { case invalid, truncated, oversized }

/// Exact binary cache representation for native field edits. Coordinates keep
/// their full precision, including holes and separate multipolygon components.
struct CanonicalWKBWriter {
    private var bytes = Data()

    static func encode(_ geometry: CanonicalWKBGeometry) throws -> Data {
        var writer = Self()
        try writer.write(geometry, depth: 0)
        guard writer.bytes.count <= 64 * 1024 * 1024 else { throw CanonicalWKBError.oversized }
        return writer.bytes
    }

    private mutating func integer(_ value: Int) throws {
        guard value >= 0, value <= Int(UInt32.max) else { throw CanonicalWKBError.oversized }
        let number = UInt32(value)
        for shift in stride(from: 0, to: 32, by: 8) { bytes.append(UInt8(truncatingIfNeeded: number >> shift)) }
    }

    private mutating func coordinate(_ point: [Double], dimension: Int) throws {
        guard point.count == dimension, point.allSatisfy(\.isFinite) else { throw CanonicalWKBError.invalid }
        for number in point {
            let bits = number.bitPattern
            for shift in stride(from: 0, to: 64, by: 8) { bytes.append(UInt8(truncatingIfNeeded: bits >> shift)) }
        }
    }

    private mutating func line(_ points: [[Double]], dimension: Int) throws {
        try integer(points.count)
        for point in points { try coordinate(point, dimension: dimension) }
    }

    private mutating func write(_ geometry: CanonicalWKBGeometry, depth: Int) throws {
        guard depth <= 16, bytes.count <= 64 * 1024 * 1024 else { throw CanonicalWKBError.oversized }
        let kind: Int
        let dimension: Int
        switch geometry {
        case .point(let point): kind = 1; dimension = point.count
        case .lineString(let points): kind = 2; dimension = points.first?.count ?? 2
        case .polygon(let rings): kind = 3; dimension = rings.first?.first?.count ?? 2
        case .multiPoint: kind = 4; dimension = 2
        case .multiLineString: kind = 5; dimension = 2
        case .multiPolygon: kind = 6; dimension = 2
        case .collection: kind = 7; dimension = 2
        }
        guard (2...4).contains(dimension) else { throw CanonicalWKBError.invalid }
        bytes.append(1)
        try integer(kind + (dimension == 3 ? 1000 : dimension == 4 ? 3000 : 0))
        switch geometry {
        case .point(let point): try coordinate(point, dimension: dimension)
        case .lineString(let points): try line(points, dimension: dimension)
        case .polygon(let rings):
            try integer(rings.count)
            for ring in rings { try line(ring, dimension: dimension) }
        case .multiPoint(let children), .multiLineString(let children), .multiPolygon(let children), .collection(let children):
            try integer(children.count)
            for child in children {
                switch (kind, child) {
                case (4, .point), (5, .lineString), (6, .polygon), (7, _): break
                default: throw CanonicalWKBError.invalid
                }
                try write(child, depth: depth + 1)
            }
        }
    }
}

struct CanonicalWKBReader {
    private let bytes: Data
    private var offset = 0

    init(_ bytes: Data) { self.bytes = bytes }

    mutating func read() throws -> CanonicalWKBGeometry {
        let value = try geometry(depth: 0)
        guard offset == bytes.count else { throw CanonicalWKBError.invalid }
        return value
    }

    private mutating func geometry(depth: Int) throws -> CanonicalWKBGeometry {
        guard depth <= 16 else { throw CanonicalWKBError.oversized }
        guard offset < bytes.count else { throw CanonicalWKBError.truncated }
        let byteOrder = bytes[offset]; offset += 1
        guard byteOrder == 0 || byteOrder == 1 else { throw CanonicalWKBError.invalid }
        let little = byteOrder == 1
        let type = try uint32(little: little)
        // The server writes OGC/ISO WKB; offsets 1000/2000/3000 encode Z/M/ZM.
        let dimensionCode = type / 1000
        guard dimensionCode <= 3 else { throw CanonicalWKBError.invalid }
        let dimension = dimensionCode == 0 ? 2 : (dimensionCode == 3 ? 4 : 3)
        switch type % 1000 {
        case 1: return .point(try coordinate(dimension: dimension, little: little))
        case 2: return .lineString(try coordinates(dimension: dimension, little: little))
        case 3:
            let count = try length(little: little, minimumBytes: 4)
            var rings: [[[Double]]] = []; rings.reserveCapacity(count)
            for _ in 0..<count { rings.append(try coordinates(dimension: dimension, little: little)) }
            return .polygon(rings)
        case 4, 5, 6, 7:
            let kind = type % 1000
            let count = try length(little: little, minimumBytes: 5)
            var children: [CanonicalWKBGeometry] = []; children.reserveCapacity(count)
            for _ in 0..<count {
                let child = try geometry(depth: depth + 1)
                switch (kind, child) {
                case (4, .point), (5, .lineString), (6, .polygon), (7, _): children.append(child)
                default: throw CanonicalWKBError.invalid
                }
            }
            switch kind {
            case 4: return .multiPoint(children)
            case 5: return .multiLineString(children)
            case 6: return .multiPolygon(children)
            default: return .collection(children)
            }
        default: throw CanonicalWKBError.invalid
        }
    }

    private mutating func uint32(little: Bool) throws -> UInt32 {
        guard offset <= bytes.count, bytes.count - offset >= 4 else { throw CanonicalWKBError.truncated }
        var result: UInt32 = 0
        for index in 0..<4 {
            let shift = (little ? index : 3 - index) * 8
            result |= UInt32(bytes[offset + index]) << shift
        }
        offset += 4
        return result
    }

    private mutating func length(little: Bool, minimumBytes: Int) throws -> Int {
        let count = Int(try uint32(little: little))
        guard count <= (bytes.count - offset) / minimumBytes else { throw CanonicalWKBError.oversized }
        return count
    }

    private mutating func coordinate(dimension: Int, little: Bool) throws -> [Double] {
        guard bytes.count - offset >= dimension * 8 else { throw CanonicalWKBError.truncated }
        var values: [Double] = []; values.reserveCapacity(dimension)
        for _ in 0..<dimension {
            var bits: UInt64 = 0
            for index in 0..<8 {
                let shift = (little ? index : 7 - index) * 8
                bits |= UInt64(bytes[offset + index]) << shift
            }
            offset += 8
            let value = Double(bitPattern: bits)
            guard value.isFinite else { throw CanonicalWKBError.invalid }
            values.append(value)
        }
        return values
    }

    private mutating func coordinates(dimension: Int, little: Bool) throws -> [[Double]] {
        let count = try length(little: little, minimumBytes: dimension * 8)
        var values: [[Double]] = []; values.reserveCapacity(count)
        for _ in 0..<count { values.append(try coordinate(dimension: dimension, little: little)) }
        return values
    }
}
