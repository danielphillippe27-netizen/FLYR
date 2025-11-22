import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
class LandingPageCreateViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var headline: String = ""
    @Published var subheadline: String = ""
    @Published var heroType: HeroType = .image
    @Published var heroImage: UIImage?
    @Published var heroVideo: URL?
    @Published var heroVideoUrl: String = ""
    @Published var youtubeUrlError: String?
    @Published var ctaType: CTAType = .book
    @Published var ctaUrl: String = ""
    @Published var isCreating = false
    @Published var error: String?
    @Published var metadata: LandingPageMetadata = LandingPageTheme.air.toMetadata()
    
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
        return YouTubeHelper.isValidYouTubeURL(urlString)
    }
    
    
    func createLandingPage(campaignId: UUID, campaignName: String) async throws -> CampaignLandingPage {
        isCreating = true
        error = nil
        defer { isCreating = false }
        
        do {
            // Update metadata with current hero settings
            metadata.heroType = heroType == .youtube ? "youtube" : "image"
            
            // Validate YouTube URL if hero type is YouTube
            if heroType == .youtube {
                if !isValidYouTubeURL(heroVideoUrl) {
                    youtubeUrlError = "Please enter a valid YouTube URL"
                    throw NSError(domain: "LandingPageCreateViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid YouTube URL"])
                }
                
                // Extract YouTube video ID and generate thumbnail URL
                if let videoId = YouTubeHelper.extractYouTubeId(from: heroVideoUrl) {
                    metadata.youtubeURL = heroVideoUrl
                    metadata.youtubeThumbnailURL = YouTubeHelper.youtubeThumbnailURL(videoId: videoId)
                }
            }
            
            // Generate slug
            let slug = CampaignLandingPage.generateSlug(from: campaignName)
            
            // Upload hero media based on type
            var heroUrl: String? = nil
            switch heroType {
            case .image:
                if let heroImage = heroImage {
                    heroUrl = try await landingPageService.uploadHeroImage(heroImage, campaignId: campaignId)
                    metadata.heroImageURL = heroUrl
                }
            case .video:
                if let heroVideo = heroVideo {
                    let videoData = try Data(contentsOf: heroVideo)
                    let fileExtension = heroVideo.pathExtension.isEmpty ? "mp4" : heroVideo.pathExtension
                    heroUrl = try await landingPageService.uploadHeroVideo(videoData, campaignId: campaignId, fileExtension: fileExtension)
                }
            case .youtube:
                heroUrl = heroVideoUrl.isEmpty ? nil : heroVideoUrl
            }
            
            // Serialize metadata to JSON
            // Encode metadata struct to JSON Data, then convert to dictionary
            let metadataJSON: [String: AnyCodable]?
            do {
                let encoder = JSONEncoder()
                let metadataData = try encoder.encode(metadata)
                // Convert to dictionary
                if let jsonObject = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                    // Convert all values to AnyCodable
                    metadataJSON = jsonObject.mapValues { AnyCodable($0) }
                } else {
                    metadataJSON = nil
                }
            } catch {
                print("⚠️ [LandingPageCreateViewModel] Failed to encode metadata: \(error)")
                metadataJSON = nil
            }
            
            // Create landing page
            let landingPage = try await landingPageService.createLandingPage(
                campaignId: campaignId,
                slug: slug,
                title: title.isEmpty ? nil : title,
                headline: headline.isEmpty ? nil : headline,
                subheadline: subheadline.isEmpty ? nil : subheadline,
                heroType: heroType,
                heroUrl: heroUrl,
                ctaType: ctaType.rawValue,
                ctaUrl: ctaUrl.isEmpty ? nil : ctaUrl,
                metadata: metadataJSON
            )
            
            return landingPage
        } catch {
            if youtubeUrlError == nil {
                self.error = "Failed to create landing page: \(error.localizedDescription)"
            }
            print("❌ [LandingPageCreateViewModel] Error creating landing page: \(error)")
            throw error
        }
    }
}

