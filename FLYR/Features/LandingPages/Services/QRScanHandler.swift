import Foundation
import UIKit
import Supabase

/// Handler for QR code scan events and landing page interactions
actor QRScanHandler {
    static let shared = QRScanHandler()
    
    private let eventsAPI = LandingPageEventsAPI.shared
    private let landingPagesAPI = LandingPagesAPI.shared
    
    private init() {}
    
    /// Handle QR code scan - logs scan event and opens landing page
    /// - Parameters:
    ///   - landingPageId: Landing page ID
    ///   - device: Device identifier
    func handleQRScan(landingPageId: UUID, device: String? = nil) async throws {
        // Log scan event
        try await eventsAPI.trackEvent(
            landingPageId: landingPageId,
            eventType: "scan",
            device: device ?? UIDevice.current.model
        )
        
        print("📱 [QRScanHandler] Logged scan event for landing page \(landingPageId)")
    }
    
    /// Handle landing page view - logs view event
    /// - Parameters:
    ///   - landingPageId: Landing page ID
    ///   - device: Device identifier
    func handlePageView(landingPageId: UUID, device: String? = nil) async throws {
        // Log view event
        try await eventsAPI.trackEvent(
            landingPageId: landingPageId,
            eventType: "view",
            device: device ?? UIDevice.current.model
        )
        
        print("👁️ [QRScanHandler] Logged view event for landing page \(landingPageId)")
    }
    
    /// Handle CTA button click - logs click event
    /// - Parameters:
    ///   - landingPageId: Landing page ID
    ///   - ctaURL: CTA URL that was clicked
    ///   - device: Device identifier
    func handleCTAClick(landingPageId: UUID, ctaURL: String, device: String? = nil) async throws {
        // Log click event
        try await eventsAPI.trackEvent(
            landingPageId: landingPageId,
            eventType: "click",
            device: device ?? UIDevice.current.model
        )
        
        // Open the CTA URL
        if let url = URL(string: ctaURL) {
            await MainActor.run {
                UIApplication.shared.open(url)
            }
        }
        
        print("🖱️ [QRScanHandler] Logged click event for landing page \(landingPageId)")
    }
    
    /// Get landing page from slug and handle scan/view
    /// - Parameters:
    ///   - slug: Landing page slug (e.g., "/camp/main/5875")
    ///   - device: Device identifier
    /// - Returns: Landing page if found
    func getLandingPageFromSlug(_ slug: String, device: String? = nil) async throws -> LandingPage? {
        // Parse slug to extract campaign and address identifiers
        guard let (campaignSlug, addressSlug) = LandingPageSlugGenerator.parseSlug(slug) else {
            print("❌ [QRScanHandler] Invalid slug format: \(slug)")
            return nil
        }
        
        // For now, we'll need to fetch by slug directly
        // In production, you might want to store a mapping or use a different lookup
        let response: PostgrestResponse<[LandingPage]> = try await SupabaseManager.shared.client
            .from("landing_pages")
            .select()
            .eq("slug", value: slug)
            .limit(1)
            .execute()
        
        guard let landingPage = response.value.first else {
            print("⚠️ [QRScanHandler] No landing page found for slug: \(slug)")
            return nil
        }
        
        // Log scan and view events
        try await handleQRScan(landingPageId: landingPage.id, device: device)
        try await handlePageView(landingPageId: landingPage.id, device: device)
        
        return landingPage
    }
}

