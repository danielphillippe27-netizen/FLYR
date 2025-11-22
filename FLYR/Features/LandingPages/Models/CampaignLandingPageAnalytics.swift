import Foundation

/// Campaign landing page analytics model matching the campaign_landing_page_analytics table schema
public struct CampaignLandingPageAnalytics: Identifiable, Codable, Equatable {
    public let id: UUID
    public let landingPageId: UUID
    public let views: Int
    public let uniqueViews: Int
    public let ctaClicks: Int
    public let timestampBucket: Date
    
    public init(
        id: UUID = UUID(),
        landingPageId: UUID,
        views: Int = 0,
        uniqueViews: Int = 0,
        ctaClicks: Int = 0,
        timestampBucket: Date = Date()
    ) {
        self.id = id
        self.landingPageId = landingPageId
        self.views = views
        self.uniqueViews = uniqueViews
        self.ctaClicks = ctaClicks
        self.timestampBucket = timestampBucket
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case landingPageId = "landing_page_id"
        case views
        case uniqueViews = "unique_views"
        case ctaClicks = "cta_clicks"
        case timestampBucket = "timestamp_bucket"
    }
}



