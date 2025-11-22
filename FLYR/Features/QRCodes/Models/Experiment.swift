import Foundation

/// Experiment model matching the experiments table schema
public struct Experiment: Identifiable, Codable, Equatable {
    public let id: UUID
    public let campaignId: UUID
    public let landingPageId: UUID
    public let name: String
    public let status: String // "draft", "running", "completed"
    public let createdAt: Date
    
    // Variants are populated separately via API
    public var variants: [ExperimentVariant] = []
    
    public init(
        id: UUID = UUID(),
        campaignId: UUID,
        landingPageId: UUID,
        name: String,
        status: String = "draft",
        createdAt: Date = Date(),
        variants: [ExperimentVariant] = []
    ) {
        self.id = id
        self.campaignId = campaignId
        self.landingPageId = landingPageId
        self.name = name
        self.status = status
        self.createdAt = createdAt
        self.variants = variants
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case campaignId = "campaign_id"
        case landingPageId = "landing_page_id"
        case name
        case status
        case createdAt = "created_at"
    }
    
    /// Convenience computed properties for status
    public var isDraft: Bool { status == "draft" }
    public var isRunning: Bool { status == "running" }
    public var isCompleted: Bool { status == "completed" }
}

