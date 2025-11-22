import Foundation

/// Landing page template enum matching template names in database
public enum LandingPageTemplate: String, Codable, CaseIterable, Identifiable {
    case minimalBlack = "minimal_black"
    case luxeCard = "luxe_card"
    case spotlight = "spotlight"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .minimalBlack:
            return "Minimal Black"
        case .luxeCard:
            return "Real Estate Luxe Card"
        case .spotlight:
            return "Neighborhood Spotlight"
        }
    }
    
    public var description: String {
        switch self {
        case .minimalBlack:
            return "Apple-inspired minimal design with black background"
        case .luxeCard:
            return "Luxury real estate design with home value focus"
        case .spotlight:
            return "Community-focused design for local offers"
        }
    }
}

/// Database model for landing_page_templates table
public struct LandingPageTemplateDB: Identifiable, Codable {
    public let id: UUID
    public let name: String
    public let description: String?
    public let previewImageURL: String?
    public let components: [String: AnyCodable]
    public let createdAt: Date
    public let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case previewImageURL = "preview_image_url"
        case components
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(
        id: UUID,
        name: String,
        description: String? = nil,
        previewImageURL: String? = nil,
        components: [String: AnyCodable] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.previewImageURL = previewImageURL
        self.components = components
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

