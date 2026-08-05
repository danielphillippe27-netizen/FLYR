import Foundation

struct Campaign: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let description: String
    let coverImageURL: String?
    let totalFlyers: Int
    let scans: Int
    let conversions: Int
    let region: String?
    let userId: UUID?
    let accentColor: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, scans, conversions, region, userId
        case coverImageURL = "cover_image_url"
        case totalFlyers = "total_flyers"
        case accentColor = "accent_color"
        case createdAt = "created_at"
    }
}
