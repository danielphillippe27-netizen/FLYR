import Foundation

/// Canonical comparison keys, not mailing labels. Callers must scope comparisons
/// to a campaign/nearby geography; a street address alone is not globally unique.
enum AddressMatcher {
    private static let suffixes = [
        "st": "street", "str": "street", "rd": "road", "ave": "avenue", "av": "avenue",
        "blvd": "boulevard", "dr": "drive", "ct": "court", "crt": "court",
        "cres": "crescent", "ln": "lane", "pl": "place", "trl": "trail",
        "pkwy": "parkway", "hwy": "highway", "cir": "circle", "ter": "terrace",
        "terr": "terrace", "wy": "way"
    ]
    private static let directions = [
        "n": "north", "s": "south", "e": "east", "w": "west",
        "ne": "northeast", "nw": "northwest", "se": "southeast", "sw": "southwest",
        "north": "north", "south": "south", "east": "east", "west": "west",
        "northeast": "northeast", "northwest": "northwest", "southeast": "southeast", "southwest": "southwest"
    ]
    private static let unitPattern = #"(?:\b(?:unit|apt|apartment|suite|ste)\s*|#\s*)([a-z0-9-]+)\b"#

    private static func clean(_ value: String?) -> String {
        (value ?? "").lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: #"[^\p{L}\p{N}#/-]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capture(_ value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    static func streetKey(_ value: String?) -> String? {
        var words = clean(value).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty, words.contains(where: { $0.contains(where: \.isLetter) }) else { return nil }
        // Treat spaced compass pairs as a single edge direction.
        let pairs = ["north east": "northeast", "north west": "northwest",
                     "south east": "southeast", "south west": "southwest"]
        if words.count >= 4, let pair = pairs[words.prefix(2).joined(separator: " ")] {
            words.replaceSubrange(0..<2, with: [pair])
        }
        if words.count >= 4, let pair = pairs[words.suffix(2).joined(separator: " ")] {
            words.replaceSubrange((words.count - 2)..<words.count, with: [pair])
        }
        // Only a terminal direction (or a prefix before a named street with a
        // suffix) is movable. East Street and North Road are street names.
        let suffixNames = Set(suffixes.values)
        if words.count >= 3, let direction = directions[words.last!],
           suffixNames.contains(suffixes[words[words.count - 2]] ?? words[words.count - 2]) {
            words[words.count - 1] = direction
            words[words.count - 2] = suffixes[words[words.count - 2]] ?? words[words.count - 2]
        } else if words.count >= 3, let direction = directions[words[0]],
                  suffixNames.contains(suffixes[words.last!] ?? words.last!) {
            words.removeFirst()
            words[words.count - 1] = suffixes[words.last!] ?? words.last!
            words.append(direction)
        } else if words.count >= 3, let direction = directions[words[words.count - 2]],
                  suffixNames.contains(suffixes[words.last!] ?? words.last!) {
            words.remove(at: words.count - 2)
            words[words.count - 1] = suffixes[words.last!] ?? words.last!
            words.append(direction)
        } else {
            words[words.count - 1] = suffixes[words.last!] ?? words.last!
        }
        return words.joined(separator: " ")
    }

    static func identity(houseNumber: String?, streetName: String?, formatted: String? = nil,
                         unit: String? = nil) -> String? {
        let line = (formatted ?? "").components(separatedBy: ",").first ?? ""
        let parsedUnit = capture(formatted ?? "", pattern: unitPattern)
            ?? capture(streetName ?? "", pattern: unitPattern)
        let withoutUnit = line.replacingOccurrences(of: unitPattern, with: " ", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let housePattern = #"^([0-9]+[a-z0-9/-]*)(?:\s|$)"#
        func validHouse(_ value: String?) -> String? {
            let raw = clean(value)
            guard raw.range(of: #"^\d+(?:st|nd|rd|th)$"#, options: .regularExpression) == nil,
                  raw.range(of: #"^\d+[a-z0-9/-]*$"#, options: .regularExpression) != nil else { return nil }
            return raw
        }
        guard let house = validHouse(houseNumber) ?? validHouse(capture(withoutUnit, pattern: housePattern)) else { return nil }
        let parsedStreet = withoutUnit.replacingOccurrences(of: housePattern, with: "", options: [.regularExpression, .caseInsensitive])
        let explicitStreet = streetName?.replacingOccurrences(of: unitPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        guard let street = streetKey(explicitStreet) ?? streetKey(parsedStreet) else { return nil }
        let explicitUnit = clean(unit.flatMap { capture($0, pattern: unitPattern) ?? $0 })
        let unitKey = explicitUnit.isEmpty ? clean(parsedUnit) : explicitUnit
        return "\(house)|\(street)" + (unitKey.isEmpty ? "" : "|unit:\(unitKey)")
    }
}
