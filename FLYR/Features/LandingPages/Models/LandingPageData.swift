import Foundation
import SwiftUI

/// Complete landing page data model for rendering templates
public struct LandingPageData: Identifiable, Codable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let campaignId: UUID?
    public let addressId: UUID?
    public let templateId: UUID?
    public let title: String
    public let subtitle: String
    public let description: String?
    public let ctaText: String
    public let ctaURL: String
    public let imageURL: String?
    public let videoURL: String?
    public let dynamicData: [String: AnyCodable]
    public let slug: String?
    public let createdAt: Date
    public let updatedAt: Date
    
    // Legacy fields for backward compatibility
    public let name: String?
    public let url: String?
    public let type: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case name
        case url
        case type
    }
    
    public init(
        id: UUID = UUID(),
        userId: UUID,
        campaignId: UUID? = nil,
        addressId: UUID? = nil,
        templateId: UUID? = nil,
        title: String,
        subtitle: String,
        description: String? = nil,
        ctaText: String,
        ctaURL: String,
        imageURL: String? = nil,
        videoURL: String? = nil,
        dynamicData: [String: AnyCodable] = [:],
        slug: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        name: String? = nil,
        url: String? = nil,
        type: String? = nil
    ) {
        self.id = id
        self.userId = userId
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.url = url
        self.type = type
    }
    
    /// Template enum from template name or ID
    public var template: LandingPageTemplate {
        // Try to infer from template name or use default
        if let name = name?.lowercased() {
            if name.contains("minimal") || name.contains("black") {
                return .minimalBlack
            } else if name.contains("luxe") || name.contains("card") {
                return .luxeCard
            } else if name.contains("spotlight") || name.contains("neighborhood") {
                return .spotlight
            }
        }
        return .minimalBlack // default
    }
}

/// Branding data for landing pages
public struct LandingPageBranding: Codable, Equatable {
    public let brandColor: String? // hex color
    public let logoURL: String?
    public let realtorProfileCard: RealtorProfileCard?
    public let defaultCTAColor: String? // hex color
    public let fontStyle: String?
    public let defaultTemplateId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case brandColor = "brand_color"
        case logoURL = "logo_url"
        case realtorProfileCard = "realtor_profile_card"
        case defaultCTAColor = "default_cta_color"
        case fontStyle = "font_style"
        case defaultTemplateId = "default_template_id"
    }
    
    public init(
        brandColor: String? = nil,
        logoURL: String? = nil,
        realtorProfileCard: RealtorProfileCard? = nil,
        defaultCTAColor: String? = nil,
        fontStyle: String? = nil,
        defaultTemplateId: UUID? = nil
    ) {
        self.brandColor = brandColor
        self.logoURL = logoURL
        self.realtorProfileCard = realtorProfileCard
        self.defaultCTAColor = defaultCTAColor
        self.fontStyle = fontStyle
        self.defaultTemplateId = defaultTemplateId
    }
    
    /// Convert hex string to SwiftUI Color
    public var brandColorValue: Color? {
        guard let hex = brandColor else { return nil }
        return Color(hex: hex)
    }
    
    /// Convert hex string to SwiftUI Color for CTA
    public var ctaColorValue: Color? {
        guard let hex = defaultCTAColor else { return brandColorValue }
        return Color(hex: hex)
    }
}

/// Realtor profile card data
public struct RealtorProfileCard: Codable, Equatable {
    public let name: String?
    public let photoURL: String?
    public let phone: String?
    public let email: String?
    public let company: String?
    public let license: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case photoURL = "photo_url"
        case phone
        case email
        case company
        case license
    }
    
    public init(
        name: String? = nil,
        photoURL: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        company: String? = nil,
        license: String? = nil
    ) {
        self.name = name
        self.photoURL = photoURL
        self.phone = phone
        self.email = email
        self.company = company
        self.license = license
    }
}

// Note: Color(hex:) extension is defined in Shared/UI/Colors.swift

