import Foundation
import Supabase

/// API layer for landing page event tracking
actor LandingPageEventsAPI {
    static let shared = LandingPageEventsAPI()
    
    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }
    
    private init() {}
    
    /// Track an event for a landing page
    /// - Parameters:
    ///   - landingPageId: Landing page ID
    ///   - eventType: Event type ("scan", "view", "click")
    ///   - device: Optional device identifier
    func trackEvent(landingPageId: UUID, eventType: String, device: String? = nil) async throws {
        let eventData: [String: AnyCodable] = [
            "landing_page_id": AnyCodable(landingPageId.uuidString),
            "event_type": AnyCodable(eventType),
            "device": device != nil ? AnyCodable(device!) : AnyCodable(NSNull()),
            "timestamp": AnyCodable(Date())
        ]
        
        _ = try await client
            .from("landing_page_events")
            .insert(eventData)
            .execute()
    }
    
    /// Fetch analytics for a landing page
    /// - Parameter landingPageId: Landing page ID
    /// - Returns: Analytics summary
    func fetchAnalytics(landingPageId: UUID) async throws -> LandingPageAnalytics {
        // Fetch all events for this landing page
        let response: PostgrestResponse<[LandingPageEvent]> = try await client
            .from("landing_page_events")
            .select()
            .eq("landing_page_id", value: landingPageId.uuidString)
            .order("timestamp", ascending: false)
            .execute()
        
        let events = response.value
        
        // Calculate statistics
        let scans = events.filter { $0.eventType == "scan" }.count
        let views = events.filter { $0.eventType == "view" }.count
        let clicks = events.filter { $0.eventType == "click" }.count
        
        // Calculate CTR (click-through rate)
        let ctr = views > 0 ? Double(clicks) / Double(views) : 0.0
        
        // Group by date
        let calendar = Calendar.current
        var eventsByDate: [Date: [LandingPageEvent]] = [:]
        for event in events {
            let date = calendar.startOfDay(for: event.timestamp)
            eventsByDate[date, default: []].append(event)
        }
        
        return LandingPageAnalytics(
            landingPageId: landingPageId,
            totalScans: scans,
            totalViews: views,
            totalClicks: clicks,
            clickThroughRate: ctr,
            events: events,
            eventsByDate: eventsByDate
        )
    }
    
    /// Fetch analytics for multiple landing pages (campaign-level)
    /// - Parameter landingPageIds: Array of landing page IDs
    /// - Returns: Combined analytics
    func fetchAnalyticsForPages(_ landingPageIds: [UUID]) async throws -> LandingPageAnalytics {
        guard !landingPageIds.isEmpty else {
            return LandingPageAnalytics(
                landingPageId: UUID(),
                totalScans: 0,
                totalViews: 0,
                totalClicks: 0,
                clickThroughRate: 0.0,
                events: [],
                eventsByDate: [:]
            )
        }
        
        let idStrings = landingPageIds.map { $0.uuidString }
        
        // Fetch all events for these landing pages
        let response: PostgrestResponse<[LandingPageEvent]> = try await client
            .from("landing_page_events")
            .select()
            .in("landing_page_id", value: idStrings)
            .order("timestamp", ascending: false)
            .execute()
        
        let events = response.value
        
        // Calculate statistics
        let scans = events.filter { $0.eventType == "scan" }.count
        let views = events.filter { $0.eventType == "view" }.count
        let clicks = events.filter { $0.eventType == "click" }.count
        
        // Calculate CTR
        let ctr = views > 0 ? Double(clicks) / Double(views) : 0.0
        
        // Group by date
        let calendar = Calendar.current
        var eventsByDate: [Date: [LandingPageEvent]] = [:]
        for event in events {
            let date = calendar.startOfDay(for: event.timestamp)
            eventsByDate[date, default: []].append(event)
        }
        
        return LandingPageAnalytics(
            landingPageId: UUID(), // Combined analytics, no single page ID
            totalScans: scans,
            totalViews: views,
            totalClicks: clicks,
            clickThroughRate: ctr,
            events: events,
            eventsByDate: eventsByDate
        )
    }
}

/// Landing page event model
public struct LandingPageEvent: Identifiable, Codable {
    public let id: UUID
    public let landingPageId: UUID
    public let eventType: String
    public let device: String?
    public let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case landingPageId = "landing_page_id"
        case eventType = "event_type"
        case device
        case timestamp
    }
}

/// Landing page analytics summary
public struct LandingPageAnalytics {
    public let landingPageId: UUID
    public let totalScans: Int
    public let totalViews: Int
    public let totalClicks: Int
    public let clickThroughRate: Double
    public let events: [LandingPageEvent]
    public let eventsByDate: [Date: [LandingPageEvent]]
    
    /// Formatted CTR as percentage
    public var formattedCTR: String {
        String(format: "%.1f%%", clickThroughRate * 100)
    }
}

