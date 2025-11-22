import Foundation

/// Experiment variant model matching the experiment_variants table schema
public struct ExperimentVariant: Identifiable, Codable, Equatable {
    public let id: UUID
    public let experimentId: UUID
    public let key: String // "A" or "B"
    public let urlSlug: String
    
    public init(
        id: UUID = UUID(),
        experimentId: UUID,
        key: String,
        urlSlug: String
    ) {
        self.id = id
        self.experimentId = experimentId
        self.key = key
        self.urlSlug = urlSlug
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case experimentId = "experiment_id"
        case key
        case urlSlug = "url_slug"
    }
    
    /// Full URL for this variant
    public var fullURL: String {
        "https://flyrpro.app/q/\(urlSlug)?variant=\(key)"
    }
    
    /// Convenience computed properties
    public var isVariantA: Bool { key == "A" }
    public var isVariantB: Bool { key == "B" }
}

