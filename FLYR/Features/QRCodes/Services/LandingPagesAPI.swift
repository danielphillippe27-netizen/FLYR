import Foundation
import Supabase

/// API layer for landing page operations
actor LandingPagesAPI {
    static let shared = LandingPagesAPI()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    // MARK: - Fetch Landing Pages
    
    /// Fetch all landing pages for the current user
    func fetchLandingPages() async throws -> [LandingPage] {
        let session = try await client.auth.session
        let userId = session.user.id
        
        let response: PostgrestResponse<[LandingPage]> = try await client
            .from("landing_pages")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        return response.value
    }
    
    /// Fetch a single landing page by ID
    func fetchLandingPage(id: UUID) async throws -> LandingPage {
        let response: PostgrestResponse<LandingPage> = try await client
            .from("landing_pages")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
        
        return response.value
    }
    
    // MARK: - Create Landing Page
    
    /// Create a new landing page
    /// - Parameters:
    ///   - name: Display name for the landing page
    ///   - url: Full URL for the landing page
    ///   - type: Optional type (e.g., "home_value", "listings", "appointment")
    /// - Returns: The created landing page
    func createLandingPage(name: String, url: String, type: String? = nil) async throws -> LandingPage {
        let session = try await client.auth.session
        let userId = session.user.id
        
        let landingPageData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "name": AnyCodable(name),
            "url": AnyCodable(url),
            "type": type != nil ? AnyCodable(type!) : AnyCodable(NSNull())
        ]
        
        let response: PostgrestResponse<LandingPage> = try await client
            .from("landing_pages")
            .insert(landingPageData)
            .select()
            .single()
            .execute()
        
        return response.value
    }
    
    // MARK: - Update Landing Page
    
    /// Update an existing landing page
    /// - Parameters:
    ///   - id: Landing page ID
    ///   - name: Updated name (optional)
    ///   - url: Updated URL (optional)
    ///   - type: Updated type (optional)
    /// - Returns: The updated landing page
    func updateLandingPage(id: UUID, name: String? = nil, url: String? = nil, type: String? = nil) async throws -> LandingPage {
        var updateData: [String: AnyCodable] = [:]
        
        if let name = name {
            updateData["name"] = AnyCodable(name)
        }
        if let url = url {
            updateData["url"] = AnyCodable(url)
        }
        if let type = type {
            updateData["type"] = AnyCodable(type)
        } else if type == nil {
            // Allow clearing type
            updateData["type"] = AnyCodable(NSNull())
        }
        
        let response: PostgrestResponse<LandingPage> = try await client
            .from("landing_pages")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
        
        return response.value
    }
    
    // MARK: - Delete Landing Page
    
    /// Delete a landing page
    /// - Parameter id: Landing page ID
    func deleteLandingPage(id: UUID) async throws {
        _ = try await client
            .from("landing_pages")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    // MARK: - Enhanced Methods
    
    /// Fetch landing page for a specific campaign and address
    /// - Parameters:
    ///   - campaignId: Campaign ID
    ///   - addressId: Address ID
    /// - Returns: Landing page if found, nil otherwise
    func fetchLandingPageForAddress(campaignId: UUID, addressId: UUID) async throws -> LandingPage? {
        let response: PostgrestResponse<[LandingPage]> = try await client
            .from("landing_pages")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .eq("address_id", value: addressId.uuidString)
            .limit(1)
            .execute()
        
        return response.value.first
    }
    
    /// Create landing page with full data payload
    /// - Parameter data: Landing page create payload
    /// - Returns: Created landing page
    func createLandingPage(data: LandingPageCreatePayload) async throws -> LandingPage {
        let session = try await client.auth.session
        let userId = session.user.id
        
        var landingPageData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "name": AnyCodable(data.name),
            "url": AnyCodable(data.url),
            "title": AnyCodable(data.title),
            "subtitle": AnyCodable(data.subtitle),
            "cta_text": AnyCodable(data.ctaText),
            "cta_url": AnyCodable(data.ctaURL)
        ]
        
        if let campaignId = data.campaignId {
            landingPageData["campaign_id"] = AnyCodable(campaignId.uuidString)
        }
        if let addressId = data.addressId {
            landingPageData["address_id"] = AnyCodable(addressId.uuidString)
        }
        if let templateId = data.templateId {
            landingPageData["template_id"] = AnyCodable(templateId.uuidString)
        }
        if let description = data.description {
            landingPageData["description"] = AnyCodable(description)
        } else {
            landingPageData["description"] = AnyCodable(NSNull())
        }
        if let imageURL = data.imageURL {
            landingPageData["image_url"] = AnyCodable(imageURL)
        } else {
            landingPageData["image_url"] = AnyCodable(NSNull())
        }
        if let videoURL = data.videoURL {
            landingPageData["video_url"] = AnyCodable(videoURL)
        } else {
            landingPageData["video_url"] = AnyCodable(NSNull())
        }
        if let dynamicData = data.dynamicData {
            landingPageData["dynamic_data"] = AnyCodable(dynamicData)
        }
        if let slug = data.slug {
            landingPageData["slug"] = AnyCodable(slug)
        } else {
            landingPageData["slug"] = AnyCodable(NSNull())
        }
        if let type = data.type {
            landingPageData["type"] = AnyCodable(type)
        } else {
            landingPageData["type"] = AnyCodable(NSNull())
        }
        
        let response: PostgrestResponse<LandingPage> = try await client
            .from("landing_pages")
            .insert(landingPageData)
            .select()
            .single()
            .execute()
        
        return response.value
    }
    
    /// Update landing page with full data payload
    /// - Parameters:
    ///   - id: Landing page ID
    ///   - data: Landing page update payload
    /// - Returns: Updated landing page
    func updateLandingPage(id: UUID, data: LandingPageUpdatePayload) async throws -> LandingPage {
        var updateData: [String: AnyCodable] = [:]
        
        if let name = data.name {
            updateData["name"] = AnyCodable(name)
        }
        if let url = data.url {
            updateData["url"] = AnyCodable(url)
        }
        if let title = data.title {
            updateData["title"] = AnyCodable(title)
        }
        if let subtitle = data.subtitle {
            updateData["subtitle"] = AnyCodable(subtitle)
        }
        if let description = data.description {
            updateData["description"] = AnyCodable(description)
        }
        if let ctaText = data.ctaText {
            updateData["cta_text"] = AnyCodable(ctaText)
        }
        if let ctaURL = data.ctaURL {
            updateData["cta_url"] = AnyCodable(ctaURL)
        }
        if let imageURL = data.imageURL {
            updateData["image_url"] = AnyCodable(imageURL)
        }
        if let videoURL = data.videoURL {
            updateData["video_url"] = AnyCodable(videoURL)
        }
        if let templateId = data.templateId {
            updateData["template_id"] = AnyCodable(templateId.uuidString)
        }
        if let dynamicData = data.dynamicData {
            updateData["dynamic_data"] = AnyCodable(dynamicData)
        }
        if let slug = data.slug {
            updateData["slug"] = AnyCodable(slug)
        }
        if let type = data.type {
            updateData["type"] = AnyCodable(type)
        }
        
        let response: PostgrestResponse<LandingPage> = try await client
            .from("landing_pages")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
        
        return response.value
    }
    
    /// Fetch all available templates
    /// - Returns: Array of landing page templates
    func fetchTemplates() async throws -> [LandingPageTemplateDB] {
        let response: PostgrestResponse<[LandingPageTemplateDB]> = try await client
            .from("landing_page_templates")
            .select()
            .order("name", ascending: true)
            .execute()
        
        return response.value
    }
    
    /// Fetch landing pages for a campaign
    /// - Parameter campaignId: Campaign ID
    /// - Returns: Array of landing pages
    func fetchLandingPagesForCampaign(campaignId: UUID) async throws -> [LandingPage] {
        let response: PostgrestResponse<[LandingPage]> = try await client
            .from("landing_pages")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .order("created_at", ascending: false)
            .execute()
        
        return response.value
    }
}

// MARK: - Payload Models

/// Payload for creating a landing page
public struct LandingPageCreatePayload {
    let name: String
    let url: String
    let campaignId: UUID?
    let addressId: UUID?
    let templateId: UUID?
    let title: String
    let subtitle: String
    let description: String?
    let ctaText: String
    let ctaURL: String
    let imageURL: String?
    let videoURL: String?
    let dynamicData: [String: AnyCodable]?
    let slug: String?
    let type: String?
    
    public init(
        name: String,
        url: String,
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
        dynamicData: [String: AnyCodable]? = nil,
        slug: String? = nil,
        type: String? = nil
    ) {
        self.name = name
        self.url = url
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
        self.type = type
    }
}

/// Payload for updating a landing page
public struct LandingPageUpdatePayload {
    let name: String?
    let url: String?
    let title: String?
    let subtitle: String?
    let description: String?
    let ctaText: String?
    let ctaURL: String?
    let imageURL: String?
    let videoURL: String?
    let templateId: UUID?
    let dynamicData: [String: AnyCodable]?
    let slug: String?
    let type: String?
    
    public init(
        name: String? = nil,
        url: String? = nil,
        title: String? = nil,
        subtitle: String? = nil,
        description: String? = nil,
        ctaText: String? = nil,
        ctaURL: String? = nil,
        imageURL: String? = nil,
        videoURL: String? = nil,
        templateId: UUID? = nil,
        dynamicData: [String: AnyCodable]? = nil,
        slug: String? = nil,
        type: String? = nil
    ) {
        self.name = name
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.ctaText = ctaText
        self.ctaURL = ctaURL
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.templateId = templateId
        self.dynamicData = dynamicData
        self.slug = slug
        self.type = type
    }
}

