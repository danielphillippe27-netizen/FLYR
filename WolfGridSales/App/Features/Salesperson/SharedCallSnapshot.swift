import Foundation

struct SharedCallSnapshot: Codable, Identifiable {
    let id: String
    let name: String
    let phone: String?
    let phase: String
    let startedAt: String
    let connectedAt: String?
    var deviceId: String?
    var platform: String?
    var expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, phone, phase, startedAt, connectedAt, deviceId, platform, expiresAt
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(phone, forKey: .phone)
        try values.encode(phase, forKey: .phase)
        try values.encode(startedAt, forKey: .startedAt)
        try values.encode(connectedAt, forKey: .connectedAt)
        try values.encodeIfPresent(deviceId, forKey: .deviceId)
        try values.encodeIfPresent(platform, forKey: .platform)
        try values.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
