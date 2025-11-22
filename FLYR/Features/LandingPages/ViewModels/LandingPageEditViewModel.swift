import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
class LandingPageEditViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var headline: String = ""
    @Published var subheadline: String = ""
    @Published var heroType: HeroType = .image
    @Published var heroImage: UIImage?
    @Published var heroVideo: URL?
    @Published var heroVideoUrl: String = ""
    @Published var youtubeUrlError: String?
    @Published var existingHeroUrl: String?
    @Published var ctaType: CTAType = .book
    @Published var ctaUrl: String = ""
    @Published var isSaving = false
    @Published var error: String?
    
    private let landingPageService = SupabaseLandingPageService.shared
    
    var ctaTypes: [CTAType] {
        CTAType.allCases
    }
    
    var shouldShowCtaUrl: Bool {
        ctaType != .form
    }
    
    func ctaTypeDisplayName(for type: CTAType) -> String {
        switch type {
        case .book: return "Book a Call"
        case .call: return "Call"
        case .text: return "Text"
        case .learn: return "Learn More"
        case .offer: return "Get Offer"
        case .custom: return "Custom"
        case .form: return "Form"
        }
    }
    
    func isValidYouTubeURL(_ urlString: String) -> Bool {
        guard !urlString.isEmpty else { return false }
        
        // Patterns to match:
        // - https://www.youtube.com/watch?v=VIDEO_ID
        // - https://youtube.com/watch?v=VIDEO_ID
        // - https://youtu.be/VIDEO_ID
        // - https://www.youtube.com/embed/VIDEO_ID
        // - http:// variants
        
        let patterns = [
            #"^https?://(www\.)?youtube\.com/watch\?v=[\w-]+"#,
            #"^https?://youtu\.be/[\w-]+"#,
            #"^https?://(www\.)?youtube\.com/embed/[\w-]+"#
        ]
        
        for pattern in patterns {
            if urlString.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    private var landingPageId: UUID?
    private var campaignId: UUID?
    
    func loadLandingPage(_ landingPage: CampaignLandingPage) {
        self.landingPageId = landingPage.id
        self.campaignId = landingPage.campaignId
        self.title = landingPage.title ?? ""
        self.headline = landingPage.headline ?? ""
        self.subheadline = landingPage.subheadline ?? ""
        self.heroType = landingPage.heroType
        self.ctaType = landingPage.ctaType ?? .book
        self.ctaUrl = landingPage.ctaUrl ?? ""
        self.existingHeroUrl = landingPage.heroUrl
        
        // Set heroVideoUrl if hero type is YouTube
        if landingPage.heroType == .youtube, let heroUrl = landingPage.heroUrl {
            self.heroVideoUrl = heroUrl
        }
    }
    
    func updateLandingPage() async throws -> CampaignLandingPage {
        guard let landingPageId = landingPageId, let campaignId = campaignId else {
            throw NSError(domain: "LandingPageEditViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Landing page not loaded"])
        }
        
        isSaving = true
        error = nil
        youtubeUrlError = nil
        defer { isSaving = false }
        
        do {
            // Validate YouTube URL if hero type is YouTube
            if heroType == .youtube {
                if !isValidYouTubeURL(heroVideoUrl) {
                    youtubeUrlError = "Please enter a valid YouTube URL"
                    throw NSError(domain: "LandingPageEditViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid YouTube URL"])
                }
            }
            
            // Upload new hero media based on type
            var heroUrl: String? = existingHeroUrl
            switch heroType {
            case .image:
                if let heroImage = heroImage {
                    heroUrl = try await landingPageService.uploadHeroImage(heroImage, campaignId: campaignId)
                }
            case .video:
                if let heroVideo = heroVideo {
                    let videoData = try Data(contentsOf: heroVideo)
                    let fileExtension = heroVideo.pathExtension.isEmpty ? "mp4" : heroVideo.pathExtension
                    heroUrl = try await landingPageService.uploadHeroVideo(videoData, campaignId: campaignId, fileExtension: fileExtension)
                }
                // If no new video selected, keep existing URL (already set above)
            case .youtube:
                heroUrl = heroVideoUrl.isEmpty ? nil : heroVideoUrl
            }
            
            // Update landing page
            let updated = try await landingPageService.updateLandingPage(
                id: landingPageId,
                title: title.isEmpty ? nil : title,
                headline: headline.isEmpty ? nil : headline,
                subheadline: subheadline.isEmpty ? nil : subheadline,
                heroType: heroType,
                heroUrl: heroUrl,
                ctaType: ctaType.rawValue,
                ctaUrl: ctaUrl.isEmpty ? nil : ctaUrl
            )
            
            // Update existing hero URL if changed
            if let newHeroUrl = heroUrl {
                existingHeroUrl = newHeroUrl
            }
            
            return updated
        } catch {
            if youtubeUrlError == nil {
                self.error = "Failed to update landing page: \(error.localizedDescription)"
            }
            print("❌ [LandingPageEditViewModel] Error updating landing page: \(error)")
            throw error
        }
    }
}


