import Foundation
import SwiftUI

// MARK: - Contact Status

enum ContactStatus: String, Codable, CaseIterable {
    case hot = "hot"
    case warm = "warm"
    case cold = "cold"
    case new = "new"
    
    var displayName: String {
        switch self {
        case .hot: return "Hot"
        case .warm: return "Warm"
        case .cold: return "Cold"
        case .new: return "New"
        }
    }
    
    var color: Color {
        switch self {
        case .hot: return .error
        case .warm: return .warning
        case .cold: return .info
        case .new: return .muted
        }
    }
}

// MARK: - Contact

struct Contact: Codable, Identifiable, Equatable {
    let id: UUID
    var fullName: String
    var phone: String?
    var email: String?
    var address: String
    var campaignId: UUID?
    var farmId: UUID?
    var gersId: String?
    var addressId: UUID?
    var tags: String?
    var status: ContactStatus
    var lastContacted: Date?
    var notes: String?
    var reminderDate: Date?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case phone
        case email
        case address
        case campaignId = "campaign_id"
        case farmId = "farm_id"
        case gersId = "gers_id"
        case addressId = "address_id"
        case tags
        case status
        case lastContacted = "last_contacted"
        case notes
        case reminderDate = "reminder_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(
        id: UUID = UUID(),
        fullName: String,
        phone: String? = nil,
        email: String? = nil,
        address: String,
        campaignId: UUID? = nil,
        farmId: UUID? = nil,
        gersId: String? = nil,
        addressId: UUID? = nil,
        tags: String? = nil,
        status: ContactStatus = .new,
        lastContacted: Date? = nil,
        notes: String? = nil,
        reminderDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fullName = fullName
        self.phone = phone
        self.email = email
        self.address = address
        self.campaignId = campaignId
        self.farmId = farmId
        self.gersId = gersId
        self.addressId = addressId
        self.tags = tags
        self.status = status
        self.lastContacted = lastContacted
        self.notes = notes
        self.reminderDate = reminderDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Contact Extensions

extension Contact {
    var needsFollowUpToday: Bool {
        guard let reminderDate = reminderDate else { return false }
        return Calendar.current.isDateInToday(reminderDate)
    }
    
    var isNewThisWeek: Bool {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return createdAt >= weekAgo
    }
    
    var hasNoContactIn30Days: Bool {
        guard let lastContacted = lastContacted else { return true }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return lastContacted < thirtyDaysAgo
    }
    
    var lastContactedDisplay: String {
        guard let lastContacted = lastContacted else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastContacted, relativeTo: Date())
    }
}

// MARK: - Preview Helpers

extension Contact {
    static let mockContacts: [Contact] = [
        Contact(
            fullName: "John Smith",
            phone: "+1-555-0123",
            address: "123 Main St, Toronto, ON",
            campaignId: UUID(),
            status: .hot,
            lastContacted: Date().addingTimeInterval(-86400 * 2),
            notes: "Interested in listing property"
        ),
        Contact(
            fullName: "Sarah Johnson",
            phone: "+1-555-0456",
            email: "sarah@example.com",
            address: "456 Oak Ave, Toronto, ON",
            farmId: UUID(),
            status: .warm,
            lastContacted: Date().addingTimeInterval(-86400 * 10),
            notes: "Left flyer, follow up in 2 weeks"
        ),
        Contact(
            fullName: "Mike Davis",
            phone: "+1-555-0789",
            address: "789 Pine St, Toronto, ON",
            status: .cold,
            lastContacted: Date().addingTimeInterval(-86400 * 45),
            notes: "Not interested at this time"
        ),
        Contact(
            fullName: "Emily Chen",
            address: "321 Elm St, Toronto, ON",
            status: .new,
            notes: "New lead from door knocking"
        )
    ]
}
