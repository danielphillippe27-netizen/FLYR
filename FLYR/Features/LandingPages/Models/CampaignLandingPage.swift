import Foundation

/// Hero media type for landing pages
public enum HeroType: String, Codable {
    case image
    case video
    case youtube
}

/// CTA button type for landing pages
public enum CTAType: String, Codable, CaseIterable {
    case book
    case call
    case text
    case learn
    case offer
    case custom
    case form
}

/// Campaign landing page model matching the campaign_landing_pages table schema
public struct CampaignLandingPage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let campaignId: UUID
    public let slug: String
    public let title: String?
    public let headline: String?
    public let subheadline: String?
    public let heroType: HeroType
    public let heroUrl: String?
    public let ctaType: CTAType?
    public let ctaUrl: String?
    public let createdAt: Date
    public let updatedAt: Date
    
    public init(
        id: UUID = UUID(),
        campaignId: UUID,
        slug: String,
        title: String? = nil,
        headline: String? = nil,
        subheadline: String? = nil,
        heroType: HeroType = .image,
        heroUrl: String? = nil,
        ctaType: CTAType? = nil,
        ctaUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.campaignId = campaignId
        self.slug = slug
        self.title = title
        self.headline = headline
        self.subheadline = subheadline
        self.heroType = heroType
        self.heroUrl = heroUrl
        self.ctaType = ctaType
        self.ctaUrl = ctaUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case slug
        case title
        case headline
        case subheadline
        case heroType = "hero_type"
        case heroUrl = "hero_url"
        case ctaType = "cta_type"
        case ctaUrl = "cta_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // Custom decoder to handle backward compatibility (default heroType to .image if missing)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        campaignId = try container.decode(UUID.self, forKey: .campaignId)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        subheadline = try container.decodeIfPresent(String.self, forKey: .subheadline)
        heroType = try container.decodeIfPresent(HeroType.self, forKey: .heroType) ?? .image
        heroUrl = try container.decodeIfPresent(String.self, forKey: .heroUrl)
        
        // Handle CTA type: try to decode as enum, fallback to string parsing
        if let ctaTypeString = try container.decodeIfPresent(String.self, forKey: .ctaType) {
            ctaType = CTAType(rawValue: ctaTypeString)
        } else {
            ctaType = nil
        }
        
        ctaUrl = try container.decodeIfPresent(String.self, forKey: .ctaUrl)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Slug Generation Helper

extension CampaignLandingPage {
    /// Generate a slug from campaign name with random short ID
    /// Format: campaign-name-kebab-randomid
    static func generateSlug(from campaignName: String) -> String {
        let kebab = campaignName
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        
        // Generate short random ID (6 characters)
        let randomId = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        
        return "\(kebab)-\(randomId)"
    }
}


