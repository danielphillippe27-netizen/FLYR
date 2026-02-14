import Foundation
import SwiftUI

// MARK: - Field Lead Status

enum FieldLeadStatus: String, Codable, CaseIterable {
    case notHome = "not_home"
    case interested = "interested"
    case qrScanned = "qr_scanned"
    case noAnswer = "no_answer"
    
    var displayName: String {
        switch self {
        case .notHome: return "Not Home"
        case .interested: return "Interested"
        case .qrScanned: return "QR Scanned"
        case .noAnswer: return "No Answer"
        }
    }
    
    var color: Color {
        switch self {
        case .notHome: return .flyrPrimary
        case .interested: return .green
        case .qrScanned: return .blue
        case .noAnswer: return .gray
        }
    }
}

// MARK: - Sync Status

enum FieldLeadSyncStatus: String, Codable {
    case pending = "pending"
    case synced = "synced"
    case failed = "failed"
}

// MARK: - Field Lead

struct FieldLead: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var userId: UUID
    var address: String
    var name: String?
    var phone: String?
    var email: String?
    var status: FieldLeadStatus
    var notes: String?
    var qrCode: String?
    var campaignId: UUID?
    var sessionId: UUID?
    var externalCrmId: String?
    var lastSyncedAt: Date?
    var syncStatus: FieldLeadSyncStatus?
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case address
        case name
        case phone
        case email
        case status
        case notes
        case qrCode = "qr_code"
        case campaignId = "campaign_id"
        case sessionId = "session_id"
        case externalCrmId = "external_crm_id"
        case lastSyncedAt = "last_synced_at"
        case syncStatus = "sync_status"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        address: String,
        name: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        status: FieldLeadStatus = .notHome,
        notes: String? = nil,
        qrCode: String? = nil,
        campaignId: UUID? = nil,
        sessionId: UUID? = nil,
        externalCrmId: String? = nil,
        lastSyncedAt: Date? = nil,
        syncStatus: FieldLeadSyncStatus? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.address = address
        self.name = name
        self.phone = phone
        self.email = email
        self.status = status
        self.notes = notes
        self.qrCode = qrCode
        self.campaignId = campaignId
        self.sessionId = sessionId
        self.externalCrmId = externalCrmId
        self.lastSyncedAt = lastSyncedAt
        self.syncStatus = syncStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Display Helpers

extension FieldLead {
    var displayNameOrUnknown: String {
        if let name = name, !name.isEmpty { return name }
        return "Unknown"
    }
    
    var relativeTimeDisplay: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var noteOrQRPreview: String {
        if let notes = notes, !notes.isEmpty {
            let s = String(notes.prefix(30))
            return notes.count > 30 ? s + "…" : s
        }
        if let qr = qrCode, !qr.isEmpty {
            return "QR: \(qr)"
        }
        return ""
    }
}
