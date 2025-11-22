import Foundation

/// Landing page model matching the landing_pages table schema
/// Enhanced with new fields for template-based system
public struct LandingPage: Identifiable, Codable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let name: String
    public let url: String
    public let type: String?
    public let createdAt: Date
    public let updatedAt: Date
    
    // New fields for enhanced landing page system
    public let campaignId: UUID?
    public let addressId: UUID?
    public let templateId: UUID?
    public let title: String?
    public let subtitle: String?
    public let description: String?
    public let ctaText: String?
    public let ctaURL: String?
    public let imageURL: String?
    public let videoURL: String?
    public let dynamicData: [String: AnyCodable]?
    public let slug: String?
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        url: String,
        type: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        campaignId: UUID? = nil,
        addressId: UUID? = nil,
        templateId: UUID? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        ctaText: String? = nil,
        ctaURL: String? = nil,
        imageURL: String? = nil,
        videoURL: String? = nil,
        dynamicData: [String: AnyCodable]? = nil,
        slug: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.url = url
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.campaignId = campaignId
        self.addressId = addressId
        self.templateId = templateId
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.ctaText = ctaText
        self.ctaURL = ctaURL
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.dynamicData = dynamicData
        self.slug = slug
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case url
        case type
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case campaignId = "campaign_id"
        case addressId = "address_id"
        case templateId = "template_id"
        case title
        case subtitle
        case description
        case ctaText = "cta_text"
        case ctaURL = "cta_url"
        case imageURL = "image_url"
        case videoURL = "video_url"
        case dynamicData = "dynamic_data"
        case slug
    }
    
    /// Convert to LandingPageData for template rendering
    public func toLandingPageData() -> LandingPageData {
        return LandingPageData(
            id: id,
            userId: userId,
            campaignId: campaignId,
            addressId: addressId,
            templateId: templateId,
            title: title ?? name,
            subtitle: subtitle ?? "",
            description: description,
            ctaText: ctaText ?? "Learn More",
            ctaURL: ctaURL ?? url,
            imageURL: imageURL,
            videoURL: videoURL,
            dynamicData: dynamicData ?? [:],
            slug: slug,
            createdAt: createdAt,
            updatedAt: updatedAt,
            name: name,
            url: url,
            type: type
        )
    }
}

