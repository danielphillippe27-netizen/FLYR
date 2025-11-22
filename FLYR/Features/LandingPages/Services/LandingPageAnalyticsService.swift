import Foundation

/// Service for aggregating landing page analytics and generating reports
actor LandingPageAnalyticsService {
    static let shared = LandingPageAnalyticsService()
    
    private let eventsAPI = LandingPageEventsAPI.shared
    private let landingPagesAPI = LandingPagesAPI.shared
    
    private init() {}
    
    /// Get analytics for a single landing page
    /// - Parameter landingPageId: Landing page ID
    /// - Returns: Analytics summary
    func getAnalytics(landingPageId: UUID) async throws -> LandingPageAnalytics {
        return try await eventsAPI.fetchAnalytics(landingPageId: landingPageId)
    }
    
    /// Get analytics for all landing pages in a campaign
    /// - Parameter campaignId: Campaign ID
    /// - Returns: Combined analytics and per-address breakdown
    func getCampaignAnalytics(campaignId: UUID) async throws -> CampaignLandingPageAnalyticsLegacy {
        // Fetch all landing pages for campaign
        let pages = try await landingPagesAPI.fetchLandingPagesForCampaign(campaignId: campaignId)
        
        guard !pages.isEmpty else {
            return CampaignLandingPageAnalyticsLegacy(
                campaignId: campaignId,
                totalPages: 0,
                totalScans: 0,
                totalViews: 0,
                totalClicks: 0,
                overallCTR: 0.0,
                perAddressPerformance: [],
                topStreets: []
            )
        }
        
        // Get analytics for all pages
        let pageIds = pages.map { $0.id }
        let combinedAnalytics = try await eventsAPI.fetchAnalyticsForPages(pageIds)
        
        // Build per-address performance
        var perAddressPerformance: [AddressPerformance] = []
        for page in pages {
            if let addressId = page.addressId {
                let analytics = try await eventsAPI.fetchAnalytics(landingPageId: page.id)
                perAddressPerformance.append(AddressPerformance(
                    addressId: addressId,
                    landingPageId: page.id,
                    addressFormatted: page.name,
                    scans: analytics.totalScans,
                    views: analytics.totalViews,
                    clicks: analytics.totalClicks,
                    ctr: analytics.clickThroughRate
                ))
            }
        }
        
        // Sort by views (top performers)
        perAddressPerformance.sort { $0.views > $1.views }
        
        // Extract top streets (simplified - could be enhanced with address parsing)
        let topStreets = Array(perAddressPerformance.prefix(10))
            .map { TopStreet(
                street: extractStreet(from: $0.addressFormatted),
                views: $0.views,
                clicks: $0.clicks
            ) }
        
        return CampaignLandingPageAnalyticsLegacy(
            campaignId: campaignId,
            totalPages: pages.count,
            totalScans: combinedAnalytics.totalScans,
            totalViews: combinedAnalytics.totalViews,
            totalClicks: combinedAnalytics.totalClicks,
            overallCTR: combinedAnalytics.clickThroughRate,
            perAddressPerformance: perAddressPerformance,
            topStreets: topStreets
        )
    }
    
    /// Generate performance report
    /// - Parameter campaignId: Campaign ID
    /// - Returns: Performance report
    func generatePerformanceReport(campaignId: UUID) async throws -> LandingPagePerformanceReport {
        let analytics = try await getCampaignAnalytics(campaignId: campaignId)
        
        // Calculate additional metrics
        let averageViewsPerPage = analytics.totalPages > 0 
            ? Double(analytics.totalViews) / Double(analytics.totalPages) 
            : 0.0
        let averageCTR = analytics.perAddressPerformance.isEmpty
            ? 0.0
            : analytics.perAddressPerformance.map { $0.ctr }.reduce(0, +) / Double(analytics.perAddressPerformance.count)
        
        // Find best and worst performers
        let bestPerformer = analytics.perAddressPerformance.max(by: { $0.views < $1.views })
        let worstPerformer = analytics.perAddressPerformance.min(by: { $0.views < $1.views })
        
        return LandingPagePerformanceReport(
            campaignId: campaignId,
            generatedAt: Date(),
            totalPages: analytics.totalPages,
            totalScans: analytics.totalScans,
            totalViews: analytics.totalViews,
            totalClicks: analytics.totalClicks,
            overallCTR: analytics.overallCTR,
            averageViewsPerPage: averageViewsPerPage,
            averageCTR: averageCTR,
            bestPerformer: bestPerformer,
            worstPerformer: worstPerformer,
            topStreets: analytics.topStreets,
            perAddressPerformance: analytics.perAddressPerformance
        )
    }
    
    /// Extract street name from formatted address
    private func extractStreet(from address: String) -> String {
        // Simple extraction - take first part before comma
        let components = address.components(separatedBy: ",")
        if let streetPart = components.first {
            // Remove house number if present
            let parts = streetPart.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            if parts.count > 1 {
                return parts.dropFirst().joined(separator: " ")
            }
            return streetPart.trimmingCharacters(in: .whitespaces)
        }
        return address
    }
}

/// Campaign-level landing page analytics (legacy - use Models/CampaignLandingPageAnalytics instead)
public struct CampaignLandingPageAnalyticsLegacy {
    public let campaignId: UUID
    public let totalPages: Int
    public let totalScans: Int
    public let totalViews: Int
    public let totalClicks: Int
    public let overallCTR: Double
    public let perAddressPerformance: [AddressPerformance]
    public let topStreets: [TopStreet]
}

/// Per-address performance metrics
public struct AddressPerformance: Identifiable {
    public let id: UUID
    public let addressId: UUID
    public let landingPageId: UUID
    public let addressFormatted: String
    public let scans: Int
    public let views: Int
    public let clicks: Int
    public let ctr: Double
    
    public init(
        addressId: UUID,
        landingPageId: UUID,
        addressFormatted: String,
        scans: Int,
        views: Int,
        clicks: Int,
        ctr: Double
    ) {
        self.id = addressId
        self.addressId = addressId
        self.landingPageId = landingPageId
        self.addressFormatted = addressFormatted
        self.scans = scans
        self.views = views
        self.clicks = clicks
        self.ctr = ctr
    }
    
    public var formattedCTR: String {
        String(format: "%.1f%%", ctr * 100)
    }
}

/// Top street performance
public struct TopStreet: Identifiable {
    public let id = UUID()
    public let street: String
    public let views: Int
    public let clicks: Int
}

/// Performance report
public struct LandingPagePerformanceReport {
    public let campaignId: UUID
    public let generatedAt: Date
    public let totalPages: Int
    public let totalScans: Int
    public let totalViews: Int
    public let totalClicks: Int
    public let overallCTR: Double
    public let averageViewsPerPage: Double
    public let averageCTR: Double
    public let bestPerformer: AddressPerformance?
    public let worstPerformer: AddressPerformance?
    public let topStreets: [TopStreet]
    public let perAddressPerformance: [AddressPerformance]
    
    public var formattedOverallCTR: String {
        String(format: "%.1f%%", overallCTR * 100)
    }
    
    public var formattedAverageCTR: String {
        String(format: "%.1f%%", averageCTR * 100)
    }
}

