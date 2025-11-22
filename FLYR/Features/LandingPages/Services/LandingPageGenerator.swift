import Foundation
import Supabase

/// Service for generating landing pages automatically
actor LandingPageGenerator {
    static let shared = LandingPageGenerator()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    /// Generate a landing page for a campaign and address
    /// Checks if page exists, returns existing if found
    /// - Parameters:
    ///   - campaign: Campaign model
    ///   - address: Campaign address row
    ///   - templateId: Optional template ID (uses default from branding if nil)
    /// - Returns: Generated or existing landing page
    func generateLandingPage(
        campaign: CampaignDBRow,
        address: CampaignAddressRow,
        templateId: UUID? = nil
    ) async throws -> LandingPage {
        // Check if landing page already exists
        if let existing = try await findExistingLandingPage(campaignId: campaign.id, addressId: address.id) {
            print("✅ [LandingPageGenerator] Found existing landing page for address \(address.id)")
            return existing
        }
        
        // Get user ID
        let session = try await client.auth.session
        let userId = session.user.id
        
        // Get default template if not provided
        let finalTemplateId: UUID?
        if let providedTemplateId = templateId {
            finalTemplateId = providedTemplateId
        } else {
            finalTemplateId = try await getDefaultTemplateId(userId: userId)
        }
        
        // Generate content
        let title = generateTitle(address: address)
        let subtitle = generateSubtitle(address: address)
        let description = generateDescription(address: address)
        let ctaText = "See Your Report"
        let ctaURL = "https://flyr.ai/report/\(address.id.uuidString)"
        
        // Generate slug
        let slug = LandingPageSlugGenerator.generateSlug(
            campaignTitle: campaign.title,
            addressFormatted: address.formatted
        )
        
        // Build dynamic data
        let dynamicData: [String: AnyCodable] = [
            "comps": AnyCodable([]),
            "avm": AnyCodable([:]),
            "stats": AnyCodable([:])
        ]
        
        // Create landing page data
        let landingPageData: [String: AnyCodable] = [
            "user_id": AnyCodable(userId.uuidString),
            "campaign_id": AnyCodable(campaign.id.uuidString),
            "address_id": AnyCodable(address.id.uuidString),
            "template_id": finalTemplateId != nil ? AnyCodable(finalTemplateId!.uuidString) : AnyCodable(NSNull()),
            "name": AnyCodable("\(address.formatted) - \(campaign.title)"),
            "url": AnyCodable("https://flyr.ai\(slug)"),
            "title": AnyCodable(title),
            "subtitle": AnyCodable(subtitle),
            "description": description != nil ? AnyCodable(description!) : AnyCodable(NSNull()),
            "cta_text": AnyCodable(ctaText),
            "cta_url": AnyCodable(ctaURL),
            "image_url": AnyCodable(NSNull()),
            "video_url": AnyCodable(NSNull()),
            "dynamic_data": AnyCodable(dynamicData),
            "slug": AnyCodable(slug),
            "type": AnyCodable("home_value")
        ]
        
        print("🔷 [LandingPageGenerator] Creating landing page for address \(address.id)")
        
        // Insert into database
        let response: PostgrestResponse<LandingPage> = try await client
            .from("landing_pages")
            .insert(landingPageData)
            .select()
            .single()
            .execute()
        
        print("✅ [LandingPageGenerator] Landing page created with ID: \(response.value.id)")
        return response.value
    }
    
    /// Find existing landing page for campaign and address
    private func findExistingLandingPage(campaignId: UUID, addressId: UUID) async throws -> LandingPage? {
        let response: PostgrestResponse<[LandingPage]> = try await client
            .from("landing_pages")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .eq("address_id", value: addressId.uuidString)
            .limit(1)
            .execute()
        
        return response.value.first
    }
    
    /// Get default template ID from user settings
    private func getDefaultTemplateId(userId: UUID) async throws -> UUID? {
        let response: PostgrestResponse<[UserSettings]> = try await client
            .from("user_settings")
            .select("default_template_id")
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        
        return response.value.first?.defaultTemplateId
    }
    
    /// Generate title from address
    private func generateTitle(address: CampaignAddressRow) -> String {
        // Extract street number and name
        let components = address.formatted.components(separatedBy: ",")
        if let streetPart = components.first {
            return "\(streetPart) • Your Home Value"
        }
        return "\(address.formatted) • Your Home Value"
    }
    
    /// Generate subtitle from address
    private func generateSubtitle(address: CampaignAddressRow) -> String {
        // Extract postal code from formatted address if available
        let components = address.formatted.components(separatedBy: ",")
        if components.count > 1 {
            let lastComponent = components.last?.trimmingCharacters(in: .whitespaces) ?? ""
            // Check if it looks like a postal code (Canadian format: A1A 1A1 or US: 12345)
            if lastComponent.count >= 5 {
                return "Discover your property value in \(lastComponent)"
            }
        }
        return "Get your free home value report"
    }
    
    /// Generate description from address
    private func generateDescription(address: CampaignAddressRow) -> String? {
        return "Find out what your home is worth with our free property valuation report. Get instant insights into your property value, comparable sales, and market trends."
    }
}


