import Foundation

struct UserProfile: Identifiable, Codable, Equatable {
    let id: UUID
    let email: String
    let fullName: String?
    let avatarURL: String?
    let phoneNumber: String?
    let createdAt: Date
    let updatedAt: Date
    
    // New profile fields
    var firstName: String?
    var lastName: String?
    var quote: String?
    var profileImageURL: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarURL = "avatar_url"
        case phoneNumber = "phone_number"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case quote
        case profileImageURL = "profile_image_url"
    }
    
    // Computed property for display name (first + last, then fallback)
    var displayName: String {
        let first = firstName ?? ""
        let last = lastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? (email.components(separatedBy: "@").first?.capitalized ?? "User") : full
    }
}


