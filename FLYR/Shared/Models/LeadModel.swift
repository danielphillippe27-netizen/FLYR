import Foundation

/// Unified lead model that normalizes all lead sources in FLYR
/// Used for CRM sync across all integration providers
struct LeadModel: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String?
    let phone: String?
    let email: String?
    let address: String?
    let source: String  // "QR Scan", "Door Knock", "Farm Lead", "Contact", etc.
    let campaignId: UUID?
    let notes: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case email
        case address
        case source
        case campaignId = "campaign_id"
        case notes
        case createdAt = "created_at"
    }
    
    init(
        id: UUID = UUID(),
        name: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        source: String,
        campaignId: UUID? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.source = source
        self.campaignId = campaignId
        self.notes = notes
        self.createdAt = createdAt
    }
    
    /// Check if lead has at least one contact field (valid for CRM sync)
    var isValidLead: Bool {
        return name != nil && !name!.isEmpty ||
               phone != nil && !phone!.isEmpty ||
               email != nil && !email!.isEmpty ||
               address != nil && !address!.isEmpty
    }
}

// MARK: - Convenience Initializers

extension LeadModel {
    /// Create LeadModel from FarmLead
    init(from farmLead: FarmLead) {
        self.init(
            id: farmLead.id,
            name: farmLead.name,
            phone: farmLead.phone,
            email: farmLead.email,
            address: farmLead.address,
            source: farmLead.leadSource.displayName,
            campaignId: nil,
            notes: nil,
            createdAt: farmLead.createdAt
        )
    }
    
    /// Create LeadModel from Contact
    init(from contact: Contact) {
        self.init(
            id: contact.id,
            name: contact.fullName,
            phone: contact.phone,
            email: contact.email,
            address: contact.address,
            source: "Contact",
            campaignId: contact.campaignId,
            notes: contact.notes,
            createdAt: contact.createdAt
        )
    }
    
    /// Create LeadModel from QR scan data
    init(
        id: UUID = UUID(),
        qrScanData: (name: String?, phone: String?, email: String?, address: String?),
        campaignId: UUID? = nil,
        notes: String? = nil
    ) {
        self.init(
            id: id,
            name: qrScanData.name,
            phone: qrScanData.phone,
            email: qrScanData.email,
            address: qrScanData.address,
            source: "QR Scan",
            campaignId: campaignId,
            notes: notes,
            createdAt: Date()
        )
    }
    
    /// Create LeadModel from door knock
    init(
        id: UUID = UUID(),
        doorKnockData: (name: String?, phone: String?, email: String?, address: String?),
        campaignId: UUID? = nil,
        notes: String? = nil
    ) {
        self.init(
            id: id,
            name: doorKnockData.name,
            phone: doorKnockData.phone,
            email: doorKnockData.email,
            address: doorKnockData.address,
            source: "Door Knock",
            campaignId: campaignId,
            notes: notes,
            createdAt: Date()
        )
    }
}


