import Foundation
import Supabase
import UIKit

actor SupabaseLandingPageService {
    static let shared = SupabaseLandingPageService()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private let bucketName = "landing-pages"
    
    private init() {}
    
    // MARK: - Fetch Landing Page
    
    func fetchLandingPage(campaignId: UUID) async throws -> CampaignLandingPage? {
        let response: [CampaignLandingPage] = try await client
            .from("campaign_landing_pages")
            .select()
            .eq("campaign_id", value: campaignId.uuidString)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    func fetchLandingPageBySlug(slug: String) async throws -> CampaignLandingPage? {
        let response: [CampaignLandingPage] = try await client
            .from("campaign_landing_pages")
            .select()
            .eq("slug", value: slug)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }
    
    /// Decode metadata JSONB from database into LandingPageMetadata
    func decodeMetadata(from jsonData: Data?) -> LandingPageMetadata? {
        guard let jsonData = jsonData else { return nil }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(LandingPageMetadata.self, from: jsonData)
        } catch {
            print("⚠️ [SupabaseLandingPageService] Failed to decode metadata: \(error)")
            return nil
        }
    }
    
    // MARK: - Create Landing Page
    
    func createLandingPage(
        campaignId: UUID,
        slug: String,
        title: String?,
        headline: String?,
        subheadline: String?,
        heroType: HeroType,
        heroUrl: String?,
        ctaType: String?,
        ctaUrl: String?,
        metadata: [String: AnyCodable]? = nil
    ) async throws -> CampaignLandingPage {
        var insertData: [String: AnyCodable] = [
            "campaign_id": AnyCodable(campaignId.uuidString),
            "slug": AnyCodable(slug),
            "hero_type": AnyCodable(heroType.rawValue)
        ]
        
        if let title = title, !title.isEmpty {
            insertData["title"] = AnyCodable(title)
        }
        if let headline = headline, !headline.isEmpty {
            insertData["headline"] = AnyCodable(headline)
        }
        if let subheadline = subheadline, !subheadline.isEmpty {
            insertData["subheadline"] = AnyCodable(subheadline)
        }
        if let heroUrl = heroUrl, !heroUrl.isEmpty {
            insertData["hero_url"] = AnyCodable(heroUrl)
        }
        if let ctaType = ctaType, !ctaType.isEmpty {
            insertData["cta_type"] = AnyCodable(ctaType)
        }
        if let ctaUrl = ctaUrl, !ctaUrl.isEmpty {
            insertData["cta_url"] = AnyCodable(ctaUrl)
        }
        if let metadata = metadata {
            // For JSONB columns, convert AnyCodable dictionary to plain dictionary
            // Supabase will handle the JSONB encoding
            let plainDict = metadata.mapValues { $0.value }
            insertData["metadata"] = AnyCodable(plainDict)
        }
        
        let response: [CampaignLandingPage] = try await client
            .from("campaign_landing_pages")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value
        
        guard let landingPage = response.first else {
            throw NSError(domain: "SupabaseLandingPageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create landing page"])
        }
        
        return landingPage
    }
    
    // MARK: - Update Landing Page
    
    func updateLandingPage(
        id: UUID,
        title: String?,
        headline: String?,
        subheadline: String?,
        heroType: HeroType?,
        heroUrl: String?,
        ctaType: String?,
        ctaUrl: String?
    ) async throws -> CampaignLandingPage {
        var updateData: [String: AnyCodable] = [:]
        
        if let title = title {
            updateData["title"] = AnyCodable(title.isEmpty ? nil : title)
        }
        if let headline = headline {
            updateData["headline"] = AnyCodable(headline.isEmpty ? nil : headline)
        }
        if let subheadline = subheadline {
            updateData["subheadline"] = AnyCodable(subheadline.isEmpty ? nil : subheadline)
        }
        if let heroType = heroType {
            updateData["hero_type"] = AnyCodable(heroType.rawValue)
        }
        if let heroUrl = heroUrl {
            updateData["hero_url"] = AnyCodable(heroUrl.isEmpty ? nil : heroUrl)
        }
        if let ctaType = ctaType {
            updateData["cta_type"] = AnyCodable(ctaType.isEmpty ? nil : ctaType)
        }
        if let ctaUrl = ctaUrl {
            updateData["cta_url"] = AnyCodable(ctaUrl.isEmpty ? nil : ctaUrl)
        }
        
        let response: [CampaignLandingPage] = try await client
            .from("campaign_landing_pages")
            .update(updateData)
            .eq("id", value: id.uuidString)
            .select()
            .single()
            .execute()
            .value
        
        guard let landingPage = response.first else {
            throw NSError(domain: "SupabaseLandingPageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update landing page"])
        }
        
        return landingPage
    }
    
    // MARK: - Upload Hero Image
    
    func uploadHeroImage(_ image: UIImage, campaignId: UUID) async throws -> String {
        // Convert UIImage to JPEG data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "SupabaseLandingPageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG"])
        }
        
        // Generate unique filename
        let filename = "\(UUID().uuidString).jpg"
        let path = "heroes/\(campaignId.uuidString)/\(filename)"
        
        // Upload to Supabase Storage
        do {
            _ = try await client.storage
                .from(bucketName)
                .upload(path: path, file: imageData, options: FileOptions(upsert: true))
            
            // Get public URL
            let publicURL = try client.storage
                .from(bucketName)
                .getPublicURL(path: path)
            
            return publicURL.absoluteString
        } catch {
            throw NSError(domain: "SupabaseLandingPageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload hero image: \(error.localizedDescription)"])
        }
    }
    
    // MARK: - Upload Hero Video
    
    func uploadHeroVideo(_ videoData: Data, campaignId: UUID, fileExtension: String = "mp4") async throws -> String {
        // Generate unique filename
        let filename = "\(UUID().uuidString).\(fileExtension)"
        let path = "heroes/\(campaignId.uuidString)/\(filename)"
        
        // Upload to Supabase Storage
        do {
            _ = try await client.storage
                .from(bucketName)
                .upload(path: path, file: videoData, options: FileOptions(upsert: true))
            
            // Get public URL
            let publicURL = try client.storage
                .from(bucketName)
                .getPublicURL(path: path)
            
            return publicURL.absoluteString
        } catch {
            throw NSError(domain: "SupabaseLandingPageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload hero video: \(error.localizedDescription)"])
        }
    }
    
    // MARK: - Delete Landing Page
    
    func deleteLandingPage(id: UUID) async throws {
        try await client
            .from("campaign_landing_pages")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}


