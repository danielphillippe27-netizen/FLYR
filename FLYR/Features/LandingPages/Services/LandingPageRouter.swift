import Foundation
import Supabase

/// Router for parsing and handling landing page URLs
public struct LandingPageRouter {
    /// Parse a URL and extract landing page data
    /// - Parameter url: URL to parse (e.g., https://flyr.ai/camp/main/5875)
    /// - Returns: Landing page data if found
    public static func parseURL(_ url: URL) async throws -> LandingPageData? {
        // Extract path from URL
        let path = url.path
        
        // Parse slug from path
        guard let (campaignSlug, addressSlug) = LandingPageSlugGenerator.parseSlug(path) else {
            print("❌ [LandingPageRouter] Invalid URL path: \(path)")
            return nil
        }
        
        // Fetch landing page by slug
        let response: PostgrestResponse<[LandingPage]> = try await SupabaseManager.shared.client
            .from("landing_pages")
            .select()
            .eq("slug", value: path)
            .limit(1)
            .execute()
        
        guard let landingPage = response.value.first else {
            print("⚠️ [LandingPageRouter] No landing page found for slug: \(path)")
            return nil
        }
        
        // Convert to LandingPageData
        return landingPage.toLandingPageData()
    }
    
    /// Handle landing page URL and return view
    /// - Parameter url: URL to handle
    /// - Returns: Landing page view if found
    public static func handleURL(_ url: URL) async throws -> LandingPageView? {
        guard let pageData = try await parseURL(url) else {
            return nil
        }
        
        // Fetch branding if user is authenticated
        var branding: LandingPageBranding? = nil
        if let userId = try? await SupabaseManager.shared.client.auth.session.user.id {
            branding = try? await BrandingService.shared.fetchBranding(userId: userId)
        }
        
        return LandingPageView(pageData: pageData, branding: branding)
    }
}

