import Foundation

/// Model for address landing page content (videos, images, forms)
public struct AddressContent: Identifiable, Codable, Equatable {
    public let id: UUID
    public let addressId: UUID // FK to campaign_addresses
    public let title: String
    public let videos: [String] // URLs to Supabase Storage
    public let images: [String] // URLs to Supabase Storage
    public let forms: [FormConfig] // Serialized form configurations
    public let updatedAt: Date
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        addressId: UUID,
        title: String,
        videos: [String] = [],
        images: [String] = [],
        forms: [FormConfig] = [],
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.addressId = addressId
        self.title = title
        self.videos = videos
        self.images = images
        self.forms = forms
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }
}

/// Form configuration model
public struct FormConfig: Codable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let fields: [FormField]
    public let submitURL: String? // Optional webhook or API endpoint
    
    public init(
        id: UUID = UUID(),
        title: String,
        fields: [FormField],
        submitURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fields = fields
        self.submitURL = submitURL
    }
}

/// Form field model
public struct FormField: Codable, Equatable, Identifiable {
    public let id: UUID
    public let label: String
    public let type: FieldType
    public let placeholder: String?
    public let required: Bool
    public let options: [String]? // For select/dropdown fields
    
    public enum FieldType: String, Codable {
        case text
        case email
        case phone
        case textarea
        case select
        case checkbox
        case radio
    }
    
    public init(
        id: UUID = UUID(),
        label: String,
        type: FieldType,
        placeholder: String? = nil,
        required: Bool = false,
        options: [String]? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.placeholder = placeholder
        self.required = required
        self.options = options
    }
}





