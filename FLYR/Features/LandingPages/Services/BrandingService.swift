import Foundation
import Supabase

/// Service for managing branding settings
actor BrandingService {
    static let shared = BrandingService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private var cachedBranding: [UUID: LandingPageBranding] = [:]
    
    private init() {}
    
    /// Fetch branding for a user
    /// - Parameter userId: User ID
    /// - Returns: Branding data
    func fetchBranding(userId: UUID) async throws -> LandingPageBranding? {
        // Check cache first
        if let cached = cachedBranding[userId] {
            return cached
        }
        
        // Fetch from database
        let response: PostgrestResponse<[UserSettingsBranding]> = try await client
            .from("user_settings")
            .select("brand_color,logo_url,realtor_profile_card,default_cta_color,font_style,default_template_id")
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        
        guard let settings = response.value.first else {
            return nil
        }
        
        // Parse realtor profile card
        var profileCard: RealtorProfileCard? = nil
        if let profileData = settings.realtorProfileCard {
            profileCard = try? JSONDecoder().decode(RealtorProfileCard.self, from: profileData)
        }
        
        let branding = LandingPageBranding(
            brandColor: settings.brandColor,
            logoURL: settings.logoURL,
            realtorProfileCard: profileCard,
            defaultCTAColor: settings.defaultCTAColor,
            fontStyle: settings.fontStyle,
            defaultTemplateId: settings.defaultTemplateId
        )
        
        // Cache it
        cachedBranding[userId] = branding
        
        return branding
    }
    
    /// Update branding for a user
    /// - Parameters:
    ///   - userId: User ID
    ///   - branding: Branding data
    func updateBranding(userId: UUID, branding: LandingPageBranding) async throws {
        var updateData: [String: AnyCodable] = [:]
        
        if let brandColor = branding.brandColor {
            updateData["brand_color"] = AnyCodable(brandColor)
        }
        if let logoURL = branding.logoURL {
            updateData["logo_url"] = AnyCodable(logoURL)
        }
        if let profileCard = branding.realtorProfileCard {
            if let jsonData = try? JSONEncoder().encode(profileCard) {
                updateData["realtor_profile_card"] = AnyCodable(jsonData)
            }
        }
        if let ctaColor = branding.defaultCTAColor {
            updateData["default_cta_color"] = AnyCodable(ctaColor)
        }
        if let fontStyle = branding.fontStyle {
            updateData["font_style"] = AnyCodable(fontStyle)
        }
        if let templateId = branding.defaultTemplateId {
            updateData["default_template_id"] = AnyCodable(templateId.uuidString)
        }
        
        _ = try await client
            .from("user_settings")
            .update(updateData)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Clear cache
        cachedBranding.removeValue(forKey: userId)
    }
    
    /// Clear cache for a user
    func clearCache(userId: UUID) {
        cachedBranding.removeValue(forKey: userId)
    }
}

/// User settings branding fields
private struct UserSettingsBranding: Codable {
    let brandColor: String?
    let logoURL: String?
    let realtorProfileCard: Data?
    let defaultCTAColor: String?
    let fontStyle: String?
    let defaultTemplateId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case brandColor = "brand_color"
        case logoURL = "logo_url"
        case realtorProfileCard = "realtor_profile_card"
        case defaultCTAColor = "default_cta_color"
        case fontStyle = "font_style"
        case defaultTemplateId = "default_template_id"
    }
}

