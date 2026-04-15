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
    /// Row badge for last CRM sync attempt (`sync_status` on `contacts` / `field_leads`).
    var crmSyncStatusLabel: String? {
        guard let syncStatus else { return nil }
        switch syncStatus {
        case .pending: return "CRM…"
        case .synced: return "Synced"
        case .failed: return "Sync failed"
        }
    }

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
    
    /// List row address: drops trailing province (e.g. ON) and postal / ZIP segments after commas.
    var listDisplayAddress: String {
        Self.stripTrailingProvinceAndPostal(from: address)
    }
    
    private static func stripTrailingProvinceAndPostal(from raw: String) -> String {
        var parts = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count > 1 else { return trimmed }
        
        let twoLetterProvinceOrState = #"^[A-Za-z]{2}$"#
        let canadianPostal = #"^[A-Za-z]\d[A-Za-z](\s?\d[A-Za-z]\d)?$"#
        let usZip = #"^\d{5}(-\d{4})?$"#
        let provinceSpacePostal = #"^[A-Za-z]{2}\s+[A-Za-z]\d[A-Za-z]"#
        
        func matches(_ s: String, pattern: String) -> Bool {
            s.range(of: pattern, options: .regularExpression) != nil
        }
        
        while let last = parts.last {
            if matches(last, pattern: usZip)
                || matches(last, pattern: canadianPostal)
                || matches(last, pattern: provinceSpacePostal) {
                parts.removeLast()
                continue
            }
            if matches(last, pattern: twoLetterProvinceOrState) {
                parts.removeLast()
                continue
            }
            break
        }
        let result = parts.joined(separator: ", ")
        return result.isEmpty ? trimmed : result
    }
}
