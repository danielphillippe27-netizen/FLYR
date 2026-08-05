import Foundation

/// App-level user model for UI and Keychain. Replaces Supabase Auth `User` in views.
struct AppUser: Equatable, Codable {
    let id: UUID
    let email: String
    let displayName: String?
    let photoURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case photoURL = "photo_url"
    }

    init(id: UUID, email: String, displayName: String? = nil, photoURL: URL? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = photoURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        email = try c.decode(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        photoURL = try c.decodeIfPresent(URL.self, forKey: .photoURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(email, forKey: .email)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(photoURL, forKey: .photoURL)
    }
}
