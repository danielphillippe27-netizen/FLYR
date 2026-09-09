import Foundation
import Combine
import PhotosUI
import SwiftUI
import Supabase
import UIKit
import UniformTypeIdentifiers

private enum SalespersonAPIError: LocalizedError {
    case missingWorkspace
    case badURL
    case status(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Salesperson workspace is not available."
        case .badURL:
            return "Unable to build request."
        case .status(_, let message):
            return message
        }
    }
}

private struct FlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decodeValue<T: Decodable>(_ type: T.Type, forAny keys: [String]) throws -> T? {
        for key in keys {
            let codingKey = FlexibleCodingKey(key)
            if contains(codingKey), let value = try decodeIfPresent(type, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeValue<T: Decodable>(_ type: T.Type, forAny keys: [String], default defaultValue: T) throws -> T {
        try decodeValue(type, forAny: keys) ?? defaultValue
    }
}

private struct SalespersonDiallerLead: Identifiable, Codable, Equatable {
    let id: UUID
    var salesContactId: String?
    var name: String
    var phone: String
    var company: String?
    var role: String?
    var email: String?
    var website: String?
    var websiteDomain: String?
    var address: String?
    var city: String?
    var region: String?
    var countryCode: String?
    var timeZoneIdentifier: String?
    var listId: String?
    var listName: String?
    var latestCallRecording: SalespersonDiallerRecordingSummary?
    var isStarred: Bool?
    var disposition: String?
    var notes: String?
    var calledAt: Date?
    var lastContactedAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case salesContactId = "sales_contact_id"
        case name
        case phone
        case company
        case role
        case email
        case website
        case websiteDomain = "website_domain"
        case address
        case city
        case region
        case countryCode = "country_code"
        case timeZoneIdentifier = "timezone"
        case listId = "list_id"
        case listName = "list_name"
        case latestCallRecording = "latest_call_recording"
        case isStarred = "is_starred"
        case disposition
        case notes
        case calledAt = "called_at"
        case lastContactedAt = "last_contacted_at"
        case createdAt = "created_at"
    }

    init(
        id: UUID,
        salesContactId: String? = nil,
        name: String,
        phone: String,
        company: String?,
        email: String?,
        website: String?,
        websiteDomain: String?,
        listId: String?,
        listName: String?,
        latestCallRecording: SalespersonDiallerRecordingSummary?,
        isStarred: Bool?,
        disposition: String?,
        notes: String?,
        calledAt: Date?,
        createdAt: Date?,
        role: String? = nil,
        address: String? = nil,
        city: String? = nil,
        region: String? = nil,
        countryCode: String? = nil,
        timeZoneIdentifier: String? = nil,
        lastContactedAt: Date? = nil
    ) {
        self.id = id
        self.salesContactId = salesContactId
        self.name = name
        self.phone = phone
        self.company = company
        self.role = role
        self.email = email
        self.website = website
        self.websiteDomain = websiteDomain
        self.address = address
        self.city = city
        self.region = region
        self.countryCode = countryCode
        self.timeZoneIdentifier = timeZoneIdentifier
        self.listId = listId
        self.listName = listName
        self.latestCallRecording = latestCallRecording
        self.isStarred = isStarred
        self.disposition = disposition
        self.notes = notes
        self.calledAt = calledAt
        self.lastContactedAt = lastContactedAt
        self.createdAt = createdAt
    }

    var displayBusinessName: String {
        company?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Unnamed business"
    }

    var companyAndRoleLine: String? {
        [company?.nilIfEmpty, role?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    var locationLine: String? {
        let structured = [city?.nilIfEmpty, region?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfEmpty
        return structured ?? address?.nilIfEmpty
    }

    var resolvedTimeZone: TimeZone? {
        if let timeZoneIdentifier = timeZoneIdentifier?.nilIfEmpty,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            return timeZone
        }
        let normalizedRegion = region?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedRegion == "on" || normalizedRegion == "ontario" {
            return TimeZone(identifier: "America/Toronto")
        }
        return nil
    }

    var lastContactedDate: Date? { lastContactedAt ?? calledAt }

    var listGroupTitle: String {
        if let listName = listName?.nilIfEmpty {
            return listName
        }
        guard let createdAt else { return "Dialler queue" }
        return "WolfGrid - \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var listGroupId: String {
        listId?.nilIfEmpty ?? listGroupTitle.lowercased()
    }

    var hasExplicitListIdentity: Bool {
        listId?.nilIfEmpty != nil || listName?.nilIfEmpty != nil
    }

    var isUnconvertedListLead: Bool {
        hasExplicitListIdentity && salesContactId?.nilIfEmpty == nil
    }
}

private struct SalespersonDiallerRecordingSummary: Codable, Equatable {
    let status: String?
    let available: Bool
    let durationSeconds: Int?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case status
        case available
        case durationSeconds = "duration_seconds"
        case updatedAt = "updated_at"
    }
}

private struct SalespersonDiallerLeadsResponse: Decodable {
    let leads: [SalespersonDiallerLead]
}

private struct SalespersonDiallerImportLead: Codable, Equatable {
    let name: String
    let phone: String
    let company: String?
    let email: String?
    let listId: String?
    let listName: String?

    enum CodingKeys: String, CodingKey {
        case name
        case phone
        case company
        case email
        case listId = "list_id"
        case listName = "list_name"
    }

    init(
        name: String,
        phone: String,
        company: String?,
        email: String?,
        listId: String? = nil,
        listName: String? = nil
    ) {
        self.name = name
        self.phone = phone
        self.company = company
        self.email = email
        self.listId = listId
        self.listName = listName
    }
}

private struct SalespersonDiallerSmartListOption: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let description: String
    let count: Int
    let dialableCount: Int
    let leads: [SalespersonDiallerImportLead]
}

private struct SalespersonDiallerSmartListsResponse: Decodable {
    let lists: [SalespersonDiallerSmartListOption]
}

private struct SalespersonDiallerSmartListCreateResponse: Decodable {
    let list: SalespersonDiallerSmartListOption
}

private struct SalespersonResearchSourcedText: Decodable, Equatable {
    let value: String?
    let confidence: String
    let sources: [String]
}

private struct SalespersonResearchSourcedList: Decodable, Equatable {
    let values: [String]
    let confidence: String
    let sources: [String]
}

private struct SalespersonResearchDecisionMaker: Decodable, Equatable, Identifiable {
    let name: String
    let role: String?
    let workEmail: String?
    let directPhone: String?
    let linkedinUrl: String?
    let confidence: String
    let sources: [String]

    var id: String { "\(name)|\(role ?? "")" }
}

private struct SalespersonCompanyResearchResult: Decodable, Equatable {
    struct Company: Decodable, Equatable {
        let resolvedName: SalespersonResearchSourcedText
        let summary: SalespersonResearchSourcedText
        let website: SalespersonResearchSourcedText
        let phone: SalespersonResearchSourcedText
        let publicEmail: SalespersonResearchSourcedText
        let address: SalespersonResearchSourcedText
        let foundedYear: SalespersonResearchSourcedText
        let timeInBusiness: SalespersonResearchSourcedText
        let employeeEstimate: SalespersonResearchSourcedText
        let ownership: SalespersonResearchSourcedText
        let services: SalespersonResearchSourcedList
        let serviceAreas: SalespersonResearchSourcedList
        let locations: SalespersonResearchSourcedList
        let hours: SalespersonResearchSourcedList
    }

    struct Reputation: Decodable, Equatable {
        let ratingSummary: SalespersonResearchSourcedText
        let positiveThemes: SalespersonResearchSourcedList
        let negativeThemes: SalespersonResearchSourcedList
    }

    struct Presence: Decodable, Equatable {
        let socialProfiles: SalespersonResearchSourcedList
        let recentActivity: SalespersonResearchSourcedList
        let websiteTechnology: SalespersonResearchSourcedList
    }

    struct Signal: Decodable, Equatable, Identifiable {
        let title: String
        let detail: String
        let observedAt: String?
        let confidence: String
        let sources: [String]
        var id: String { "\(title)|\(detail)" }
    }

    struct Signals: Decodable, Equatable {
        let recentNews: [Signal]
        let hiringAndGrowth: [Signal]
        let competitors: SalespersonResearchSourcedList
    }

    struct CallBrief: Decodable, Equatable {
        let opener: String
        let summary: String
        let conversationHooks: [String]
        let inferredOpportunities: [String]
        let caveats: [String]
    }

    let company: Company
    let decisionMakers: [SalespersonResearchDecisionMaker]
    let reputation: Reputation
    let presence: Presence
    let signals: Signals
    let callBrief: CallBrief
    let overallConfidence: String
    let unresolvedFields: [String]

    var website: String? { company.website.value?.nilIfEmpty }
    var instagram: String? {
        presence.socialProfiles.values.first { $0.localizedCaseInsensitiveContains("instagram.com/") }?.nilIfEmpty
    }
    var timeInBusiness: String? {
        company.timeInBusiness.value?.nilIfEmpty
            ?? company.foundedYear.value?.nilIfEmpty.map { "Founded \($0)" }
    }
    var googleReviews: String? { reputation.ratingSummary.value?.nilIfEmpty }
    var hasVisibleResearch: Bool {
        website != nil || instagram != nil || timeInBusiness != nil || googleReviews != nil
    }
}

private struct SalespersonCompanyResearchSource: Decodable, Equatable, Identifiable {
    let url: String
    let title: String?
    var id: String { url }
}

private struct SalespersonCompanyResearchRecord: Decodable, Equatable, Identifiable {
    let id: String
    let status: String
    let result: SalespersonCompanyResearchResult?
    let sources: [SalespersonCompanyResearchSource]?
    let completedAt: Date?
    let expiresAt: Date?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, status, result, sources
        case completedAt = "completed_at"
        case expiresAt = "expires_at"
        case errorMessage = "error_message"
    }

    var isActive: Bool { status == "queued" || status == "researching" }
}

private struct SalespersonCompanyResearchCompany: Decodable, Equatable {
    let id: String
    let name: String
}

private struct SalespersonCompanyResearchResponse: Decodable, Equatable {
    let company: SalespersonCompanyResearchCompany?
    let active: SalespersonCompanyResearchRecord?
    let latest: SalespersonCompanyResearchRecord?
    let history: [SalespersonCompanyResearchRecord]
}

private struct SalespersonCompanyResearchBatch: Decodable, Equatable, Identifiable {
    let id: String
    let status: String
    let requestedCount: Int
    let skippedCount: Int

    enum CodingKeys: String, CodingKey {
        case id, status
        case requestedCount = "requested_count"
        case skippedCount = "skipped_count"
    }

    var isActive: Bool { status == "queued" || status == "researching" }
}

private struct SalespersonCompanyResearchBatchResponse: Decodable, Equatable {
    let batch: SalespersonCompanyResearchBatch
    let counts: [String: Int]?
    let queued: Int?
    let skipped: Int?
    let capped: Bool?
}

private struct SalespersonDiallerImportResponse: Decodable {
    let leads: [SalespersonDiallerLead]?
    let importedCount: Int?
    let warning: String?
}

private struct SalespersonDiallerRecording: Identifiable, Decodable, Equatable {
    let callId: String
    let createdAt: Date
    let durationSeconds: Int?
    let downloadUrl: String

    var id: String { callId }

    enum CodingKeys: String, CodingKey {
        case callId
        case createdAt
        case durationSeconds
        case downloadUrl
    }
}

private struct SalespersonDiallerRecordingGroup: Identifiable, Decodable, Equatable {
    let leadId: String
    let leadName: String
    let company: String?
    let phone: String?
    let isStarred: Bool
    let recordings: [SalespersonDiallerRecording]

    var id: String { leadId }
}

private struct SalespersonDiallerRecordingsResponse: Decodable {
    let groups: [SalespersonDiallerRecordingGroup]
}

private struct SalespersonRecordingExport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SalespersonDiallerCall: Identifiable, Decodable, Equatable {
    struct StatusPayload: Decodable, Equatable {
        let contentRetention: String?
        let contentSaved: Bool?

        enum CodingKeys: String, CodingKey {
            case contentRetention
            case contentSaved
        }
    }

    let id: UUID
    let callRequestId: String
    let toNumber: String?
    let fromNumber: String?
    let status: String?
    let disposition: String?
    let statusPayload: StatusPayload?

    var isContentSaved: Bool {
        statusPayload?.contentRetention == "saved" || statusPayload?.contentSaved == true
    }

    enum CodingKeys: String, CodingKey {
        case id
        case callRequestId = "call_request_id"
        case toNumber = "to_number_e164"
        case fromNumber = "from_number_e164"
        case status
        case disposition
        case statusPayload = "status_payload"
    }
}

private struct SalespersonDiallerCallResponse: Decodable {
    let call: SalespersonDiallerCall
}

private struct SalespersonCallLog: Identifiable, Decodable {
    let id: UUID
    let direction: String?
    let status: String?
    let disposition: String?
    let startedAt: Date?
    let createdAt: Date
    let durationSeconds: Int?
    let note: String?

    var occurredAt: Date { startedAt ?? createdAt }
    var outcome: String {
        (disposition?.nilIfEmpty ?? status?.nilIfEmpty ?? "Unknown")
            .replacingOccurrences(of: "_", with: " ").capitalized
    }

    enum CodingKeys: String, CodingKey {
        case id, direction, status, disposition
        case startedAt = "started_at"
        case createdAt = "created_at"
        case durationSeconds = "duration_seconds"
        case note = "disposition_note"
    }
}

private struct SalespersonInboxResponse: Decodable {
    let threads: [SalespersonInboxThread]?
    let items: [SalespersonInboxItem]?
    let counts: [String: Int]?
}

private struct SalespersonInboxContactSummary: Decodable, Equatable {
    let id: String
    let fullName: String?
    let phone: String?
    let email: String?
    let address: String?

    var displayName: String {
        fullName?.nilIfEmpty ?? phone?.nilIfEmpty ?? email?.nilIfEmpty ?? address?.nilIfEmpty ?? "Unknown contact"
    }
}

private struct SalespersonInboxEvent: Identifiable, Decodable, Equatable {
    let id: String
    let source: String
    let kind: String
    let direction: String?
    let title: String
    let preview: String?
    let body: String?
    let status: String
    let occurredAt: Date
    let readAt: Date?
    let fromLabel: String?
    let fromEmail: String?
    let fromPhone: String?
    let toLabel: String?
    let toEmail: String?
    let toPhone: String?
    let contactId: String?
    let href: String?
    var attachments: [SalespersonInboxAttachment]? = nil

    var isInboundMessage: Bool {
        (source == "sms" || source == "email") && direction == "inbound"
    }

    var isOutboundMessage: Bool {
        (source == "sms" || source == "email") && direction == "outbound"
    }
}

private struct SalespersonInboxAttachment: Codable, Equatable, Identifiable {
    let url: String
    let mimeType: String
    let fileName: String?
    let storagePath: String?

    var id: String { storagePath ?? url }
    var isVideo: Bool { mimeType.hasPrefix("video/") }
}

private struct SalespersonInboxPendingAttachment: Equatable {
    let data: Data
    let fileName: String
    let mimeType: String
    let previewImage: UIImage?

    var isVideo: Bool { mimeType.hasPrefix("video/") }
}

private struct SalespersonInboxThread: Identifiable, Decodable, Equatable {
    let id: String
    let contactId: String?
    let contact: SalespersonInboxContactSummary?
    let title: String
    let subtitle: String?
    let primaryPhone: String?
    let primaryEmail: String?
    let latestAt: Date
    let latestSource: String
    let latestPreview: String?
    let unreadCount: Int
    let needsResponse: Bool
    let events: [SalespersonInboxEvent]

    var textPhone: String? {
        if let primaryPhone = primaryPhone?.nilIfEmpty {
            return primaryPhone
        }
        if let contactPhone = contact?.phone?.nilIfEmpty {
            return contactPhone
        }

        return events.reversed().compactMap { event in
            if event.direction == "inbound" {
                return event.fromPhone?.nilIfEmpty
            }
            if event.direction == "outbound" {
                return event.toPhone?.nilIfEmpty
            }
            return event.fromPhone?.nilIfEmpty ?? event.toPhone?.nilIfEmpty
        }.first
    }

    var canText: Bool {
        textPhone != nil
    }

    var emailRecipient: String? {
        if let contactEmail = contact?.email?.nilIfEmpty {
            return contactEmail
        }

        let counterparty = events.reversed().compactMap { event -> String? in
            if event.direction == "outbound" {
                return event.toEmail?.nilIfEmpty
            }
            if event.direction == "inbound" {
                return event.fromEmail?.nilIfEmpty
            }
            return event.fromEmail?.nilIfEmpty ?? event.toEmail?.nilIfEmpty
        }.first
        return counterparty ?? primaryEmail?.nilIfEmpty
    }

    var canEmail: Bool {
        emailRecipient != nil
    }

    var rowTitle: String {
        let contactTitle = [
            contact?.fullName,
            contact?.phone,
            contact?.email,
            contact?.address
        ]
            .compactMap { $0?.normalizedInboxLine.nilIfEmpty }
            .first

        if let contactTitle { return contactTitle }

        let normalizedTitle = title.normalizedInboxLine
        if Self.isGenericTitle(normalizedTitle) || isOwnEmailAddress(normalizedTitle) {
            if latestSource == "email" {
                return emailRecipient?.normalizedInboxLine.nilIfEmpty
                    ?? textPhone?.normalizedInboxLine.nilIfEmpty
                    ?? normalizedTitle
            }
            return textPhone?.normalizedInboxLine.nilIfEmpty
                ?? emailRecipient?.normalizedInboxLine.nilIfEmpty
                ?? normalizedTitle
        }
        return normalizedTitle
    }

    var rowPreview: String? {
        latestPreview?.normalizedInboxLine.nilIfEmpty
    }

    private func isOwnEmailAddress(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return events.contains { event in
            let ownAddress: String?
            if event.direction == "outbound" {
                ownAddress = event.fromEmail
            } else if event.direction == "inbound" {
                ownAddress = event.toEmail
            } else {
                ownAddress = nil
            }
            return ownAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    private static func isGenericTitle(_ value: String) -> Bool {
        let lowercased = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercased == "inbound text"
            || lowercased == "incoming message"
            || lowercased == "sent message"
            || lowercased == "unknown contact"
            || lowercased == "no contact"
            || lowercased == "unnamed contact"
            || lowercased.hasPrefix("new text from ")
    }
}

private struct SalespersonInboxItem: Identifiable, Decodable, Equatable {
    let id: String
    let source: String
    let direction: String?
    let title: String
    let preview: String?
    let body: String?
    let fromLabel: String?
    let fromEmail: String?
    let fromPhone: String?
    let toLabel: String?
    let toEmail: String?
    let toPhone: String?
    let status: String
    let occurredAt: Date
    let readAt: Date?
    let contactId: String?
    let href: String?

    var isUnread: Bool { readAt == nil }
    var needsResponse: Bool {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["done", "closed", "responded", "archived"].contains(normalizedStatus)
    }
}

private struct SalespersonInboxSendResponse: Decodable {
    let sent: Bool?
    let emailId: String?
    let warning: String?
}

private struct SalespersonLeadMetadata: Decodable, Equatable, Hashable {
    let firstName: String?
    let lastName: String?
    let photoPath: String?
}

private struct SalespersonContactCreatePayload: Encodable {
    let workspaceId: String
    let name: String
    let company: String?
    let phone: String?
    let email: String?
    let address: String?
    let notes: String?
    let firstName: String
    let lastName: String
    let photoPath: String?
}

private struct SalespersonLeadMasterRow: Identifiable, Decodable, Equatable, Hashable {
    let id: UUID
    let salesContactId: String?
    let name: String
    let company: String?
    let phone: String?
    let email: String?
    let website: String?
    let address: String?
    let city: String?
    let region: String?
    let countryCode: String?
    let source: String?
    let listId: String?
    let listName: String?
    let leadState: String
    let attemptCount: Int?
    let lastAttemptedAt: Date?
    let disposition: String?
    let notes: String?
    let metadata: SalespersonLeadMetadata?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case salesContactId = "sales_contact_id"
        case name
        case company
        case phone
        case email
        case website
        case address
        case city
        case region
        case source
        case disposition
        case notes
        case metadata
        case listId = "list_id"
        case listName = "list_name"
        case countryCode = "country_code"
        case leadState = "lead_state"
        case attemptCount = "attempt_count"
        case lastAttemptedAt = "last_attempted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var primaryLine: String {
        phone?.nilIfEmpty ?? address?.nilIfEmpty ?? email?.nilIfEmpty ?? website?.nilIfEmpty ?? "No contact detail"
    }

    var displayName: String {
        name.nilIfEmpty ?? company?.nilIfEmpty ?? "Unnamed lead"
    }

    var sourceLabel: String {
        source?
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
            .nilIfEmpty ?? "Scraped"
    }

    var detailLine: String {
        [
            phone?.nilIfEmpty,
            websiteHost,
            locationLine
        ]
            .compactMap { $0 }
            .joined(separator: " • ")
            .nilIfEmpty ?? primaryLine
    }

    var websiteHost: String? {
        guard let rawWebsite = website?.nilIfEmpty else { return nil }
        let value = rawWebsite.contains("://") ? rawWebsite : "https://\(rawWebsite)"
        return URL(string: value)?.host?.replacingOccurrences(of: "www.", with: "").nilIfEmpty ?? rawWebsite
    }

    var locationLine: String? {
        [city?.nilIfEmpty, region?.nilIfEmpty, countryCode?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfEmpty
    }

    var listGroupTitle: String {
        if let listName = listName?.nilIfEmpty {
            return listName
        }

        let location = [city?.nilIfEmpty, region?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfEmpty ?? "Imported leads"
        return "\(location) - \(sourceLabel) - \(createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    var listGroupId: String {
        listId?.nilIfEmpty ?? listGroupTitle.lowercased()
    }

    var hasExplicitListIdentity: Bool {
        listId?.nilIfEmpty != nil || listName?.nilIfEmpty != nil
    }

    /// A lead becomes a contact only after the backend links it to the canonical
    /// sales contact record. Legacy manually-created rows predate that link, so
    /// keep treating those unlisted records as contacts.
    var isContact: Bool {
        salesContactId?.nilIfEmpty != nil ||
            (!hasExplicitListIdentity && source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "manual")
    }

    var isUnconvertedListLead: Bool {
        hasExplicitListIdentity && !isContact
    }

    var wasCalled: Bool {
        (attemptCount ?? 0) > 0 || lastAttemptedAt != nil
    }

    var connectedByCall: Bool {
        guard let disposition = disposition?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return false }
        return ["interested", "connected", "appointment_set"].contains(disposition)
    }
}

private struct SalespersonLeadListResponse: Decodable {
    let leads: [SalespersonLeadMasterRow]
    let workspaceId: String?
}

private struct SalespersonLeadListGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let leads: [SalespersonLeadMasterRow]
    let createdAt: Date

    var count: Int { leads.count }

    var dialableCount: Int {
        leads.filter { $0.phone?.nilIfEmpty != nil }.count
    }

    var callsMade: Int {
        leads.reduce(into: 0) { total, lead in
            total += max(lead.attemptCount ?? 0, lead.lastAttemptedAt == nil ? 0 : 1)
        }
    }

    var attemptedLeadCount: Int {
        leads.filter(\.wasCalled).count
    }

    var connectedCount: Int {
        leads.filter(\.connectedByCall).count
    }

    var remainingToCall: Int {
        max(dialableCount - attemptedLeadCount, 0)
    }

    var completionFraction: Double {
        guard dialableCount > 0 else { return 0 }
        return min(Double(attemptedLeadCount) / Double(dialableCount), 1)
    }

    var connectionRate: Double {
        guard callsMade > 0 else { return 0 }
        return Double(connectedCount) / Double(callsMade)
    }

    var subtitle: String {
        let newest = createdAt.formatted(date: .abbreviated, time: .omitted)
        let source = leads.first?.sourceLabel ?? "Leads"
        return "\(count) leads • \(dialableCount) dialable • \(source) • \(newest)"
    }

    var locationLine: String? {
        let locations = leads
            .compactMap(\.locationLine)
            .filter { !$0.isEmpty }
        return locations.first
    }

    static func makeGroups(from leads: [SalespersonLeadMasterRow]) -> [SalespersonLeadListGroup] {
        let groups = Dictionary(grouping: leads.filter(\.isUnconvertedListLead)) { lead in
            lead.listGroupId
        }
        return groups.map { key, rows in
            let sortedRows = rows.sorted { $0.createdAt > $1.createdAt }
            return SalespersonLeadListGroup(
                id: key,
                title: sortedRows.first?.listGroupTitle ?? "Imported leads",
                leads: sortedRows,
                createdAt: sortedRows.map(\.createdAt).max() ?? .distantPast
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.title < rhs.title
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private struct SalespersonDiallerListGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let leads: [SalespersonDiallerLead]
    let createdAt: Date

    var count: Int { leads.count }
    var dialableCount: Int {
        leads.filter { !$0.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var subtitle: String {
        let newest = createdAt == .distantPast ? "No date" : createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(count) leads • \(dialableCount) dialable • \(newest)"
    }

    static func makeGroups(from leads: [SalespersonDiallerLead]) -> [SalespersonDiallerListGroup] {
        let listedLeads = leads.filter(\.isUnconvertedListLead)
        let fallbackLeads = leads.filter { !$0.hasExplicitListIdentity }
        let explicitGroups = Dictionary(grouping: listedLeads) { lead in
            lead.listGroupId
        }
        .map { key, rows in
            let sortedRows = rows.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            return SalespersonDiallerListGroup(
                id: key,
                title: sortedRows.first?.listGroupTitle ?? "Dialler queue",
                leads: sortedRows,
                createdAt: sortedRows.compactMap(\.createdAt).max() ?? .distantPast
            )
        }

        return (explicitGroups + makeScrapeMomentGroups(from: fallbackLeads))
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.title < rhs.title
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func makeScrapeMomentGroups(from leads: [SalespersonDiallerLead]) -> [SalespersonDiallerListGroup] {
        let sortedLeads = leads.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
        var batches: [[SalespersonDiallerLead]] = []

        for lead in sortedLeads {
            guard let createdAt = lead.createdAt else {
                if let index = batches.firstIndex(where: { $0.first?.createdAt == nil }) {
                    batches[index].append(lead)
                } else {
                    batches.append([lead])
                }
                continue
            }

            if let lastIndex = batches.indices.last,
               let previousDate = batches[lastIndex].compactMap(\.createdAt).min(),
               previousDate.timeIntervalSince(createdAt) <= 10 * 60 {
                batches[lastIndex].append(lead)
            } else {
                batches.append([lead])
            }
        }

        return batches.map { rows in
            let sortedRows = rows.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            let createdAt = sortedRows.compactMap(\.createdAt).max() ?? .distantPast
            let id = createdAt == .distantPast
                ? "wolfgrid-undated"
                : "wolfgrid-\(Self.batchKeyFormatter.string(from: createdAt))"
            let title = createdAt == .distantPast
                ? "WolfGrid"
                : "WolfGrid - \(createdAt.formatted(date: .abbreviated, time: .shortened))"
            return SalespersonDiallerListGroup(
                id: id,
                title: title,
                leads: sortedRows,
                createdAt: createdAt
            )
        }
    }

    private static let batchKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()
}

private struct ProspectMarket: Identifiable, Decodable, Equatable {
    let id: UUID
    let countryCode: String
    let region: String
    let city: String
    let label: String
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case region
        case city
        case label
        case priority
        case countryCode = "country_code"
    }
}

private struct ProspectIndustry: Identifiable, Decodable, Equatable {
    let id: UUID
    let name: String
    let slug: String
    let defaultTerms: [String]
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case priority
        case defaultTerms = "default_terms"
    }
}

private struct ProspectSearchRun: Identifiable, Decodable, Equatable {
    let id: UUID
    let marketId: UUID?
    let industryId: UUID?
    let city: String
    let region: String?
    let countryCode: String
    let industry: String
    let rawCount: Int
    let uniqueCount: Int
    let savedCount: Int
    let dialerCount: Int
    let status: String
    let completedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case city
        case region
        case industry
        case status
        case marketId = "market_id"
        case industryId = "industry_id"
        case countryCode = "country_code"
        case rawCount = "raw_count"
        case uniqueCount = "unique_count"
        case savedCount = "saved_count"
        case dialerCount = "dialer_count"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

private struct ProspectingOptionsResponse: Decodable {
    struct JobSignals: Decodable, Equatable {
        let configured: Bool?
        let provider: String?
    }

    let workspaceId: String?
    let markets: [ProspectMarket]
    let industries: [ProspectIndustry]
    let recentRuns: [ProspectSearchRun]
    let jobSignals: JobSignals?
}

private struct PlacesJobSignal: Decodable, Equatable {
    let source: String?
    let title: String?
    let url: String?
}

private struct PlacesLead: Identifiable, Decodable, Equatable {
    let placeId: String?
    let name: String
    let city: String?
    let industry: String?
    let phone: String?
    let website: String?
    let websiteDomain: String?
    let formattedAddress: String?
    let googleMapsUrl: String?
    let rating: Double?
    let userRatingCount: Int?
    let primaryType: String?
    let businessStatus: String?
    let confidenceScore: Int
    let leadCategory: String?
    let evidenceSummary: String?
    let query: String?
    let jobSignals: [PlacesJobSignal]?

    var id: String {
        placeId ?? [name, formattedAddress ?? "", phone ?? ""].joined(separator: "|")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        placeId = try container.decodeValue(String.self, forAny: ["place_id", "placeId"])
        name = try container.decodeValue(String.self, forAny: ["name"], default: "Unnamed lead")
        city = try container.decodeValue(String.self, forAny: ["city"])
        industry = try container.decodeValue(String.self, forAny: ["industry"])
        phone = try container.decodeValue(String.self, forAny: ["phone"])
        website = try container.decodeValue(String.self, forAny: ["website"])
        websiteDomain = try container.decodeValue(String.self, forAny: ["website_domain", "websiteDomain"])
        formattedAddress = try container.decodeValue(String.self, forAny: ["formatted_address", "formattedAddress", "address"])
        googleMapsUrl = try container.decodeValue(String.self, forAny: ["google_maps_url", "googleMapsUrl"])
        rating = try container.decodeValue(Double.self, forAny: ["rating"])
        userRatingCount = try container.decodeValue(Int.self, forAny: ["user_rating_count", "userRatingCount"])
        primaryType = try container.decodeValue(String.self, forAny: ["primary_type", "primaryType"])
        businessStatus = try container.decodeValue(String.self, forAny: ["business_status", "businessStatus"])
        confidenceScore = try container.decodeValue(Int.self, forAny: ["confidence_score", "confidenceScore"], default: 0)
        leadCategory = try container.decodeValue(String.self, forAny: ["lead_category", "leadCategory"])
        evidenceSummary = try container.decodeValue(String.self, forAny: ["evidence_summary", "evidenceSummary"])
        query = try container.decodeValue(String.self, forAny: ["query"])
        jobSignals = try container.decodeValue([PlacesJobSignal].self, forAny: ["job_signals", "jobSignals"])
    }
}

private struct SavedScraperList: Decodable, Equatable {
    let listId: String?
    let listName: String
    let contactIds: [String]
    let contactCount: Int
    let dialerLeadIds: [String]
    let dialerImportedCount: Int
    let dialerSkippedCount: Int
    let masterAddedCount: Int
    let masterSkippedCount: Int
    let warning: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        listId = try container.decodeValue(String.self, forAny: ["list_id", "listId"])
        listName = try container.decodeValue(String.self, forAny: ["list_name", "listName"], default: "Places leads")
        contactIds = try container.decodeValue([String].self, forAny: ["contact_ids", "contactIds"], default: [])
        contactCount = try container.decodeValue(Int.self, forAny: ["contact_count", "contactCount"], default: contactIds.count)
        dialerLeadIds = try container.decodeValue([String].self, forAny: ["dialer_lead_ids", "dialerLeadIds"], default: [])
        dialerImportedCount = try container.decodeValue(Int.self, forAny: ["dialer_imported_count", "dialerImportedCount"], default: 0)
        dialerSkippedCount = try container.decodeValue(Int.self, forAny: ["dialer_skipped_count", "dialerSkippedCount"], default: 0)
        masterAddedCount = try container.decodeValue(Int.self, forAny: ["master_added_count", "masterAddedCount"], default: 0)
        masterSkippedCount = try container.decodeValue(Int.self, forAny: ["master_skipped_count", "masterSkippedCount"], default: 0)
        warning = try container.decodeValue(String.self, forAny: ["warning"])
    }
}

private struct PlacesLeadSearchResponse: Decodable, Equatable {
    let ok: Bool?
    let startedAt: Date?
    let completedAt: Date?
    let queryCount: Int?
    let rawResultCount: Int?
    let uniqueResultCount: Int?
    let jobSignalCount: Int?
    let jobSignalRawCount: Int?
    let jobSignalProvider: String?
    let leadSource: String?
    let prospects: [PlacesLead]
    let savedList: SavedScraperList?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        ok = try container.decodeValue(Bool.self, forAny: ["ok"])
        startedAt = try container.decodeValue(Date.self, forAny: ["started_at", "startedAt"])
        completedAt = try container.decodeValue(Date.self, forAny: ["completed_at", "completedAt"])
        queryCount = try container.decodeValue(Int.self, forAny: ["query_count", "queryCount"])
        rawResultCount = try container.decodeValue(Int.self, forAny: ["raw_result_count", "rawResultCount", "raw_count"])
        uniqueResultCount = try container.decodeValue(Int.self, forAny: ["unique_result_count", "uniqueResultCount", "unique_count"])
        jobSignalCount = try container.decodeValue(Int.self, forAny: ["job_signal_count", "jobSignalCount"])
        jobSignalRawCount = try container.decodeValue(Int.self, forAny: ["job_signal_raw_count", "jobSignalRawCount"])
        jobSignalProvider = try container.decodeValue(String.self, forAny: ["job_signal_provider", "jobSignalProvider"])
        leadSource = try container.decodeValue(String.self, forAny: ["lead_source", "leadSource"])
        prospects = try container.decodeValue([PlacesLead].self, forAny: ["prospects", "leads", "items"], default: [])
        savedList = try container.decodeValue(SavedScraperList.self, forAny: ["saved_list", "savedList"])
    }
}

private struct CitySuggestion: Identifiable, Equatable {
    let id: String
    let city: String
    let region: String
    let countryCode: String
    let label: String
}

private struct ScraperIndustryOption: Identifiable, Equatable {
    let id: String
    let name: String
    let defaultTerms: [String]
}

private struct SalespersonPerformanceResponse: Decodable, Equatable {
    struct Range: Decodable, Equatable {
        let start: Date
        let end: Date
    }

    struct Salesperson: Decodable, Equatable {
        let id: UUID?
        let fullName: String
        let email: String
        let referralCode: String?
        let workspaceId: String?
        let trackedLink: String?
    }

    struct Outreach: Decodable, Equatable {
        let calls: Int
        let answers: Int
        let messages: Int
        let outboundMessages: Int
        let inboundMessages: Int
        let emails: Int
        let demosSent: Int?
        let directMessages: Int
        let posts: Int
        let meetingsBooked: Int
        let meetingsHeld: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
            calls = try container.decodeValue(Int.self, forAny: ["calls"], default: 0)
            answers = try container.decodeValue(Int.self, forAny: ["answers"], default: 0)
            messages = try container.decodeValue(Int.self, forAny: ["messages"], default: 0)
            outboundMessages = try container.decodeValue(
                Int.self,
                forAny: ["outboundMessages", "outbound_messages"],
                default: 0
            )
            inboundMessages = try container.decodeValue(
                Int.self,
                forAny: ["inboundMessages", "inbound_messages"],
                default: 0
            )
            emails = try container.decodeValue(Int.self, forAny: ["emails"], default: 0)
            demosSent = try container.decodeValue(Int.self, forAny: ["demosSent", "demos_sent"])
            directMessages = try container.decodeValue(
                Int.self,
                forAny: ["directMessages", "direct_messages", "dms", "dm"],
                default: 0
            )
            posts = try container.decodeValue(
                Int.self,
                forAny: ["posts", "socialPosts", "social_posts"],
                default: 0
            )
            meetingsBooked = try container.decodeValue(
                Int.self,
                forAny: ["meetingsBooked", "meetings_booked", "meetings"],
                default: 0
            )
            meetingsHeld = try container.decodeValue(
                Int.self,
                forAny: ["meetingsHeld", "meetings_held"],
                default: 0
            )
        }
    }

    struct Links: Decodable, Equatable {
        let opens: Int
        let signups: Int
    }

    struct Revenue: Decodable, Equatable {
        let payingUsers: Int
        let paidTeams: Int
        let mrrByCurrency: [String: Int]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
            payingUsers = try container.decodeValue(
                Int.self,
                forAny: ["payingUsers", "paying_users"],
                default: 0
            )
            paidTeams = try container.decodeValue(
                Int.self,
                forAny: ["paidTeams", "paid_teams"],
                default: payingUsers
            )
            mrrByCurrency = try container.decodeValue(
                [String: Int].self,
                forAny: ["mrrByCurrency", "mrr_by_currency"],
                default: [:]
            )
        }
    }

    struct MetricComparison: Decodable, Equatable {
        let previousValue: Int?
        let percentageChange: Double?
    }

    struct Comparisons: Decodable, Equatable {
        struct Outreach: Decodable, Equatable {
            let calls: MetricComparison
            let answers: MetricComparison
            let messages: MetricComparison
            let emails: MetricComparison
            let directMessages: MetricComparison
            let posts: MetricComparison
            let meetingsBooked: MetricComparison
            let meetingsHeld: MetricComparison
        }

        struct Links: Decodable, Equatable {
            let signups: MetricComparison
        }

        struct Revenue: Decodable, Equatable {
            let paidTeams: MetricComparison
            let mrrByCurrency: [String: MetricComparison]
        }

        let outreach: Outreach
        let links: Links
        let revenue: Revenue
    }

    struct DemoVideo: Decodable, Equatable {
        let sessions: Int
        let pageViews: Int
        let videoStarts: Int
        let playWithSound: Int
        let progress25: Int
        let progress50: Int
        let progress75: Int
        let completions: Int
        let ctaShown: Int
        let startTrialClicks: Int
        let founderCallClicks: Int
        let exits: Int
        let averageWatchSeconds: Double
        let maxWatchSeconds: Double
    }

    let period: String
    let range: Range
    let salesperson: Salesperson
    let outreach: Outreach
    let links: Links
    let revenue: Revenue
    let demoVideo: DemoVideo
    let comparisons: Comparisons?
}

private actor SalespersonMobileAPI {
    static let shared = SalespersonMobileAPI()

    private static let defaultRequestTimeout: TimeInterval = 12
    private static let leadGenerationRequestTimeout: TimeInterval = 120

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.flyrInternet.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.flyrInternetNoFractional.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateFormatter.flyrInternet.string(from: date))
        }
        return encoder
    }()

    private func workspaceId() async throws -> UUID {
        if let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) {
            return workspaceId
        }

        await refreshWorkspaceContext()

        guard let refreshedWorkspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) else {
            throw SalespersonAPIError.missingWorkspace
        }
        return refreshedWorkspaceId
    }

    private func refreshWorkspaceContext() async {
        do {
            let state = try await AccessAPI.shared.getState()
            await MainActor.run {
                WorkspaceContext.shared.update(from: state)
            }
        } catch {
            #if DEBUG
            print("⚠️ [SalespersonMobileAPI] workspace refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func currentUserContext() async throws -> (userId: UUID, workspaceId: UUID?) {
        let context = await MainActor.run {
            (AuthManager.shared.user?.id, WorkspaceContext.shared.workspaceId)
        }
        guard let userId = context.0 else {
            throw SalespersonAPIError.status(401, "Sign in again to load your data.")
        }
        return (userId, context.1)
    }

    private func fetchExistingContacts() async throws -> [Contact] {
        let context = try await currentUserContext()
        return try await SalespersonContactsService.shared.fetchContacts(
            userID: context.userId,
            workspaceId: context.workspaceId
        )
    }

    private func diallerLead(from contact: Contact) -> SalespersonDiallerLead? {
        guard let phone = contact.phone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return SalespersonDiallerLead(
            id: contact.id,
            name: contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? contact.address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? phone,
            phone: phone,
            company: contact.company?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            email: contact.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            website: nil,
            websiteDomain: nil,
            listId: nil,
            listName: nil,
            latestCallRecording: nil,
            isStarred: false,
            disposition: contact.status == .new ? nil : contact.status.displayName,
            notes: contact.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            calledAt: contact.lastContacted,
            createdAt: contact.createdAt,
            address: contact.address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            lastContactedAt: contact.lastContacted
        )
    }

    private func request(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        timeoutInterval: TimeInterval = SalespersonMobileAPI.defaultRequestTimeout
    ) async throws -> URLRequest {
        var components = URLComponents(url: Config.backendAPIURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SalespersonAPIError.badURL }

        let session = try await SupabaseManager.shared.client.auth.session
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let session = try await SupabaseManager.shared.client.auth.session
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(session.accessToken)" else {
            throw CancellationError()
        }
        let userID = session.user.id
        let workspaceID = await WorkspaceContext.shared.workspaceId
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (try? await SupabaseManager.shared.client.auth.session.user.id) == userID,
              (await WorkspaceContext.shared.workspaceId) == workspaceID else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else {
            throw SalespersonAPIError.status(0, "No response from server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode([String: String].self, from: data)["error"])
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            if http.statusCode == 403,
               message.localizedCaseInsensitiveContains("workspace"),
               let retryRequest = await requestByRefreshingWorkspaceId(request) {
                guard (try? await SupabaseManager.shared.client.auth.session.user.id) == userID else { throw CancellationError() }
                let retryWorkspaceID = await WorkspaceContext.shared.workspaceId
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
                guard (try? await SupabaseManager.shared.client.auth.session.user.id) == userID,
                      (await WorkspaceContext.shared.workspaceId) == retryWorkspaceID else { throw CancellationError() }
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw SalespersonAPIError.status(0, "No response from server.")
                }
                guard (200...299).contains(retryHTTP.statusCode) else {
                    let retryMessage = (try? decoder.decode([String: String].self, from: retryData)["error"])
                        ?? HTTPURLResponse.localizedString(forStatusCode: retryHTTP.statusCode)
                    throw SalespersonAPIError.status(retryHTTP.statusCode, retryMessage)
                }
                return retryData
            }
            throw SalespersonAPIError.status(http.statusCode, message)
        }
        return data
    }

    private func requestByRefreshingWorkspaceId(_ request: URLRequest) async -> URLRequest? {
        guard let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "workspaceId" }) == true else {
            return nil
        }

        await refreshWorkspaceContext()

        guard let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) else {
            return nil
        }

        let requestedWorkspaceId = components.queryItems?
            .first(where: { $0.name == "workspaceId" })?
            .value
        if requestedWorkspaceId?.lowercased() == workspaceId.uuidString.lowercased() {
            // The cached workspace was rejected and access-state refresh returned the
            // same value. Omit the hint so the authenticated backend can safely resolve
            // the user's primary accessible workspace instead of repeating the 403.
            components.queryItems = components.queryItems?.filter { $0.name != "workspaceId" }
        } else {
            components.queryItems = components.queryItems?.map { item in
                item.name == "workspaceId"
                    ? URLQueryItem(name: item.name, value: workspaceId.uuidString)
                    : item
            }
        }
        guard let retryURL = components.url, retryURL != url else { return nil }

        var retry = request
        retry.url = retryURL
        return retry
    }

    private func isDiallerBackendUnavailable(_ error: Error) -> Bool {
        guard let apiError = error as? SalespersonAPIError,
              case SalespersonAPIError.status(let status, let message) = apiError else {
            return false
        }
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == 404 ||
            status == 501 ||
            (status == 500 && normalizedMessage == "internal server error") ||
            normalizedMessage.contains("dialler queue item") ||
            normalizedMessage.contains("dialer queue item") ||
            normalizedMessage.contains("dialer lead storage") ||
            normalizedMessage.contains("dialler lead storage")
    }

    private func isMissingMessagingSenderError(_ error: Error) -> Bool {
        guard let apiError = error as? SalespersonAPIError,
              case SalespersonAPIError.status(_, let message) = apiError else {
            return false
        }

        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedMessage.contains("'from' address") ||
            normalizedMessage.contains("from address") ||
            normalizedMessage.contains("valid number associated with the sending messaging profile")
    }

    private func contactBackedLead(
        id: UUID,
        disposition: String? = nil,
        notes: String? = nil,
        email: String? = nil,
        followUpAt: Date? = nil,
        markContacted: Bool = true
    ) async throws -> SalespersonDiallerLead {
        let context = try await currentUserContext()
        let contacts = try await SalespersonContactsService.shared.fetchContacts(
            userID: context.userId,
            workspaceId: context.workspaceId
        )
        guard var contact = contacts.first(where: { $0.id == id }) else {
            throw SalespersonAPIError.status(404, "Dialler lead was not found.")
        }

        if let disposition {
            contact.status = ContactStatus.normalized(disposition)
        }
        if let notes {
            contact.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let email {
            contact.email = email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if let followUpAt {
            contact.followUpAt = followUpAt
            contact.reminderDate = followUpAt
        }
        if markContacted {
            contact.lastContacted = Date()
        }
        contact.updatedAt = Date()

        let updated = try await SalespersonContactsService.shared.updateContact(
            contact,
            userID: context.userId,
            workspaceId: context.workspaceId,
            syncToCRM: false
        )
        guard let lead = diallerLead(from: updated) else {
            throw SalespersonAPIError.status(400, "Dialler lead needs a phone number.")
        }
        return lead
    }

    private func download(for request: URLRequest, fallbackName: String) async throws -> URL {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SalespersonAPIError.status(0, "No response from server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode([String: String].self, from: data)["error"])
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SalespersonAPIError.status(http.statusCode, message)
        }

        let fileName = Self.fileName(from: http.value(forHTTPHeaderField: "Content-Disposition"))
            ?? fallbackName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private static func fileName(from disposition: String?) -> String? {
        guard let disposition else { return nil }
        let marker = "filename=\""
        guard let range = disposition.range(of: marker) else { return nil }
        let suffix = disposition[range.upperBound...]
        guard let end = suffix.firstIndex(of: "\"") else { return nil }
        return String(suffix[..<end]).nilIfEmpty
    }

    func fetchDiallerLeads() async throws -> [SalespersonDiallerLead] {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/dialer/leads",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        )
        do {
            return try decoder.decode(SalespersonDiallerLeadsResponse.self, from: try await data(for: request)).leads
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            return try await fetchExistingContacts()
                .compactMap(diallerLead(from:))
                .filter { $0.disposition == nil }
        }
    }

    func fetchDiallerSmartLists() async throws -> [SalespersonDiallerSmartListOption] {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/dialer/smart-list-imports",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        )
        do {
            let lists = try decoder.decode(
                SalespersonDiallerSmartListsResponse.self,
                from: try await data(for: request)
            ).lists
            if !lists.isEmpty { return lists }
        } catch SalespersonAPIError.status(404, _) {
            // Fall through to the salesperson's created lead lists.
        }

        let createdLeads = try await fetchSalespersonLeads().filter {
            $0.listId?.nilIfEmpty != nil || $0.listName?.nilIfEmpty != nil
        }
        return SalespersonLeadListGroup.makeGroups(from: createdLeads).map { list in
            let dialableLeads = list.leads.compactMap { lead -> SalespersonDiallerImportLead? in
                guard let phone = lead.phone?.nilIfEmpty else { return nil }
                return SalespersonDiallerImportLead(
                    name: lead.name,
                    phone: phone,
                    company: lead.company,
                    email: lead.email,
                    listId: list.id,
                    listName: list.title
                )
            }
            return SalespersonDiallerSmartListOption(
                id: list.id,
                name: list.title,
                description: list.subtitle,
                count: list.count,
                dialableCount: dialableLeads.count,
                leads: dialableLeads
            )
        }
    }

    func createDiallerSmartList(name: String) async throws -> SalespersonDiallerSmartListOption {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let name: String
        }
        let request = try await request(
            path: "api/dialer/smart-list-imports",
            method: "POST",
            body: try encoder.encode(Payload(
                workspaceId: workspaceId.uuidString,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        )
        return try decoder.decode(
            SalespersonDiallerSmartListCreateResponse.self,
            from: try await data(for: request)
        ).list
    }

    func fetchCompanyResearch(leadId: UUID) async throws -> SalespersonCompanyResearchResponse {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/sales/company-research",
            queryItems: [
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "leadId", value: leadId.uuidString)
            ]
        )
        return try decoder.decode(SalespersonCompanyResearchResponse.self, from: try await data(for: request))
    }

    func startCompanyResearch(leadId: UUID) async throws {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable { let leadId: String }
        let request = try await request(
            path: "api/sales/company-research",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)],
            method: "POST",
            body: try encoder.encode(Payload(leadId: leadId.uuidString))
        )
        _ = try await data(for: request)
    }

    func startCompanyResearch(listId: String, refreshAll: Bool) async throws -> SalespersonCompanyResearchBatchResponse {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable { let listId: String; let refreshAll: Bool }
        let request = try await request(
            path: "api/sales/company-research",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)],
            method: "POST",
            body: try encoder.encode(Payload(listId: listId, refreshAll: refreshAll))
        )
        return try decoder.decode(SalespersonCompanyResearchBatchResponse.self, from: try await data(for: request))
    }

    func fetchCompanyResearch(batchId: String) async throws -> SalespersonCompanyResearchBatchResponse {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/sales/company-research",
            queryItems: [
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "batchId", value: batchId)
            ]
        )
        return try decoder.decode(SalespersonCompanyResearchBatchResponse.self, from: try await data(for: request))
    }

    func retryCompanyResearch(batchId: String) async throws {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable { let retryBatchId: String }
        let request = try await request(
            path: "api/sales/company-research",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)],
            method: "POST",
            body: try encoder.encode(Payload(retryBatchId: batchId))
        )
        _ = try await data(for: request)
    }

    func importDiallerLeads(_ leads: [SalespersonDiallerImportLead]) async throws -> SalespersonDiallerImportResponse {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let phoneMarket: String
            let leads: [SalespersonDiallerImportLead]
        }
        let payload = Payload(workspaceId: workspaceId.uuidString, phoneMarket: "CA", leads: leads)
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads", method: "POST", body: body)
        return try decoder.decode(SalespersonDiallerImportResponse.self, from: try await data(for: request))
    }

    func fetchDiallerRecordings(starredOnly: Bool = false) async throws -> [SalespersonDiallerRecordingGroup] {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/dialer/recordings",
            queryItems: [
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "starred", value: starredOnly ? "true" : "false")
            ]
        )
        do {
            return try decoder.decode(SalespersonDiallerRecordingsResponse.self, from: try await data(for: request)).groups
        } catch SalespersonAPIError.status(404, _) {
            return []
        }
    }

    func downloadDiallerRecording(downloadUrl: String, fallbackName: String) async throws -> URL {
        let url: URL
        if let absolute = URL(string: downloadUrl), absolute.scheme != nil {
            url = absolute
        } else if let resolved = URL(string: downloadUrl, relativeTo: Config.backendAPIURL)?.absoluteURL {
            url = resolved
        } else {
            throw SalespersonAPIError.badURL
        }

        let session = try await SupabaseManager.shared.client.auth.session
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return try await download(for: request, fallbackName: fallbackName)
    }

    func fetchSalespersonLeads() async throws -> [SalespersonLeadMasterRow] {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/salesperson/leads",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        )
        return try decoder.decode(
            SalespersonLeadListResponse.self,
            from: try await data(for: request)
        ).leads
    }

    func createSalespersonContact(
        firstName: String,
        lastName: String,
        company: String,
        phone: String,
        email: String,
        address: String,
        notes: String,
        photoData: Data?
    ) async throws -> SalespersonLeadMasterRow {
        let context = try await currentUserContext()
        let resolvedWorkspaceId: UUID
        if let workspaceId = context.workspaceId {
            resolvedWorkspaceId = workspaceId
        } else {
            resolvedWorkspaceId = try await workspaceId()
        }
        let normalizedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [normalizedFirstName, normalizedLastName].joined(separator: " ")
        let leadId = UUID()
        let photoPath: String?
        if let photoData {
            let path = "\(context.userId.uuidString.lowercased())/\(leadId.uuidString.lowercased()).jpg"
            _ = try await SupabaseManager.shared.client.storage
                .from("contact-photos")
                .upload(
                    path,
                    data: photoData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            photoPath = path
        } else {
            photoPath = nil
        }

        let payload = SalespersonContactCreatePayload(
            workspaceId: resolvedWorkspaceId.uuidString,
            name: fullName,
            company: company.nilIfEmpty,
            phone: phone.nilIfEmpty,
            email: email.nilIfEmpty?.lowercased(),
            address: address.nilIfEmpty,
            notes: notes.nilIfEmpty,
            firstName: normalizedFirstName,
            lastName: normalizedLastName,
            photoPath: photoPath
        )

        do {
            struct Response: Decodable {
                let lead: SalespersonLeadMasterRow
                let created: Bool?
            }
            let request = try await request(
                path: "api/salesperson/leads",
                method: "POST",
                body: try encoder.encode(payload)
            )
            let response = try decoder.decode(Response.self, from: try await data(for: request))
            if let photoPath, response.lead.metadata?.photoPath != photoPath {
                _ = try? await SupabaseManager.shared.client.storage
                    .from("contact-photos")
                    .remove(paths: [photoPath])
            }
            return response.lead
        } catch {
            if let photoPath {
                _ = try? await SupabaseManager.shared.client.storage
                    .from("contact-photos")
                    .remove(paths: [photoPath])
            }
            throw error
        }
    }

    func createSalespersonContact(from lead: SalespersonLeadMasterRow) async throws -> SalespersonLeadMasterRow {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let leadId: String
        }
        struct Response: Decodable {
            let lead: SalespersonLeadMasterRow
            let created: Bool?
        }
        let request = try await request(
            path: "api/salesperson/leads",
            method: "POST",
            body: try encoder.encode(Payload(
                workspaceId: workspaceId.uuidString,
                leadId: lead.id.uuidString
            ))
        )
        return try decoder.decode(Response.self, from: try await data(for: request)).lead
    }

    func updateSalespersonLead(
        id: UUID,
        name: String,
        company: String,
        phone: String,
        email: String,
        notes: String
    ) async throws -> SalespersonLeadMasterRow {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let name: String
            let company: String
            let phone: String
            let email: String
            let notes: String
        }
        struct Response: Decodable {
            let lead: SalespersonLeadMasterRow
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            name: name,
            company: company,
            phone: phone,
            email: email,
            notes: notes
        )
        let request = try await request(
            path: "api/salesperson/leads/\(id.uuidString)",
            method: "PATCH",
            body: try encoder.encode(payload)
        )
        return try decoder.decode(Response.self, from: try await data(for: request)).lead
    }

    func pushSalespersonLeadToCRM(
        provider: IntegrationProvider,
        lead: SalespersonLeadMasterRow,
        name: String,
        phone: String,
        email: String,
        notes: String
    ) async throws {
        guard [.fub, .boldtrail, .hubspot].contains(provider) else {
            throw SalespersonAPIError.status(400, "This CRM does not support direct contact push yet.")
        }
        let nameParts = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1)
            .map(String.init)
        let payload: [String: AnyCodable] = [
            "id": AnyCodable(lead.id.uuidString),
            "name": AnyCodable(name),
            "company": AnyCodable(lead.company as Any),
            "firstName": AnyCodable(nameParts.first as Any),
            "lastName": AnyCodable((nameParts.count > 1 ? nameParts[1] : nil) as Any),
            "phone": AnyCodable(phone.nilIfEmpty as Any),
            "email": AnyCodable(email.nilIfEmpty as Any),
            "address": AnyCodable((lead.address?.nilIfEmpty ?? lead.locationLine) as Any),
            "message": AnyCodable(notes.nilIfEmpty as Any),
            "notes": AnyCodable(notes.nilIfEmpty as Any),
            "source": AnyCodable(lead.sourceLabel),
            "createdAt": AnyCodable(ISO8601DateFormatter.flyrInternet.string(from: lead.createdAt)),
        ]
        let request = try await request(
            path: "api/integrations/\(provider.rawValue)/push-lead",
            method: "POST",
            body: try encoder.encode(payload)
        )
        _ = try await data(for: request)
    }

    func fetchProspectingOptions() async throws -> ProspectingOptionsResponse {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/prospecting/options",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        )
        return try decoder.decode(ProspectingOptionsResponse.self, from: try await data(for: request))
    }

    func fetchSalespersonPerformance(period: String = "monthly") async throws -> SalespersonPerformanceResponse {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/salesperson/performance",
            queryItems: [
                URLQueryItem(name: "period", value: period),
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
            ]
        )
        return try decoder.decode(SalespersonPerformanceResponse.self, from: try await data(for: request))
    }

    func searchPlacesLeads(
        city: String,
        industry: String,
        countryCode: String,
        region: String?,
        relatedTerms: [String],
        marketId: UUID?,
        industryId: UUID?,
        leadIntent: String,
        listName: String?
    ) async throws -> PlacesLeadSearchResponse {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let city: String
            let industry: String
            let countryCode: String
            let region: String?
            let workspaceId: String
            let relatedTerms: [String]
            let pageSize: Int
            let marketId: String?
            let industryId: String?
            let leadSource: String
            let leadIntent: String
            let listName: String?
        }
        let payload = Payload(
            city: city,
            industry: industry,
            countryCode: countryCode,
            region: region?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            workspaceId: workspaceId.uuidString,
            relatedTerms: relatedTerms,
            pageSize: 20,
            marketId: marketId?.uuidString,
            industryId: industryId?.uuidString,
            leadSource: "places",
            leadIntent: leadIntent,
            listName: listName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/salesperson/google-places",
            method: "POST",
            body: body,
            timeoutInterval: Self.leadGenerationRequestTimeout
        )
        return try decoder.decode(PlacesLeadSearchResponse.self, from: try await data(for: request))
    }

    func updateDiallerLead(
        id: UUID,
        disposition: String,
        notes: String?,
        email: String? = nil,
        followUpName: String? = nil,
        followUpAt: Date? = nil,
        createNotification: Bool = false
    ) async throws -> (SalespersonDiallerLead, String?) {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let id: String
            let disposition: String
            let notes: String?
            let email: String?
            let followUpName: String?
            let followUpAt: Date?
            let createNotification: Bool
        }
        struct Response: Decodable {
            let lead: SalespersonDiallerLead
            let warning: String?
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            id: id.uuidString,
            disposition: disposition,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            followUpName: followUpName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            followUpAt: followUpAt,
            createNotification: createNotification
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads", method: "PATCH", body: body)
        do {
            let response = try decoder.decode(Response.self, from: try await data(for: request))
            return (response.lead, response.warning)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            let lead = try await contactBackedLead(
                id: id,
                disposition: disposition,
                notes: notes,
                email: email,
                followUpAt: followUpAt
            )
            return (lead, createNotification ? "Follow-up saved locally." : nil)
        }
    }

    func toggleDiallerLeadStar(id: UUID, isStarred: Bool) async throws -> SalespersonDiallerLead {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let id: String
            let isStarred: Bool
        }
        struct Response: Decodable {
            let lead: SalespersonDiallerLead
        }
        let payload = Payload(workspaceId: workspaceId.uuidString, id: id.uuidString, isStarred: isStarred)
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads", method: "PATCH", body: body)
        do {
            return try decoder.decode(Response.self, from: try await data(for: request)).lead
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            let context = try await currentUserContext()
            let contacts = try await SalespersonContactsService.shared.fetchContacts(
                userID: context.userId,
                workspaceId: context.workspaceId
            )
            guard var lead = contacts.first(where: { $0.id == id }).flatMap(diallerLead(from:)) else {
                throw SalespersonAPIError.status(404, "Dialler lead was not found.")
            }
            lead.isStarred = isStarred
            return lead
        }
    }

    func removeDiallerLead(id: UUID) async throws {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let id: String
        }
        let payload = Payload(workspaceId: workspaceId.uuidString, id: id.uuidString)
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads", method: "DELETE", body: body)
        do {
            _ = try await data(for: request)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
        }
    }

    func startDiallerCall(lead: SalespersonDiallerLead, doubleDial: Bool = false) async throws -> SalespersonDiallerCall {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let leadId: String
            let phone: String
            let tabId: String
            let doubleDial: Bool
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            leadId: lead.id.uuidString,
            phone: lead.phone,
            tabId: "ios",
            doubleDial: doubleDial
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads/call", method: "POST", body: body)
        do {
            return try decoder.decode(SalespersonDiallerCallResponse.self, from: try await data(for: request)).call
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            let callId = UUID()
            return SalespersonDiallerCall(
                id: callId,
                callRequestId: callId.uuidString,
                toNumber: lead.phone,
                fromNumber: nil,
                status: "started",
                disposition: nil,
                statusPayload: nil
            )
        }
    }

    func startManualDiallerCall(phone: String) async throws -> SalespersonDiallerCall {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let phone: String
            let label: String
            let tabId: String
        }
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            phone: trimmedPhone,
            label: trimmedPhone,
            tabId: "ios"
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads/call", method: "POST", body: body)
        do {
            return try decoder.decode(SalespersonDiallerCallResponse.self, from: try await data(for: request)).call
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            let callId = UUID()
            return SalespersonDiallerCall(
                id: callId,
                callRequestId: callId.uuidString,
                toNumber: trimmedPhone,
                fromNumber: nil,
                status: "started",
                disposition: nil,
                statusPayload: nil
            )
        }
    }

    func setCallContentSaved(callId: UUID, saved: Bool) async throws -> SalespersonDiallerCall {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let contentSaved: Bool
        }
        let body = try encoder.encode(Payload(workspaceId: workspaceId.uuidString, contentSaved: saved))
        let request = try await request(
            path: "api/dialer/calls/\(callId.uuidString)",
            method: "PATCH",
            body: body
        )
        return try decoder.decode(SalespersonDiallerCallResponse.self, from: try await data(for: request)).call
    }

    func saveCallDisposition(callId: UUID, disposition: String, note: String?) async throws {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let disposition: String
            let note: String?
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            disposition: disposition,
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/calls/\(callId.uuidString)/disposition",
            method: "POST",
            body: body
        )
        do {
            _ = try await data(for: request)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
        }
    }

    func dropVoicemail(callId: UUID) async throws {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
        }
        let payload = Payload(workspaceId: workspaceId.uuidString)
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/calls/\(callId.uuidString)/voicemail-drop",
            method: "POST",
            body: body
        )
        do {
            _ = try await data(for: request)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
        }
    }

    func sendTextDrop(callId: UUID, body messageBody: String) async throws {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let body: String
        }
        let payload = Payload(workspaceId: workspaceId.uuidString, body: messageBody)
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/calls/\(callId.uuidString)/sms",
            method: "POST",
            body: body
        )
        do {
            _ = try await data(for: request)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
        }
    }

    func sendLeadText(lead: SalespersonDiallerLead, body messageBody: String) async throws -> String? {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let body: String
            let phone: String
            let name: String?
        }
        struct Response: Decodable {
            let warning: String?
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            body: messageBody,
            phone: lead.phone,
            name: lead.displayBusinessName
        )
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/leads/\(lead.id.uuidString)/sms",
            method: "POST",
            body: body
        )
        do {
            return try decoder.decode(Response.self, from: try await data(for: request)).warning
        } catch {
            if isMissingMessagingSenderError(error) {
                return "Text delivery needs a Telnyx sender number connected to the messaging profile."
            }
            guard isDiallerBackendUnavailable(error) else { throw error }
            return "Text delivery backend is not configured yet."
        }
    }

    func saveDiallerLeadContact(id: UUID, notes: String?, email: String?) async throws -> (SalespersonDiallerLead, String?) {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let id: String
            let notes: String?
            let email: String?
            let saveContact: Bool
        }
        struct Response: Decodable {
            let lead: SalespersonDiallerLead
            let warning: String?
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            id: id.uuidString,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            saveContact: true
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads", method: "PATCH", body: body)
        do {
            let response = try decoder.decode(Response.self, from: try await data(for: request))
            return (response.lead, response.warning)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            let lead = try await contactBackedLead(
                id: id,
                notes: notes,
                email: email,
                markContacted: false
            )
            return (lead, "Saved locally.")
        }
    }

    func fetchInbox(source: String = "all", status: String = "open", limit: Int = 75) async throws -> SalespersonInboxResponse {
        let workspaceId = try await workspaceId()
        var request = try await request(
            path: "api/inbox",
            queryItems: [
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try decoder.decode(SalespersonInboxResponse.self, from: try await data(for: request))
    }

    func fetchInboxThread(contactId: String, source: String = "all") async throws -> SalespersonInboxThread? {
        let workspaceId = try await workspaceId()
        var request = try await request(
            path: "api/inbox",
            queryItems: [
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "contactId", value: contactId),
                URLQueryItem(name: "limit", value: "1")
            ]
        )
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try decoder.decode(SalespersonInboxResponse.self, from: try await data(for: request)).threads?.first
    }

    func fetchCallLogs(for lead: SalespersonDiallerLead, offset: Int = 0) async throws -> [SalespersonCallLog] {
        let context = try await currentUserContext()
        guard let workspaceId = context.workspaceId else { throw SalespersonAPIError.missingWorkspace }
        var matches = ["sales_lead_id.eq.\(lead.id.uuidString)", "contact_id.eq.\(lead.id.uuidString)"]
        if let contactId = lead.salesContactId.flatMap(UUID.init(uuidString:)) {
            matches.append("contact_id.eq.\(contactId.uuidString)")
        }
        let digits = lead.phone.normalizedPhoneDigits
        if digits.count >= 8 {
            let number = !lead.phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") && digits.count == 10
                ? "+1\(digits)" : "+\(digits)"
            matches.append("and(direction.eq.outbound,to_number_e164.eq.\(number))")
            matches.append("and(direction.eq.inbound,from_number_e164.eq.\(number))")
        }
        let response = try await SupabaseManager.shared.client.from("dialer_calls")
            .select("id,direction,status,disposition,started_at,created_at,duration_seconds,disposition_note")
            .eq("workspace_id", value: workspaceId.uuidString)
            .eq("user_id", value: context.userId.uuidString)
            .or(matches.joined(separator: ","))
            .order("created_at", ascending: false)
            .order("id", ascending: false)
            .range(from: offset, to: offset + 24)
            .execute()
        let currentContext = try await currentUserContext()
        guard currentContext.userId == context.userId, currentContext.workspaceId == context.workspaceId else {
            throw CancellationError()
        }
        return try decoder.decode([SalespersonCallLog].self, from: response.data)
    }

    func uploadInboxAttachment(
        data: Data,
        fileName: String,
        mimeType: String
    ) async throws -> SalespersonInboxAttachment {
        let workspaceId = try await workspaceId()
        struct UploadRequest: Encodable {
            let workspaceId: String
            let fileName: String
            let mimeType: String
            let byteSize: Int
        }
        struct UploadReceipt: Decodable {
            let signedUrl: URL
            let storagePath: String
        }
        struct UploadEnvelope: Decodable { let upload: UploadReceipt }
        struct CompleteRequest: Encodable {
            let workspaceId: String
            let storagePath: String
            let fileName: String
            let mimeType: String
            let byteSize: Int
        }
        struct CompleteEnvelope: Decodable { let attachment: SalespersonInboxAttachment }

        let prepareBody = try encoder.encode(UploadRequest(
            workspaceId: workspaceId.uuidString,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: data.count
        ))
        let prepareRequest = try await request(
            path: "api/inbox/media/upload-url",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)],
            method: "POST",
            body: prepareBody
        )
        let prepared = try decoder.decode(UploadEnvelope.self, from: try await self.data(for: prepareRequest))

        var uploadRequest = URLRequest(url: prepared.upload.signedUrl)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.timeoutInterval = 120
        uploadRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue("false", forHTTPHeaderField: "x-upsert")
        let (_, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, from: data)
        guard let uploadHTTP = uploadResponse as? HTTPURLResponse,
              (200...299).contains(uploadHTTP.statusCode) else {
            throw SalespersonAPIError.status(0, "The photo or video could not be uploaded.")
        }

        let completeBody = try encoder.encode(CompleteRequest(
            workspaceId: workspaceId.uuidString,
            storagePath: prepared.upload.storagePath,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: data.count
        ))
        let completeRequest = try await request(
            path: "api/inbox/media/complete",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)],
            method: "POST",
            body: completeBody
        )
        return try decoder.decode(CompleteEnvelope.self, from: try await self.data(for: completeRequest)).attachment
    }

    func sendInboxText(
        leadId: String? = nil,
        contactId: String?,
        body messageBody: String,
        phone: String?,
        attachments: [SalespersonInboxAttachment] = []
    ) async throws -> String? {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let leadId: String?
            let body: String
            let phone: String?
            let contactId: String?
            let attachments: [SalespersonInboxAttachment]
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            leadId: leadId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            body: messageBody,
            phone: phone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            contactId: contactId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            attachments: attachments
        )
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/inbox",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)],
            method: "POST",
            body: body
        )
        return try decoder.decode(SalespersonInboxSendResponse.self, from: try await data(for: request)).warning
    }

    func sendInboxEmail(
        leadId: String? = nil,
        contactId: String?,
        to recipient: String,
        subject: String,
        body messageBody: String,
        useDemoTemplate: Bool = false
    ) async throws -> String? {
        let workspaceId = try await workspaceId()
        if useDemoTemplate, let leadId {
            struct DemoPayload: Encodable {
                let workspaceId: String
                let id: String
                let email: String
                let sendDemoEmail = true
            }
            struct DemoResponse: Decodable {
                let demoEmailSent: Bool
                let warning: String?
            }
            let request = try await request(
                path: "api/dialer/leads",
                method: "PATCH",
                body: try encoder.encode(DemoPayload(
                    workspaceId: workspaceId.uuidString,
                    id: leadId,
                    email: recipient.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            )
            let response = try decoder.decode(DemoResponse.self, from: try await data(for: request))
            guard response.demoEmailSent else {
                throw SalespersonAPIError.status(502, "The demo email could not be confirmed. Check your Inbox before retrying.")
            }
            return response.warning
        }
        struct Payload: Encodable {
            let workspaceId: String
            let channel: String
            let leadId: String?
            let contactId: String?
            let email: String
            let subject: String
            let body: String
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            channel: "email",
            leadId: leadId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            contactId: contactId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            email: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/inbox", method: "POST", body: body)
        return try decoder.decode(SalespersonInboxSendResponse.self, from: try await data(for: request)).warning
    }

    func updateInboxItem(id: String, status: String? = nil, read: Bool = true) async throws {
        let workspaceId = try await workspaceId()
        let payload: [String: AnyCodable] = [
            "workspaceId": AnyCodable(workspaceId.uuidString),
            "id": AnyCodable(id),
            "read": AnyCodable(read),
            "status": AnyCodable(status as Any)
        ]
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/inbox", method: "PATCH", body: body)
        _ = try await data(for: request)
    }
}

enum SalespersonEmailSender {
    static func send(
        leadId: String? = nil,
        contactId: String? = nil,
        to recipient: String,
        subject: String,
        body: String
    ) async throws -> String? {
        try await SalespersonMobileAPI.shared.sendInboxEmail(
            leadId: leadId,
            contactId: contactId,
            to: recipient,
            subject: subject,
            body: body
        )
    }
}

@MainActor
private final class SalespersonDiallerViewModel: ObservableObject {
    @Published var leads: [SalespersonDiallerLead] = []
    @Published var selectedListId: String?
    @Published var selectedLead: SalespersonDiallerLead?
    @Published var notes = ""
    @Published var email = ""
    @Published var textDropBody = ""
    @Published var activeCall: SalespersonDiallerCall?
    @Published var manualCallNumber: String?
    @Published var isCallSessionActive = false
    @Published private(set) var isDiallerSessionActive = false
    @Published private(set) var isDiallerSessionPaused = false
    @Published private(set) var diallerSessionStartedAt: Date?
    @Published var isLoading = false
    @Published var isPlacingCall = false
    @Published var isSaving = false
    @Published var isSavingContent = false
    @Published var isDroppingVoicemail = false
    @Published var isSendingTextDrop = false
    @Published var isSendingCallbackText = false
    @Published var isSendingEmail = false
    @Published var isOpeningTestLead = false
    @Published var smartLists: [SalespersonDiallerSmartListOption] = []
    @Published var recordings: [SalespersonDiallerRecordingGroup] = []
    @Published var isLoadingSmartLists = false
    @Published var isCreatingSmartList = false
    @Published var isImportingSmartList = false
    @Published var isLoadingRecordings = false
    @Published var isExportingRecording = false
    @Published var recordingExport: SalespersonRecordingExport?
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published private(set) var callsMade = 0
    @Published private(set) var callsAnswered = 0

    let quickNotes = [
        "Left voicemail",
        "Asked for pricing",
        "Call back later",
        "Not the decision maker",
        "Bad number"
    ]

    private let gabeTestPhone = "905-260-6688"
    private let gabeTestLeadId = UUID(uuidString: "90526066-8800-4000-9000-000000000001")!
    private let santanaTestPhone = "289-261-9598"
    private let santanaTestLeadId = UUID(uuidString: "28926195-9800-4000-9000-000000000002")!
    private let danielQaqishTestPhone = "289-927-1774"
    private let danielQaqishTestLeadId = UUID(uuidString: "28992717-7400-4000-9000-000000000003")!
    private let mainListId = "wolfgrid-main-list"
    private let testListId = "wolfgrid-test-list"
    private let testListName = "WolfGrid"
    private var emailAutosaveTask: Task<Void, Never>?
    private var answeredCallIds: Set<UUID> = []
    private var discardRequestedCallIds: Set<UUID> = []

    deinit {
        emailAutosaveTask?.cancel()
    }

    var leadLists: [SalespersonDiallerListGroup] {
        SalespersonDiallerListGroup.makeGroups(from: leads)
    }

    var mainList: SalespersonDiallerListGroup? {
        guard !leads.isEmpty else { return nil }
        let sortedLeads = leads.sorted {
            ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
        }
        return SalespersonDiallerListGroup(
            id: mainListId,
            title: "WolfGrid",
            leads: sortedLeads,
            createdAt: sortedLeads.compactMap(\.createdAt).max() ?? .distantPast
        )
    }

    var selectedList: SalespersonDiallerListGroup? {
        guard let selectedListId else { return nil }
        if selectedListId == mainListId {
            return mainList
        }
        return leadLists.first { $0.id == selectedListId }
    }

    var activeList: SalespersonDiallerListGroup? {
        selectedList
    }

    var visibleLeads: [SalespersonDiallerLead] {
        activeList?.leads ?? []
    }

    var shouldChooseStatus: Bool {
        selectedLead != nil && activeCall != nil && !isCallSessionActive
    }

    func load() async {
        emailAutosaveTask?.cancel()
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await SalespersonMobileAPI.shared.fetchDiallerLeads()
            if let selectedListId,
               !leadLists.contains(where: { $0.id == selectedListId }) {
                self.selectedListId = nil
            }
            selectedLead = selectedLead.flatMap { selected in
                leads.first(where: { $0.id == selected.id })
            }
            if let selectedLead {
                selectedListId = selectedListId ?? listId(containing: selectedLead) ?? leadLists.first?.id
                email = selectedLead.email ?? ""
                notes = selectedLead.notes ?? ""
                textDropBody = defaultTextDropBody(for: selectedLead)
            } else if let firstLead = leads.first(where: isDialableLead) ?? leads.first {
                select(firstLead)
            } else {
                notes = ""
                email = ""
                textDropBody = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addManualLead(
        name: String,
        company: String,
        phone: String,
        email: String,
        address: String,
        notes: String,
        isCompanyLead: Bool
    ) async -> Bool {
        guard !isSaving else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Add a person or company name."
            return false
        }
        guard trimmedPhone.filter(\.isNumber).count >= 8 else {
            errorMessage = "Enter a valid phone number."
            return false
        }

        let nameParts = trimmedName.split(separator: " ", maxSplits: 1).map(String.init)
        isSaving = true
        errorMessage = nil
        statusMessage = nil
        defer { isSaving = false }

        do {
            let created = try await SalespersonMobileAPI.shared.createSalespersonContact(
                firstName: nameParts.first ?? trimmedName,
                lastName: nameParts.count > 1 ? nameParts[1] : "",
                company: trimmedCompany,
                phone: trimmedPhone,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                photoData: nil
            )
            guard let createdPhone = created.phone?.nilIfEmpty else {
                errorMessage = "The lead was created, but it needs a phone number for the dialler."
                return false
            }

            let diallerLead = SalespersonDiallerLead(
                id: created.id,
                name: created.displayName,
                phone: createdPhone,
                company: created.company,
                email: created.email,
                website: created.website,
                websiteDomain: nil,
                listId: created.listId,
                listName: created.listName,
                latestCallRecording: nil,
                isStarred: false,
                disposition: created.disposition,
                notes: created.notes,
                calledAt: nil,
                createdAt: created.createdAt,
                address: created.address,
                city: created.city,
                region: created.region,
                countryCode: created.countryCode
            )
            replaceOrAppendLead(diallerLead)
            select(diallerLead)
            statusMessage = isCompanyLead
                ? "Added company lead \(trimmedCompany)."
                : trimmedCompany.isEmpty
                    ? "Added \(created.displayName)."
                    : "Added \(created.displayName) to \(trimmedCompany)."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openList(_ list: SalespersonDiallerListGroup) {
        emailAutosaveTask?.cancel()
        selectedListId = list.id
        if let firstLead = list.leads.first(where: isDialableLead) ?? list.leads.first {
            select(firstLead)
        } else {
            discardConversationIfNeeded(activeCall)
            selectedLead = nil
            notes = ""
            email = ""
            textDropBody = ""
            activeCall = nil
            isCallSessionActive = false
            isDiallerSessionActive = false
            isDiallerSessionPaused = false
            diallerSessionStartedAt = nil
        }
    }

    func openMainList() {
        guard let list = leadLists.first ?? mainList else { return }
        openList(list)
    }

    func openListMatching(id: String?, title: String?) {
        let normalizedId = Self.normalizedListKey(id)
        let normalizedTitle = Self.normalizedListKey(title)

        if let list = leadLists.first(where: { list in
            Self.normalizedListKey(list.id) == normalizedId ||
            Self.normalizedListKey(list.title) == normalizedTitle
        }) {
            openList(list)
            return
        }

        openMainList()
    }

    func closeList() {
        emailAutosaveTask?.cancel()
        discardConversationIfNeeded(activeCall)
        if isDiallerSessionActive || isCallSessionActive {
            SalespersonVoiceCallService.shared.endActiveCall()
        }
        selectedListId = nil
        selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        activeCall = nil
        manualCallNumber = nil
        isCallSessionActive = false
        isDiallerSessionActive = false
        isDiallerSessionPaused = false
        diallerSessionStartedAt = nil
    }

    func removeActiveList() {
        let removedListName = activeList?.title
        closeList()
        if let removedListName {
            statusMessage = "Removed \(removedListName) from the dialler. Choose another list when you're ready."
        }
    }

    func closeLead() {
        emailAutosaveTask?.cancel()
        discardConversationIfNeeded(activeCall)
        if isDiallerSessionActive || isCallSessionActive {
            SalespersonVoiceCallService.shared.endActiveCall()
        }
        selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        activeCall = nil
        manualCallNumber = nil
        isCallSessionActive = false
        isDiallerSessionActive = false
        isDiallerSessionPaused = false
        diallerSessionStartedAt = nil
    }

    func select(_ lead: SalespersonDiallerLead) {
        emailAutosaveTask?.cancel()
        discardConversationIfNeeded(activeCall)
        selectedListId = selectedListId ?? listId(containing: lead) ?? leadLists.first?.id ?? mainListId
        selectedLead = lead
        notes = lead.notes ?? ""
        email = lead.email ?? ""
        textDropBody = defaultTextDropBody(for: lead)
        activeCall = nil
        manualCallNumber = nil
        isCallSessionActive = false
    }

    func loadSmartLists() async {
        guard !isLoadingSmartLists else { return }
        isLoadingSmartLists = true
        errorMessage = nil
        defer { isLoadingSmartLists = false }
        do {
            smartLists = try await SalespersonMobileAPI.shared.fetchDiallerSmartLists()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importSmartList(_ list: SalespersonDiallerSmartListOption) async {
        guard !isImportingSmartList else { return }
        guard list.dialableCount > 0 else {
            errorMessage = "This smart list has no dialable leads."
            return
        }
        isImportingSmartList = true
        errorMessage = nil
        statusMessage = nil
        defer { isImportingSmartList = false }
        do {
            let response = try await SalespersonMobileAPI.shared.importDiallerLeads(list.leads)
            let imported = (response.leads ?? []).map { lead in
                var copy = lead
                copy.listId = copy.listId?.nilIfEmpty ?? list.id
                copy.listName = copy.listName?.nilIfEmpty ?? list.name
                return copy
            }
            imported.forEach(replaceOrAppendLead)
            selectedListId = leadLists.first(where: { $0.id == list.id })?.id
                ?? listId(containing: imported.first)
                ?? leadLists.first?.id
            if let firstLead = imported.first {
                select(firstLead)
            } else {
                selectedLead = nil
            }
            statusMessage = response.warning ?? "\(response.importedCount ?? imported.count) added from \(list.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createSmartList(named requestedName: String) async -> Bool {
        let name = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isCreatingSmartList else { return false }
        isCreatingSmartList = true
        errorMessage = nil
        defer { isCreatingSmartList = false }
        do {
            let created = try await SalespersonMobileAPI.shared.createDiallerSmartList(name: name)
            smartLists.removeAll { $0.id == created.id }
            smartLists.insert(created, at: 0)
            statusMessage = "Created \(created.name). It is available on iOS and web."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadRecordings(starredOnly: Bool = false) async {
        guard !isLoadingRecordings else { return }
        isLoadingRecordings = true
        errorMessage = nil
        defer { isLoadingRecordings = false }
        do {
            let loadedRecordings = try await SalespersonMobileAPI.shared.fetchDiallerRecordings(starredOnly: starredOnly)
            recordings = starredOnly ? loadedRecordings.filter(\.isStarred) : loadedRecordings
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func callSelected() async {
        guard let selectedLead else { return }
        await placeCall(lead: selectedLead)
    }

    func callManual(number: String) async -> Bool {
        guard !isPlacingCall else { return false }
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNumber.filter(\.isNumber).count >= 8 else {
            errorMessage = "Enter a valid phone number."
            return false
        }

        isPlacingCall = true
        errorMessage = nil
        statusMessage = nil
        defer { isPlacingCall = false }
        do {
            SalespersonVoiceCallService.shared.endActiveCall()
            discardConversationIfNeeded(activeCall)
            let call = try await SalespersonMobileAPI.shared.startManualDiallerCall(phone: trimmedNumber)
            activeCall = call
            manualCallNumber = call.toNumber ?? trimmedNumber
            try await SalespersonVoiceCallService.shared.startOutboundCall(
                label: manualCallNumber ?? trimmedNumber,
                callRequestId: call.callRequestId,
                destinationNumber: call.toNumber ?? trimmedNumber,
                fromNumber: call.fromNumber
            )
            callsMade += 1
            isCallSessionActive = true
            statusMessage = "Calling \(manualCallNumber ?? trimmedNumber)."
            return true
        } catch {
            discardConversationIfNeeded(activeCall)
            activeCall = nil
            manualCallNumber = nil
            isCallSessionActive = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openGabeTestLead() async {
        await openTestLead(name: "Gabe Phillippe", phone: gabeTestPhone, id: gabeTestLeadId)
    }

    func openSantanaTestLead() async {
        await openTestLead(
            name: "Santana Philippe",
            phone: santanaTestPhone,
            id: santanaTestLeadId,
            company: "Prima Aesthetic Studios",
            role: "Owner",
            city: "Whitby",
            region: "Ontario",
            timeZoneIdentifier: "America/Toronto"
        )
    }

    func openDanielQaqishTestLead() async {
        await openTestLead(name: "Daniel Qaqish", phone: danielQaqishTestPhone, id: danielQaqishTestLeadId)
    }

    private func openTestLead(
        name: String,
        phone: String,
        id: UUID,
        company: String? = nil,
        role: String? = nil,
        city: String? = nil,
        region: String? = nil,
        timeZoneIdentifier: String? = nil
    ) async {
        guard !isOpeningTestLead else { return }
        if let existingLead = leads.first(where: { $0.phone.normalizedPhoneDigits == phone.normalizedPhoneDigits }) {
            let listBackedLead = enrichedTestLead(
                existingLead,
                name: name,
                company: company,
                role: role,
                city: city,
                region: region,
                timeZoneIdentifier: timeZoneIdentifier
            )
            replaceOrAppendLead(listBackedLead)
            select(listBackedLead)
            statusMessage = "Opened \(name)."
            return
        }

        isOpeningTestLead = true
        errorMessage = nil
        statusMessage = nil
        defer { isOpeningTestLead = false }

        do {
            let response = try await SalespersonMobileAPI.shared.importDiallerLeads([
                SalespersonDiallerImportLead(
                    name: name,
                    phone: phone,
                    company: company,
                    email: nil,
                    listId: testListId,
                    listName: testListName
                )
            ])
            if let importedLead = response.leads?.first {
                let listBackedLead = enrichedTestLead(
                    importedLead,
                    name: name,
                    company: company,
                    role: role,
                    city: city,
                    region: region,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                replaceOrAppendLead(listBackedLead)
                select(listBackedLead)
                statusMessage = response.warning ?? "Opened \(name)."
                return
            }
            let fallbackLead = enrichedTestLead(
                makeTestLead(name: name, phone: phone, id: id),
                name: name,
                company: company,
                role: role,
                city: city,
                region: region,
                timeZoneIdentifier: timeZoneIdentifier
            )
            replaceOrAppendLead(fallbackLead)
            select(fallbackLead)
            statusMessage = response.warning ?? "Opened \(name) for testing."
        } catch {
            let fallbackLead = enrichedTestLead(
                makeTestLead(name: name, phone: phone, id: id),
                name: name,
                company: company,
                role: role,
                city: city,
                region: region,
                timeZoneIdentifier: timeZoneIdentifier
            )
            replaceOrAppendLead(fallbackLead)
            select(fallbackLead)
            statusMessage = "Opened \(name) for testing."
        }
    }

    func callNext() async {
        if let current = selectedLead,
           let next = nextDialableLead(after: current.id) {
            select(next)
            await placeCall(lead: next)
            return
        }
        if let first = nextDialableLead(after: nil) {
            select(first)
            await placeCall(lead: first)
            return
        }
        closeLead()
        statusMessage = "No valid pending leads left."
    }

    func advanceToNextLead() {
        if let current = selectedLead,
           let next = nextDialableLead(after: current.id) {
            select(next)
            return
        }
        if let first = nextDialableLead(after: nil) {
            select(first)
            return
        }
        closeLead()
        statusMessage = "No valid pending leads left."
    }

    func appendQuickNote(_ note: String) {
        let separator = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
        notes += "\(separator)\(note)"
    }

    func saveCurrentConversation() async {
        guard let call = activeCall else {
            errorMessage = "Start a call before saving it for content."
            return
        }
        guard !call.isContentSaved, !isSavingContent else { return }
        isSavingContent = true
        errorMessage = nil
        defer { isSavingContent = false }
        do {
            let savedCall = try await SalespersonMobileAPI.shared.setCallContentSaved(callId: call.id, saved: true)
            if activeCall?.id == call.id {
                activeCall = savedCall
            }
            discardRequestedCallIds.remove(call.id)
            statusMessage = "Saved to Saved Content. The MP3 appears after Telnyx finishes processing it."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleStar(_ lead: SalespersonDiallerLead) async {
        do {
            replaceLead(try await SalespersonMobileAPI.shared.toggleDiallerLeadStar(
                id: lead.id,
                isStarred: !(lead.isStarred ?? false)
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeLead(_ lead: SalespersonDiallerLead) async {
        do {
            try await SalespersonMobileAPI.shared.removeDiallerLead(id: lead.id)
            leads.removeAll { $0.id == lead.id }
            if selectedLead?.id == lead.id {
                selectedLead = nil
                selectNextLead()
            }
            statusMessage = "Lead removed from queue."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportRecording(_ recording: SalespersonDiallerRecording, leadName: String) async {
        guard !isExportingRecording else { return }
        isExportingRecording = true
        errorMessage = nil
        defer { isExportingRecording = false }
        do {
            let safeName = leadName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: " ", with: "-")
                .nilIfEmpty ?? "lead"
            let url = try await SalespersonMobileAPI.shared.downloadDiallerRecording(
                downloadUrl: recording.downloadUrl,
                fallbackName: "\(safeName)-recording.mp3"
            )
            recordingExport = SalespersonRecordingExport(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func hangUp() {
        let isManualCall = selectedLead == nil
        SalespersonVoiceCallService.shared.endActiveCall()
        isCallSessionActive = false
        if isManualCall {
            discardConversationIfNeeded(activeCall)
            activeCall = nil
            manualCallNumber = nil
        }
        statusMessage = isManualCall ? "Manual call ended." : "Call ended. Choose a status."
    }

    func pauseSession() {
        guard isDiallerSessionActive, !isDiallerSessionPaused else { return }
        SalespersonVoiceCallService.shared.endActiveCall()
        isCallSessionActive = false
        isDiallerSessionPaused = true
        statusMessage = "Dialler paused."
    }

    func resumeSession() async {
        guard isDiallerSessionActive, isDiallerSessionPaused, let selectedLead else { return }
        isDiallerSessionPaused = false
        await placeCall(lead: selectedLead)
    }

    func skipCurrentLead() async {
        guard isDiallerSessionActive else { return }
        let shouldContinue = !isDiallerSessionPaused
        SalespersonVoiceCallService.shared.endActiveCall()
        isCallSessionActive = false
        discardConversationIfNeeded(activeCall)
        activeCall = nil
        advanceToNextLead()
        guard shouldContinue, let selectedLead else {
            statusMessage = "Lead skipped."
            return
        }
        await placeCall(lead: selectedLead)
    }

    func endSession() {
        guard isDiallerSessionActive else { return }
        SalespersonVoiceCallService.shared.endActiveCall()
        discardConversationIfNeeded(activeCall)
        activeCall = nil
        isCallSessionActive = false
        isDiallerSessionActive = false
        isDiallerSessionPaused = false
        diallerSessionStartedAt = nil
        statusMessage = "Dialler session ended."
    }

    func callDidEnd() {
        guard activeCall != nil else { return }
        let isManualCall = selectedLead == nil
        isCallSessionActive = false
        if isManualCall {
            discardConversationIfNeeded(activeCall)
            activeCall = nil
            manualCallNumber = nil
        }
        statusMessage = isManualCall ? "Manual call ended." : "Call ended. Choose a status."
    }

    func markCurrentCallAnswered() {
        guard let callId = activeCall?.id,
              answeredCallIds.insert(callId).inserted else { return }
        callsAnswered += 1
    }

    func toggleMute() {
        SalespersonVoiceCallService.shared.setMuted(!SalespersonVoiceCallService.shared.isMuted)
    }

    func dropVoicemailAndAdvance() async {
        guard let activeCall else {
            errorMessage = "Start a call before dropping voicemail."
            return
        }
        isDroppingVoicemail = true
        errorMessage = nil
        statusMessage = nil
        defer { isDroppingVoicemail = false }
        do {
            try await SalespersonMobileAPI.shared.dropVoicemail(callId: activeCall.id)
            try await SalespersonMobileAPI.shared.saveCallDisposition(
                callId: activeCall.id,
                disposition: "left_voicemail",
                note: notes
            )
            SalespersonVoiceCallService.shared.endActiveCall()
            completeCurrentLead(message: "Voicemail dropped.")
            await callNext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTextDrop() async {
        guard let activeCall else {
            errorMessage = "Start a call before sending a text drop."
            return
        }
        guard let selectedLead else {
            errorMessage = "Choose a lead before sending a text drop."
            return
        }
        let body = textDropBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            errorMessage = "Write a text before sending it."
            return
        }
        isSendingTextDrop = true
        errorMessage = nil
        statusMessage = nil
        defer { isSendingTextDrop = false }
        do {
            _ = try await SalespersonMobileAPI.shared.sendLeadText(lead: selectedLead, body: body)
            let nextNotes = [
                notes.trimmingCharacters(in: .whitespacesAndNewlines),
                "Text drop sent: \(body)"
            ].filter { !$0.isEmpty }.joined(separator: "\n")
            notes = nextNotes
            try await SalespersonMobileAPI.shared.saveCallDisposition(
                callId: activeCall.id,
                disposition: "callback_requested",
                note: nextNotes
            )
            completeCurrentLead(message: "Text drop sent.")
            await callNext()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendCallbackText() async {
        guard let selectedLead else { return }
        let body = textDropBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            errorMessage = "Write a text before sending it."
            return
        }
        isSendingCallbackText = true
        errorMessage = nil
        statusMessage = nil
        defer { isSendingCallbackText = false }

        do {
            let warning = try await SalespersonMobileAPI.shared.sendLeadText(lead: selectedLead, body: body)
            statusMessage = warning ?? "Text sent."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTextMessage(_ message: String) async -> Bool {
        guard let selectedLead else { return false }
        let body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            errorMessage = "Write a text before sending it."
            return false
        }

        isSendingCallbackText = true
        errorMessage = nil
        statusMessage = nil
        defer { isSendingCallbackText = false }

        do {
            let warning = try await SalespersonMobileAPI.shared.sendInboxText(
                leadId: selectedLead.id.uuidString,
                contactId: nil,
                body: body,
                phone: selectedLead.phone
            )
            textDropBody = body
            statusMessage = warning ?? "Text sent."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendEmailMessage(to recipient: String, subject: String, body: String) async -> Bool {
        guard let selectedLead else { return false }
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(trimmedRecipient) else {
            errorMessage = "Enter a valid email address."
            return false
        }
        guard !trimmedBody.isEmpty else {
            errorMessage = "Write an email before sending it."
            return false
        }

        isSendingEmail = true
        errorMessage = nil
        statusMessage = nil
        defer { isSendingEmail = false }

        do {
            emailAutosaveTask?.cancel()
            let savedEmail = selectedLead.email ?? ""
            var saveWarning: String?
            if Self.normalizedEmail(savedEmail) != Self.normalizedEmail(trimmedRecipient) {
                let result = try await SalespersonMobileAPI.shared.saveDiallerLeadContact(
                    id: selectedLead.id,
                    notes: notes,
                    email: trimmedRecipient
                )
                replaceLead(result.0)
                email = result.0.email ?? trimmedRecipient
                saveWarning = result.1
            } else {
                email = trimmedRecipient
            }

            let warning = try await SalespersonMobileAPI.shared.sendInboxEmail(
                leadId: selectedLead.id.uuidString,
                contactId: nil,
                to: trimmedRecipient,
                subject: trimmedSubject.isEmpty ? "Following up" : trimmedSubject,
                body: trimmedBody,
                useDemoTemplate: SalespersonDemoEmailTemplate.matches(
                    subject: trimmedSubject, body: trimmedBody, recipientName: selectedLead.name
                )
            )
            statusMessage = warning ?? saveWarning ?? "Email sent and added to the dialler."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveContact() async {
        guard let selectedLead else { return }
        emailAutosaveTask?.cancel()
        isSaving = true
        errorMessage = nil
        statusMessage = nil
        defer { isSaving = false }

        do {
            let (updatedLead, warning) = try await SalespersonMobileAPI.shared.saveDiallerLeadContact(
                id: selectedLead.id,
                notes: notes,
                email: email
            )
            replaceLead(updatedLead)
            self.email = updatedLead.email ?? email
            statusMessage = warning ?? "Saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleEmailAutosave() {
        emailAutosaveTask?.cancel()
        guard let selectedLead else { return }

        let requestedEmail = email
        guard Self.isValidEmail(requestedEmail) else { return }
        let savedEmail = selectedLead.email ?? ""
        guard Self.normalizedEmail(requestedEmail) != Self.normalizedEmail(savedEmail) else { return }

        let leadId = selectedLead.id
        emailAutosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            await self?.autosaveEmail(leadId: leadId, requestedEmail: requestedEmail)
        }
    }

    func associateEmailWithSelectedLead(_ requestedEmail: String) {
        email = requestedEmail
        scheduleEmailAutosave()
    }

    func log(disposition: String) async {
        guard let selectedLead else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let activeCall {
                try await SalespersonMobileAPI.shared.saveCallDisposition(
                    callId: activeCall.id,
                    disposition: disposition,
                    note: notes
                )
            } else {
                _ = try await SalespersonMobileAPI.shared.updateDiallerLead(
                    id: selectedLead.id,
                    disposition: legacyLeadDisposition(for: disposition),
                    notes: notes,
                    email: email
                )
            }
            completeCurrentLead(message: "Saved.")
            selectNextLead()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleFollowUp(name: String, at date: Date) async {
        guard let selectedLead else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let followUpName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Follow up with \(selectedLead.displayBusinessName)"
            let followUpNote = "Follow up: \(followUpName) | When: \(date.formatted(date: .abbreviated, time: .shortened))"
            let nextNotes = [
                notes.trimmingCharacters(in: .whitespacesAndNewlines),
                followUpNote
            ].filter { !$0.isEmpty }.joined(separator: "\n")

            if let activeCall {
                try await SalespersonMobileAPI.shared.saveCallDisposition(
                    callId: activeCall.id,
                    disposition: "callback_requested",
                    note: nextNotes
                )
            }

            let (_, warning) = try await SalespersonMobileAPI.shared.updateDiallerLead(
                id: selectedLead.id,
                disposition: "callback",
                notes: nextNotes,
                email: email,
                followUpName: followUpName,
                followUpAt: date,
                createNotification: true
            )
            completeCurrentLead(message: warning ?? "Follow-up added to Task.")
            selectNextLead()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func listId(containing lead: SalespersonDiallerLead?) -> String? {
        guard let lead else { return nil }
        return leadLists.first { list in
            list.leads.contains(where: { $0.id == lead.id })
        }?.id
    }

    private func placeCall(lead: SalespersonDiallerLead) async {
        guard !isPlacingCall else { return }
        isPlacingCall = true
        errorMessage = nil
        statusMessage = nil
        defer { isPlacingCall = false }
        do {
            SalespersonVoiceCallService.shared.endActiveCall()
            discardConversationIfNeeded(activeCall)
            let call = try await SalespersonMobileAPI.shared.startDiallerCall(lead: lead)
            activeCall = call
            manualCallNumber = nil
            let label = lead.displayBusinessName
            try await SalespersonVoiceCallService.shared.startOutboundCall(
                label: label,
                callRequestId: call.callRequestId,
                destinationNumber: call.toNumber,
                fromNumber: call.fromNumber
            )
            callsMade += 1
            isCallSessionActive = true
            if !isDiallerSessionActive {
                diallerSessionStartedAt = Date()
            }
            isDiallerSessionActive = true
            isDiallerSessionPaused = false
            statusMessage = "Calling \(label)."
        } catch {
            discardConversationIfNeeded(activeCall)
            activeCall = nil
            manualCallNumber = nil
            isCallSessionActive = false
            errorMessage = error.localizedDescription
        }
    }

    private func completeCurrentLead(message: String) {
        guard let selectedLead else { return }
        emailAutosaveTask?.cancel()
        leads.removeAll { $0.id == selectedLead.id }
        discardConversationIfNeeded(activeCall)
        activeCall = nil
        manualCallNumber = nil
        isCallSessionActive = false
        self.selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        statusMessage = message
    }

    private func discardConversationIfNeeded(_ call: SalespersonDiallerCall?) {
        guard let call, !call.isContentSaved, discardRequestedCallIds.insert(call.id).inserted else { return }
        Task { @MainActor [weak self] in
            do {
                _ = try await SalespersonMobileAPI.shared.setCallContentSaved(callId: call.id, saved: false)
            } catch {
                self?.errorMessage = "The unsaved recording could not be deleted yet: \(error.localizedDescription)"
            }
        }
    }

    private func autosaveEmail(leadId: UUID, requestedEmail: String) async {
        guard selectedLead?.id == leadId else { return }

        let requestedNormalized = Self.normalizedEmail(requestedEmail)
        let savedNormalized = Self.normalizedEmail(selectedLead?.email ?? "")
        guard requestedNormalized != savedNormalized else { return }

        do {
            let (updatedLead, _) = try await SalespersonMobileAPI.shared.saveDiallerLeadContact(
                id: leadId,
                notes: notes,
                email: requestedEmail
            )
            replaceLead(updatedLead)
            if selectedLead?.id == leadId, Self.normalizedEmail(email) == requestedNormalized {
                self.email = updatedLead.email ?? requestedEmail
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func replaceLead(_ updatedLead: SalespersonDiallerLead) {
        if let index = leads.firstIndex(where: { $0.id == updatedLead.id }) {
            leads[index] = updatedLead
        }
        if selectedLead?.id == updatedLead.id {
            selectedLead = updatedLead
        }
    }

    private func replaceOrAppendLead(_ lead: SalespersonDiallerLead) {
        if let index = leads.firstIndex(where: { $0.id == lead.id }) {
            leads[index] = lead
        } else if let index = leads.firstIndex(where: { $0.phone.normalizedPhoneDigits == lead.phone.normalizedPhoneDigits }) {
            leads[index] = lead
        } else {
            leads.insert(lead, at: 0)
        }
    }

    private func makeTestLead(name: String, phone: String, id: UUID) -> SalespersonDiallerLead {
        SalespersonDiallerLead(
            id: id,
            name: name,
            phone: phone,
            company: nil,
            email: nil,
            website: nil,
            websiteDomain: nil,
            listId: testListId,
            listName: testListName,
            latestCallRecording: nil,
            isStarred: false,
            disposition: nil,
            notes: nil,
            calledAt: nil,
            createdAt: Date()
        )
    }

    private func leadWithTestList(_ lead: SalespersonDiallerLead) -> SalespersonDiallerLead {
        var copy = lead
        copy.listId = copy.listId?.nilIfEmpty ?? testListId
        copy.listName = copy.listName?.nilIfEmpty ?? testListName
        return copy
    }

    private func enrichedTestLead(
        _ lead: SalespersonDiallerLead,
        name: String,
        company: String?,
        role: String?,
        city: String?,
        region: String?,
        timeZoneIdentifier: String?
    ) -> SalespersonDiallerLead {
        var copy = leadWithTestList(lead)
        copy.name = name
        copy.company = company ?? copy.company
        copy.role = role ?? copy.role
        copy.city = city ?? copy.city
        copy.region = region ?? copy.region
        copy.timeZoneIdentifier = timeZoneIdentifier ?? copy.timeZoneIdentifier
        return copy
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let normalized = normalizedEmail(value)
        let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2
            && !parts[0].isEmpty
            && parts[1].contains(".")
            && !normalized.contains(where: \.isWhitespace)
    }

    private static func normalizedListKey(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func selectNextLead() {
        guard let next = nextDialableLead(after: nil) else { return }
        select(next)
    }

    private func nextDialableLead(after id: UUID?) -> SalespersonDiallerLead? {
        let queue = selectedList?.leads ?? leads
        let currentIndex = id.flatMap { selectedId in
            queue.firstIndex(where: { $0.id == selectedId })
        } ?? -1
        let later = queue.dropFirst(max(currentIndex + 1, 0)).first(where: isDialablePending)
        return later ?? queue.first(where: isDialablePending)
    }

    private func isDialablePending(_ lead: SalespersonDiallerLead) -> Bool {
        lead.id != selectedLead?.id &&
        isDialableLead(lead)
    }

    private func isDialableLead(_ lead: SalespersonDiallerLead) -> Bool {
        lead.disposition == nil &&
        !lead.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func defaultTextDropBody(for lead: SalespersonDiallerLead?) -> String {
        guard lead != nil else { return "" }
        return "Hey, Daniel with WolfGrid. Give me a call when you get a chance."
    }

    private func legacyLeadDisposition(for callDisposition: String) -> String {
        switch callDisposition {
        case "interested", "connected", "appointment_set": return "interested"
        case "callback_requested", "follow_up": return "callback"
        case "do_not_call": return "dnc"
        default: return "not_now"
        }
    }
}

@MainActor
private final class SalespersonInboxViewModel: ObservableObject {
    @Published var threads: [SalespersonInboxThread] = []
    @Published var counts: [String: Int] = [:]
    @Published var selectedSource: String
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    let sources = ["all", "sms", "email", "call"]

    init(selectedSource: String = "all") {
        self.selectedSource = selectedSource
    }

    func load() async {
        let requestUserId = AuthManager.shared.user?.id
        let requestWorkspaceId = WorkspaceContext.shared.workspaceId
        threads = []
        counts = [:]
        guard requestUserId != nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let inboxRequest = SalespersonMobileAPI.shared.fetchInbox(source: selectedSource)
            async let leadsRequest = SalespersonMobileAPI.shared.fetchSalespersonLeads()
            let response = try await inboxRequest
            let knownLeads = (try? await leadsRequest) ?? []
            guard AuthManager.shared.user?.id == requestUserId,
                  WorkspaceContext.shared.workspaceId == requestWorkspaceId else { return }
            let rawThreads = response.threads ?? Self.threads(from: response.items ?? [])
            threads = Self.consolidatedThreads(
                Self.threadsByResolvingContacts(rawThreads, from: knownLeads)
            )
            counts = response.counts ?? [:]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectSource(_ source: String) {
        guard selectedSource != source else { return }
        selectedSource = source
    }

    func markDone(_ item: SalespersonInboxItem) async {
        do {
            try await SalespersonMobileAPI.shared.updateInboxItem(id: item.id, status: "done")
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markRead(_ item: SalespersonInboxItem) async {
        do {
            try await SalespersonMobileAPI.shared.updateInboxItem(id: item.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markThreadRead(_ thread: SalespersonInboxThread) async {
        let unreadIDs = thread.events
            .filter { $0.readAt == nil && $0.direction != "outbound" }
            .map(\.id)
        guard !unreadIDs.isEmpty else { return }

        do {
            for id in unreadIDs {
                try await SalespersonMobileAPI.shared.updateInboxItem(id: id)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendText(
        in thread: SalespersonInboxThread,
        body: String,
        pendingAttachment: SalespersonInboxPendingAttachment? = nil
    ) async -> SalespersonInboxThread? {
        guard let phone = thread.textPhone else {
            errorMessage = "This thread does not have a phone number."
            return nil
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || pendingAttachment != nil else { return nil }

        isSending = true
        statusMessage = nil
        errorMessage = nil
        defer { isSending = false }

        do {
            let sentAt = Date()
            let uploadedAttachments: [SalespersonInboxAttachment]
            if let pendingAttachment {
                uploadedAttachments = [try await SalespersonMobileAPI.shared.uploadInboxAttachment(
                    data: pendingAttachment.data,
                    fileName: pendingAttachment.fileName,
                    mimeType: pendingAttachment.mimeType
                )]
            } else {
                uploadedAttachments = []
            }
            let warning = try await SalespersonMobileAPI.shared.sendInboxText(
                contactId: thread.contactId,
                body: trimmed,
                phone: phone,
                attachments: uploadedAttachments
            )
            if let warning { statusMessage = warning }
            var refreshed: SalespersonInboxThread?
            if let contactId = thread.contactId?.nilIfEmpty {
                refreshed = try await SalespersonMobileAPI.shared.fetchInboxThread(contactId: contactId, source: selectedSource)
                if refreshed == nil {
                    refreshed = try await SalespersonMobileAPI.shared.fetchInboxThread(contactId: contactId)
                }
            }
            await load()
            let serverThread = refreshed
                ?? threads.first(where: { $0.id == thread.id })
                ?? threads.first(where: {
                    guard let contactId = thread.contactId?.nilIfEmpty else { return false }
                    return $0.contactId == contactId
                })
                ?? thread
            let visibleThread = Self.threadByAddingSentText(
                trimmed,
                phone: phone,
                sentAt: sentAt,
                attachments: uploadedAttachments,
                to: serverThread
            )
            replaceThread(with: visibleThread, matching: thread)
            return visibleThread
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func sendEmail(
        contactId: String?,
        to recipient: String,
        subject: String,
        body: String,
        matching thread: SalespersonInboxThread? = nil
    ) async -> SalespersonInboxThread? {
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(trimmedRecipient) else {
            errorMessage = "Enter a valid recipient email address."
            return nil
        }
        guard !trimmedBody.isEmpty else { return nil }

        isSending = true
        statusMessage = nil
        errorMessage = nil
        defer { isSending = false }

        do {
            let warning = try await SalespersonMobileAPI.shared.sendInboxEmail(
                contactId: contactId,
                to: trimmedRecipient,
                subject: trimmedSubject.isEmpty ? "Following up" : trimmedSubject,
                body: trimmedBody
            )
            statusMessage = warning ?? "Email sent."
            await load()
            if let contactId = contactId?.nilIfEmpty {
                return threads.first(where: { $0.contactId == contactId && $0.latestSource == "email" })
                    ?? threads.first(where: { $0.contactId == contactId })
                    ?? thread
            }
            return threads.first(where: {
                $0.primaryEmail?.caseInsensitiveCompare(trimmedRecipient) == .orderedSame
            }) ?? thread
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func sendNewText(to phone: String, body: String) async -> Bool {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPhone.normalizedPhoneDigits.count >= 8 else {
            errorMessage = "Enter a valid phone number."
            return false
        }
        guard !trimmedBody.isEmpty else { return false }

        isSending = true
        statusMessage = nil
        errorMessage = nil
        defer { isSending = false }

        do {
            let warning = try await SalespersonMobileAPI.shared.sendInboxText(
                contactId: nil,
                body: trimmedBody,
                phone: trimmedPhone
            )
            statusMessage = warning ?? "Message sent."
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func callManual(number: String) async -> Bool {
        let trimmedNumber = number.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNumber.normalizedPhoneDigits.count >= 8 else {
            errorMessage = "Enter a valid phone number."
            return false
        }

        statusMessage = nil
        errorMessage = nil
        do {
            SalespersonVoiceCallService.shared.endActiveCall()
            let call = try await SalespersonMobileAPI.shared.startManualDiallerCall(phone: trimmedNumber)
            try await SalespersonVoiceCallService.shared.startOutboundCall(
                label: call.toNumber ?? trimmedNumber,
                callRequestId: call.callRequestId,
                destinationNumber: call.toNumber ?? trimmedNumber,
                fromNumber: call.fromNumber
            )
            statusMessage = "Calling \(call.toNumber ?? trimmedNumber)."
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func sortedThreads(_ threads: [SalespersonInboxThread]) -> [SalespersonInboxThread] {
        threads.sorted { lhs, rhs in
            if lhs.latestAt == rhs.latestAt {
                return lhs.id < rhs.id
            }
            return lhs.latestAt > rhs.latestAt
        }
    }

    private static func threadsByResolvingContacts(
        _ threads: [SalespersonInboxThread],
        from leads: [SalespersonLeadMasterRow]
    ) -> [SalespersonInboxThread] {
        guard !leads.isEmpty else { return threads }

        return threads.map { thread in
            guard thread.contact?.fullName?.normalizedInboxLine.nilIfEmpty == nil,
                  let lead = matchingLead(for: thread, in: leads) else {
                return thread
            }

            let contact = SalespersonInboxContactSummary(
                id: lead.salesContactId?.nilIfEmpty ?? lead.id.uuidString,
                fullName: lead.name.nilIfEmpty,
                phone: lead.phone,
                email: lead.email,
                address: lead.address?.nilIfEmpty ?? lead.locationLine
            )
            return SalespersonInboxThread(
                id: thread.id,
                contactId: thread.contactId ?? lead.salesContactId?.nilIfEmpty,
                contact: contact,
                title: lead.name.nilIfEmpty ?? thread.title,
                subtitle: thread.subtitle,
                primaryPhone: thread.textPhone ?? lead.phone,
                primaryEmail: thread.emailRecipient ?? lead.email,
                latestAt: thread.latestAt,
                latestSource: thread.latestSource,
                latestPreview: thread.latestPreview,
                unreadCount: thread.unreadCount,
                needsResponse: thread.needsResponse,
                events: thread.events
            )
        }
    }

    private static func matchingLead(
        for thread: SalespersonInboxThread,
        in leads: [SalespersonLeadMasterRow]
    ) -> SalespersonLeadMasterRow? {
        if let contactId = thread.contactId?.nilIfEmpty?.lowercased(),
           let match = leads.first(where: {
               $0.id.uuidString.lowercased() == contactId ||
               $0.salesContactId?.lowercased() == contactId
           }) {
            return match
        }

        if let phoneKey = thread.textPhone.flatMap(inboxPhoneIdentityKey),
           let match = leads.first(where: {
               $0.phone.flatMap(inboxPhoneIdentityKey) == phoneKey
           }) {
            return match
        }

        if let email = thread.emailRecipient?.nilIfEmpty?.lowercased() {
            return leads.first { $0.email?.nilIfEmpty?.lowercased() == email }
        }
        return nil
    }

    private static func inboxPhoneIdentityKey(_ phone: String) -> String? {
        let digits = phone.normalizedPhoneDigits
        guard !digits.isEmpty else { return nil }
        return digits.count > 10 ? String(digits.suffix(10)) : digits
    }

    private static func consolidatedThreads(_ threads: [SalespersonInboxThread]) -> [SalespersonInboxThread] {
        let grouped = Dictionary(grouping: threads) { thread in
            if let digits = thread.textPhone?.normalizedPhoneDigits.nilIfEmpty,
               thread.latestSource == "sms" || thread.events.contains(where: { $0.source == "sms" }) {
                return "sms:\(digits)"
            }
            return "thread:\(thread.id)"
        }

        return sortedThreads(grouped.values.map { group in
            guard group.count > 1 else { return group[0] }

            let orderedThreads = group.sorted { $0.latestAt < $1.latestAt }
            let latest = orderedThreads.last ?? group[0]
            let preferredIdentity = orderedThreads.reversed().first { thread in
                thread.contact?.fullName?.normalizedInboxLine.nilIfEmpty != nil
            }
            let allEvents = orderedThreads
                .flatMap(\.events)
                .reduce(into: [String: SalespersonInboxEvent]()) { eventsByID, event in
                    eventsByID[event.id] = event
                }
                .values
                .sorted { $0.occurredAt < $1.occurredAt }

            return SalespersonInboxThread(
                id: preferredIdentity?.id ?? latest.id,
                contactId: preferredIdentity?.contactId ?? orderedThreads.compactMap(\.contactId).first,
                contact: preferredIdentity?.contact ?? orderedThreads.compactMap(\.contact).first,
                title: preferredIdentity?.title ?? latest.title,
                subtitle: preferredIdentity?.subtitle ?? latest.subtitle,
                primaryPhone: preferredIdentity?.textPhone ?? latest.textPhone,
                primaryEmail: preferredIdentity?.primaryEmail ?? orderedThreads.compactMap(\.primaryEmail).first,
                latestAt: latest.latestAt,
                latestSource: latest.latestSource,
                latestPreview: latest.latestPreview,
                unreadCount: allEvents.filter { $0.readAt == nil && $0.direction != "outbound" }.count,
                needsResponse: orderedThreads.contains(where: \.needsResponse),
                events: allEvents
            )
        })
    }

    private func replaceThread(with replacement: SalespersonInboxThread, matching original: SalespersonInboxThread) {
        if let index = threads.firstIndex(where: { $0.id == replacement.id || $0.id == original.id }) {
            threads[index] = replacement
        } else {
            threads.append(replacement)
        }
        threads = Self.sortedThreads(threads)
    }

    private static func threadByAddingSentText(
        _ body: String,
        phone: String,
        sentAt: Date,
        attachments: [SalespersonInboxAttachment] = [],
        to thread: SalespersonInboxThread
    ) -> SalespersonInboxThread {
        let alreadyPresent = thread.events.contains { event in
            guard event.source == "sms", event.direction == "outbound" else { return false }
            let eventBody = (event.body ?? event.preview ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let eventAttachments = event.attachments ?? []
            return eventBody == body
                && (attachments.isEmpty || eventAttachments == attachments)
                && abs(event.occurredAt.timeIntervalSince(sentAt)) < 120
        }
        guard !alreadyPresent else { return thread }

        let event = SalespersonInboxEvent(
            id: "local-sms-\(UUID().uuidString)",
            source: "sms",
            kind: "sms_item",
            direction: "outbound",
            title: "Sent message",
            preview: body.nilIfEmpty ?? (attachments.first?.isVideo == true ? "Video" : attachments.isEmpty ? nil : "Photo"),
            body: body,
            status: "sent",
            occurredAt: sentAt,
            readAt: sentAt,
            fromLabel: nil,
            fromEmail: nil,
            fromPhone: nil,
            toLabel: thread.contact?.displayName,
            toEmail: nil,
            toPhone: phone,
            contactId: thread.contactId,
            href: nil,
            attachments: attachments
        )

        return SalespersonInboxThread(
            id: thread.id,
            contactId: thread.contactId,
            contact: thread.contact,
            title: thread.title,
            subtitle: thread.subtitle,
            primaryPhone: thread.primaryPhone ?? phone,
            primaryEmail: thread.primaryEmail,
            latestAt: sentAt,
            latestSource: "sms",
            latestPreview: body.nilIfEmpty ?? (attachments.first?.isVideo == true ? "Video" : attachments.isEmpty ? nil : "Photo"),
            unreadCount: thread.unreadCount,
            needsResponse: false,
            events: (thread.events + [event]).sorted { $0.occurredAt < $1.occurredAt }
        )
    }

    private static func threads(from items: [SalespersonInboxItem]) -> [SalespersonInboxThread] {
        let groups = Dictionary(grouping: items) { item in
            if let contactId = item.contactId?.nilIfEmpty {
                return "contact:\(contactId)"
            }
            let counterpartyEmail = item.direction == "outbound" ? item.toEmail : item.fromEmail
            if let email = counterpartyEmail?.nilIfEmpty {
                return "email:\(email.lowercased())"
            }
            if let phone = (item.fromPhone ?? item.toPhone)?.nilIfEmpty {
                return "phone:\(phone.normalizedPhoneDigits)"
            }
            return "item:\(item.id)"
        }

        return groups.map { key, group in
            let ordered = group.sorted { $0.occurredAt < $1.occurredAt }
            let latest = ordered.last ?? group[0]
            let events = ordered.map { item in
                SalespersonInboxEvent(
                    id: item.id,
                    source: item.source,
                    kind: "\(item.source)_item",
                    direction: item.direction,
                    title: item.title,
                    preview: item.preview,
                    body: item.body,
                    status: item.status,
                    occurredAt: item.occurredAt,
                    readAt: item.readAt,
                    fromLabel: item.fromLabel,
                    fromEmail: item.fromEmail,
                    fromPhone: item.fromPhone,
                    toLabel: item.toLabel,
                    toEmail: item.toEmail,
                    toPhone: item.toPhone,
                    contactId: item.contactId,
                    href: item.href
                )
            }
            let inboundIdentity = ordered.reversed().first(where: { $0.direction == "inbound" })
            let contactId = ordered.compactMap(\.contactId).first
            let primaryEmail = ordered.reversed().compactMap { item -> String? in
                if item.direction == "outbound" { return item.toEmail?.nilIfEmpty }
                if item.direction == "inbound" { return item.fromEmail?.nilIfEmpty }
                return item.fromEmail?.nilIfEmpty ?? item.toEmail?.nilIfEmpty
            }.first
            let primaryPhone = inboundIdentity?.fromPhone
                ?? latest.toPhone
                ?? latest.fromPhone
                ?? ordered.compactMap(\.fromPhone).first
                ?? ordered.compactMap(\.toPhone).first
            let identityLabel: String
            if latest.direction == "outbound" {
                identityLabel = latest.toLabel
                    ?? latest.toEmail
                    ?? latest.toPhone
                    ?? inboundIdentity?.fromLabel
                    ?? latest.title
            } else {
                identityLabel = inboundIdentity?.fromLabel
                    ?? latest.fromLabel
                    ?? primaryEmail
                    ?? primaryPhone
                    ?? latest.title
            }

            return SalespersonInboxThread(
                id: key,
                contactId: contactId,
                contact: nil,
                title: identityLabel,
                subtitle: primaryEmail ?? primaryPhone,
                primaryPhone: primaryPhone,
                primaryEmail: primaryEmail,
                latestAt: latest.occurredAt,
                latestSource: latest.source,
                latestPreview: latest.preview ?? latest.body,
                unreadCount: ordered.filter(\.isUnread).count,
                needsResponse: ordered.contains(where: \.needsResponse),
                events: events
            )
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return false }
        return !value.contains(where: \.isWhitespace)
    }
}

@MainActor
private enum SalespersonTaskDueFilter: String, CaseIterable, Identifiable {
    case today
    case future

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .future: return "Future"
        }
    }
}

@MainActor
private final class SalespersonTasksViewModel: ObservableObject {
    @Published var items: [SalespersonCalendarItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedDueFilter: SalespersonTaskDueFilter = .today

    var filteredItems: [SalespersonCalendarItem] {
        let selectedDueFilter = selectedDueFilter
        let now = Date()
        return items
            .filter { item in
                let isTask = item.eventType == SalespersonCalendarEventType.followUp.rawValue ||
                    item.eventType == SalespersonCalendarEventType.call.rawValue ||
                    item.eventType == SalespersonCalendarEventType.task.rawValue
                return isTask && Self.dueFilter(for: item, now: now) == selectedDueFilter
            }
            .sorted { $0.startAt < $1.startAt }
    }

    func isOverdue(_ item: SalespersonCalendarItem, now: Date = Date()) -> Bool {
        item.startAt < Calendar.current.startOfDay(for: now)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        items = await SalespersonCalendarService.shared.fetchAllCalendarItems()
    }

    func complete(_ item: SalespersonCalendarItem) async {
        do {
            try await SalespersonCalendarService.shared.deleteEvent(id: item.sourceId)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dueFilter(for item: SalespersonCalendarItem, now: Date) -> SalespersonTaskDueFilter {
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now
        return item.startAt < startOfTomorrow ? .today : .future
    }
}

@MainActor
private final class SalespersonLeadsViewModel: ObservableObject {
    @Published var leads: [SalespersonLeadMasterRow] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedListId: String?

    var leadLists: [SalespersonLeadListGroup] {
        SalespersonLeadListGroup.makeGroups(from: leads)
    }

    var contacts: [SalespersonLeadMasterRow] {
        leads.filter(\.isContact)
    }

    var filteredLeadLists: [SalespersonLeadListGroup] {
        let groups = leadLists
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groups }

        return groups.filter { group in
            if group.title.lowercased().contains(query) ||
                group.subtitle.lowercased().contains(query) ||
                (group.locationLine?.lowercased().contains(query) ?? false) {
                return true
            }
            return group.leads.contains { lead in
                Self.matches(lead, query: query)
            }
        }
    }

    var filteredLeads: [SalespersonLeadMasterRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return contacts }
        return contacts.filter { Self.matches($0, query: query) }
    }

    var selectedList: SalespersonLeadListGroup? {
        guard let selectedListId else { return nil }
        return leadLists.first { $0.id == selectedListId }
    }

    var selectedListLeads: [SalespersonLeadMasterRow] {
        guard let selectedList else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return selectedList.leads }
        return selectedList.leads.filter { Self.matches($0, query: query) }
    }

    func openList(_ list: SalespersonLeadListGroup) {
        selectedListId = list.id
        searchText = ""
    }

    func closeList() {
        selectedListId = nil
        searchText = ""
    }

    func replaceLead(_ lead: SalespersonLeadMasterRow) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        leads[index] = lead
    }

    func addLead(_ lead: SalespersonLeadMasterRow) {
        leads.removeAll { $0.id == lead.id }
        leads.insert(lead, at: 0)
    }

    @discardableResult
    func openListMatching(id: String?, title: String?) -> Bool {
        let normalizedId = Self.normalizedListKey(id)
        let normalizedTitle = Self.normalizedListKey(title)
        if let list = leadLists.first(where: { list in
            Self.normalizedListKey(list.id) == normalizedId ||
            Self.normalizedListKey(list.title) == normalizedTitle
        }) {
            selectedListId = list.id
            searchText = ""
            return true
        }

        selectedListId = nil
        searchText = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? ""
        return false
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await SalespersonMobileAPI.shared.fetchSalespersonLeads()
            if let selectedListId, !leadLists.contains(where: { $0.id == selectedListId }) {
                self.selectedListId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func matches(_ lead: SalespersonLeadMasterRow, query: String) -> Bool {
        [
            lead.name,
            lead.company,
            lead.phone,
            lead.email,
            lead.website,
            lead.websiteHost,
            lead.address,
            lead.city,
            lead.region,
            lead.countryCode,
            lead.source,
            lead.listName,
            lead.leadState,
            lead.disposition,
            lead.notes
        ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
    }

    private static func normalizedListKey(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}

@MainActor
private final class SalespersonHomeViewModel: ObservableObject {
    enum Period: String, CaseIterable, Identifiable {
        case daily
        case weekly
        case monthly
        case yearly

        var id: String { rawValue }

        var menuLabel: String {
            switch self {
            case .daily: return "Today"
            case .weekly: return "Week"
            case .monthly: return "Month"
            case .yearly: return "Year"
            }
        }

        var caption: String {
            switch self {
            case .daily: return "today"
            case .weekly: return "week"
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }
    }

    @Published var performance: SalespersonPerformanceResponse?
    @Published var selectedPeriod: Period = .daily
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var linkCopyMessage: String?

    var displayName: String {
        let cleanName = performance?.salesperson.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanName, !cleanName.isEmpty { return cleanName }
        let authName = AuthManager.shared.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let authName, !authName.isEmpty { return authName }
        let email = AuthManager.shared.user?.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if let email, !email.isEmpty {
            let emailPrefix = email
                .split(separator: "@", maxSplits: 1)
                .first
                .map(String.init)
            if let emailPrefix, !emailPrefix.isEmpty { return emailPrefix }
        }
        return "Home"
    }

    var demoVideoURL: URL {
        var components = URLComponents(url: SalespersonDemoLink.url, resolvingAgainstBaseURL: false)!
        if let code = performance?.salesperson.referralCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !code.isEmpty {
            components.queryItems = [URLQueryItem(name: "ref", value: code)]
        }
        return components.url ?? SalespersonDemoLink.url
    }

    var demoVideoLink: String {
        demoVideoURL.absoluteString
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            performance = try await SalespersonMobileAPI.shared.fetchSalespersonPerformance(period: selectedPeriod.rawValue)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectPeriod(_ period: Period) async {
        guard period != selectedPeriod else { return }
        selectedPeriod = period
        await load()
    }

    func copyDemoVideoLink() {
        UIPasteboard.general.string = demoVideoLink
        linkCopyMessage = "Demo video link copied."
    }
}

@MainActor
private final class SalespersonScraperViewModel: ObservableObject {
    @Published var markets: [ProspectMarket] = []
    @Published var industries: [ProspectIndustry] = []
    @Published var recentRuns: [ProspectSearchRun] = []
    @Published var selectedMarketId: UUID?
    @Published var selectedIndustryId: UUID?
    @Published var citySuggestions: [CitySuggestion] = []
    @Published var city = ""
    @Published var industry = ""
    @Published var region = ""
    @Published var countryCode = "US"
    @Published var relatedTerms = ""
    @Published var realEstateTarget = "individual_agents"
    @Published var prospects: [PlacesLead] = []
    @Published var summary: PlacesLeadSearchResponse?
    @Published var isLoadingOptions = false
    @Published var isSearching = false
    @Published var cityAutocompleteLoading = false
    @Published var researchModeEnabled = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var csvURL: URL?

    let countryOptions = [
        ("US", "USA"),
        ("CA", "CAN"),
        ("NZ", "NZ"),
        ("AU", "AUS"),
        ("ZA", "ZA"),
    ]

    let realEstateTargetOptions = [
        ("teams", "Team"),
        ("individual_agents", "Agent"),
        ("offices", "Office"),
    ]

    let industryOptions: [ScraperIndustryOption] = [
        ScraperIndustryOption(id: "roofing", name: "Roofing", defaultTerms: ["roofing company", "roofer", "roof repair", "roof replacement"]),
        ScraperIndustryOption(id: "solar", name: "Solar", defaultTerms: ["solar company", "solar installer", "solar panels", "residential solar"]),
        ScraperIndustryOption(id: "real-estate", name: "Real Estate", defaultTerms: ["real estate agent", "realtor", "real estate brokerage"]),
        ScraperIndustryOption(id: "pest-control", name: "Pest Control", defaultTerms: ["pest control", "exterminator", "termite control"]),
        ScraperIndustryOption(id: "lawncare", name: "Lawncare", defaultTerms: ["lawn care", "lawn service", "landscaping", "yard maintenance"]),
        ScraperIndustryOption(id: "home-security", name: "Home Security", defaultTerms: ["home security", "security systems", "alarm systems", "security installer"]),
    ]

    var canSubmit: Bool {
        city.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        industry.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        !isSearching
    }

    var realEstateMode: Bool {
        Self.isRealEstateIndustry(industry)
    }

    var defaultListName: String {
        let dateText = Date().formatted(.dateTime.month(.abbreviated).day())
        let cleanCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanIndustry = industry.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = [cleanCity.nilIfEmpty, cleanRegion.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilIfEmpty

        if realEstateMode && realEstateTarget == "individual_agents", let location {
            return "\(location) agents - \(dateText)"
        }

        let base = [
            location,
            cleanIndustry.nilIfEmpty
        ]
            .compactMap { $0 }
            .joined(separator: " - ")
            .nilIfEmpty ?? "Places leads"
        return "\(base) - \(dateText)"
    }

    var selectedRun: ProspectSearchRun? {
        guard let selectedMarketId, let selectedIndustryId else { return nil }
        return recentRuns.first {
            $0.marketId == selectedMarketId && $0.industryId == selectedIndustryId
        }
    }

    func loadOptions() async {
        isLoadingOptions = true
        errorMessage = nil
        defer { isLoadingOptions = false }
        do {
            let payload = try await SalespersonMobileAPI.shared.fetchProspectingOptions()
            markets = payload.markets
            industries = payload.industries
            recentRuns = payload.recentRuns
            selectedIndustryId = matchingIndustryId(for: industry)
        } catch {
            errorMessage = error.localizedDescription
            markets = []
            industries = []
            recentRuns = []
        }
    }

    func selectIndustry(_ id: UUID?) {
        selectedIndustryId = id
        guard let id, let selected = industries.first(where: { $0.id == id }) else { return }
        industry = selected.name
        relatedTerms = selected.defaultTerms.joined(separator: ", ")
        realEstateTarget = "individual_agents"
    }

    func selectIndustry(named name: String) {
        guard let selected = industryOptions.first(where: { $0.name == name }) else {
            selectedIndustryId = nil
            industry = ""
            relatedTerms = ""
            return
        }
        industry = selected.name
        relatedTerms = selected.defaultTerms.joined(separator: ", ")
        selectedIndustryId = matchingIndustryId(for: selected.name)
        realEstateTarget = "individual_agents"
    }

    func selectCountry(_ value: String) {
        countryCode = value
        let market = findMarket(city: city, countryCode: value)
        selectedMarketId = market?.id
        region = market?.region ?? ""
        Task { await refreshCitySuggestions(for: city) }
    }

    func selectCitySuggestion(_ suggestion: CitySuggestion) {
        let market = findMarket(city: suggestion.city, countryCode: suggestion.countryCode)
        city = suggestion.city
        countryCode = suggestion.countryCode.isEmpty ? countryCode : suggestion.countryCode
        region = market?.region ?? suggestion.region
        selectedMarketId = market?.id
        citySuggestions = []
    }

    func refreshCitySuggestions(for query: String) async {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 2 else {
            citySuggestions = []
            cityAutocompleteLoading = false
            return
        }
        cityAutocompleteLoading = true
        defer { cityAutocompleteLoading = false }
        do {
            let results = try await Self.searchCities(query: clean, selectedCountryCode: countryCode)
            guard Self.normalizeInput(city) == Self.normalizeInput(clean) else { return }
            citySuggestions = results
        } catch {
            citySuggestions = []
        }
    }

    func runSearch(listName: String? = nil) async -> Bool {
        guard canSubmit else { return false }
        isSearching = true
        errorMessage = nil
        statusMessage = nil
        csvURL = nil
        defer { isSearching = false }

        do {
            let payload = try await SalespersonMobileAPI.shared.searchPlacesLeads(
                city: city,
                industry: industry,
                countryCode: countryCode,
                region: region,
                relatedTerms: resolvedRelatedTerms(),
                marketId: selectedMarketId,
                industryId: selectedIndustryId,
                leadIntent: resolvedLeadIntent(),
                listName: listName
            )
            prospects = payload.prospects
            summary = payload
            let foundLabel = leadIntentLabel()
            var researchMessage = ""
            if researchModeEnabled, let listId = payload.savedList?.listId?.nilIfEmpty {
                do {
                    let research = try await SalespersonMobileAPI.shared.startCompanyResearch(
                        listId: listId,
                        refreshAll: false
                    )
                    let queuedCount = research.queued ?? research.batch.requestedCount
                    let skippedCount = research.skipped ?? research.batch.skippedCount
                    if queuedCount > 0 {
                        researchMessage = " Research queued for \(queuedCount) companies."
                    } else if skippedCount > 0 {
                        researchMessage = " Company research is already current."
                    }
                } catch {
                    researchMessage = " The list was saved, but research could not start: \(error.localizedDescription)"
                }
            } else if researchModeEnabled {
                researchMessage = " Research could not start because the lead list was not created."
            }
            if let saved = payload.savedList {
                statusMessage = "\(payload.prospects.count) \(foundLabel) found. Saved \"\(saved.listName)\" with \(saved.contactCount) list rows and \(saved.dialerLeadIds.count) dialer rows.\(researchMessage)"
            } else {
                statusMessage = "\(payload.prospects.count) \(foundLabel) found."
            }
            await loadOptions()
            return true
        } catch let error as URLError where error.code == .timedOut {
            errorMessage = "Lead generation is taking longer than expected and may still finish. Check Lists before trying again."
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func copyCallSheet() {
        guard !prospects.isEmpty else {
            statusMessage = "Run a search first."
            return
        }
        UIPasteboard.general.string = Self.buildCallSheet(prospects)
        statusMessage = "Call sheet copied."
    }

    func copyLead(_ lead: PlacesLead) {
        UIPasteboard.general.string = Self.buildCallSheet([lead])
        statusMessage = "\(lead.name) copied."
    }

    func prepareCSVShare() {
        guard !prospects.isEmpty else {
            statusMessage = "Run a search first."
            return
        }
        do {
            let csv = Self.buildPlacesCSV(prospects)
            let fileName = "places-leads-\(Self.slug(city))-\(Self.dateSlug()).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            csvURL = url
            statusMessage = "CSV ready."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func findMarket(city: String, countryCode: String) -> ProspectMarket? {
        markets.first {
            Self.normalizeInput($0.city) == Self.normalizeInput(city) && $0.countryCode == countryCode
        }
    }

    private func matchingIndustryId(for name: String) -> UUID? {
        let normalizedName = Self.normalizeInput(name)
        guard !normalizedName.isEmpty else { return nil }
        return industries.first { Self.normalizeInput($0.name) == normalizedName }?.id
    }

    private func resolvedRelatedTerms() -> [String] {
        let typed = relatedTerms
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let safeTerms = realEstateMode && realEstateTarget == "individual_agents"
            ? Self.filterIndividualAgentTerms(typed)
            : typed
        let teamTerms = realEstateMode && realEstateTarget == "teams"
            ? ["real estate team", "realtor team", "real estate group", "realtor group"]
            : []
        let officeTerms = realEstateMode && realEstateTarget == "offices"
            ? ["real estate brokerage", "real estate office", "realtor office", "realty brokerage"]
            : []
        return Array(Self.uniqueTerms(teamTerms + officeTerms + safeTerms).prefix(12))
    }

    private func resolvedLeadIntent() -> String {
        guard realEstateMode else { return "generic" }
        switch realEstateTarget {
        case "teams": return "real_estate_teams"
        case "individual_agents": return "real_estate_individual_agents"
        case "offices": return "real_estate_brokerages"
        default: return "real_estate_agents"
        }
    }

    private func leadIntentLabel() -> String {
        switch resolvedLeadIntent() {
        case "real_estate_teams": return "team leads"
        case "real_estate_brokerages": return "office leads"
        case "real_estate_individual_agents": return "individual agent leads"
        case "real_estate_agents": return "agent leads"
        default: return "leads"
        }
    }

    private static func normalizeInput(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRealEstateIndustry(_ value: String) -> Bool {
        let normalized = normalizeInput(value)
        return normalized.contains("real estate") ||
            normalized.contains("realtor") ||
            normalized.contains("brokerage") ||
            normalized.contains("property agent")
    }

    private static func uniqueTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for term in terms {
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizeInput(clean)
            guard !clean.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(clean)
        }
        return output
    }

    private static func filterIndividualAgentTerms(_ terms: [String]) -> [String] {
        terms.filter { term in
            let normalized = normalizeInput(term)
            return !["team", "group", "collective", "associates", "partners", "brokerage", "office"].contains { signal in
                normalized.contains(signal)
            }
        }
    }

    private static func searchCities(query: String, selectedCountryCode: String) async throws -> [CitySuggestion] {
        let token = Config.mapboxAccessToken
        guard !token.isEmpty else { return [] }
        let supportedCountries = ["us", "ca", "nz", "au", "za"]
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.mapbox.com"
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        components.percentEncodedPath = "/geocoding/v5/mapbox.places/\(encodedQuery).json"
        components.queryItems = [
            URLQueryItem(name: "access_token", value: token),
            URLQueryItem(name: "types", value: "place,locality"),
            URLQueryItem(name: "autocomplete", value: "true"),
            URLQueryItem(name: "fuzzyMatch", value: "true"),
            URLQueryItem(name: "limit", value: "8"),
            URLQueryItem(name: "country", value: supportedCountries.joined(separator: ",")),
            URLQueryItem(name: "language", value: "en"),
        ]
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        struct Response: Decodable {
            struct Feature: Decodable {
                struct Context: Decodable {
                    let id: String
                    let text: String?
                    let shortCode: String?

                    enum CodingKeys: String, CodingKey {
                        case id
                        case text
                        case shortCode = "short_code"
                    }
                }

                let id: String
                let text: String
                let placeName: String
                let context: [Context]?

                enum CodingKeys: String, CodingKey {
                    case id
                    case text
                    case context
                    case placeName = "place_name"
                }
            }

            let features: [Feature]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let queryTokens = Set(normalizeInput(query).split(separator: " ").map(String.init))
        let selectedCountry = selectedCountryCode.uppercased()
        return decoded.features.map { feature in
            let region = feature.context?.first { $0.id.hasPrefix("region.") }?.text ?? ""
            let country = normalizedCountryCode(feature.context?.first { $0.id.hasPrefix("country.") }?.shortCode)
            let city = feature.text.isEmpty ? feature.placeName.split(separator: ",").first.map(String.init) ?? "" : feature.text
            return CitySuggestion(
                id: feature.id,
                city: city,
                region: region,
                countryCode: country,
                label: [city, region, country].filter { !$0.isEmpty }.joined(separator: ", ")
            )
        }
        .sorted { lhs, rhs in
            citySuggestionScore(lhs, queryTokens: queryTokens, selectedCountry: selectedCountry) >
                citySuggestionScore(rhs, queryTokens: queryTokens, selectedCountry: selectedCountry)
        }
    }

    private static func normalizedCountryCode(_ value: String?) -> String {
        let code = value?
            .split(separator: "-")
            .first
            .map(String.init)?
            .uppercased() ?? ""
        return code == "UK" ? "GB" : code
    }

    private static func citySuggestionScore(
        _ suggestion: CitySuggestion,
        queryTokens: Set<String>,
        selectedCountry: String
    ) -> Int {
        let city = normalizeInput(suggestion.city)
        let region = normalizeInput(suggestion.region)
        let country = suggestion.countryCode.uppercased()
        var score = 0
        if country == selectedCountry { score += 10 }
        if queryTokens.contains(country.lowercased()) { score += 30 }
        if queryTokens.contains("canada"), country == "CA" { score += 30 }
        if queryTokens.contains("usa") || queryTokens.contains("us"), country == "US" { score += 30 }
        if queryTokens.contains("australia"), country == "AU" { score += 30 }
        if queryTokens.contains("new"), queryTokens.contains("zealand"), country == "NZ" { score += 30 }
        if queryTokens.contains("south"), queryTokens.contains("africa"), country == "ZA" { score += 30 }
        if queryTokens.contains(where: { region.contains($0) }) { score += 20 }
        if queryTokens.contains(where: { city.contains($0) }) { score += 5 }
        return score
    }

    private static func buildCallSheet(_ prospects: [PlacesLead]) -> String {
        prospects.enumerated().map { index, lead in
            [
                "\(index + 1). \(lead.name)",
                lead.phone.map { "Phone: \($0)" },
                lead.website.map { "Website: \($0)" },
                lead.formattedAddress.map { "Address: \($0)" },
                lead.googleMapsUrl.map { "Maps: \($0)" },
                lead.placeId.map { "Place ID: \($0)" },
            ]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    private static func buildPlacesCSV(_ prospects: [PlacesLead]) -> String {
        let headers = [
            "place_id", "name", "city", "industry", "phone", "website", "website_domain", "address",
            "google_maps_url", "rating", "user_rating_count", "primary_type", "business_status",
            "confidence_score", "lead_category", "evidence_summary", "source_query"
        ]
        let rows: [[String]] = prospects.map { lead in
            [
                lead.placeId ?? "",
                lead.name,
                lead.city ?? "",
                lead.industry ?? "",
                lead.phone ?? "",
                lead.website ?? "",
                lead.websiteDomain ?? "",
                lead.formattedAddress ?? "",
                lead.googleMapsUrl ?? "",
                lead.rating.map { String($0) } ?? "",
                lead.userRatingCount.map { String($0) } ?? "",
                lead.primaryType ?? "",
                lead.businessStatus ?? "",
                String(lead.confidenceScore),
                lead.leadCategory ?? "",
                lead.evidenceSummary ?? "",
                lead.query ?? "",
            ]
        }
        return ([headers] + rows).map { row in
            row.map { csvEscape($0) }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.range(of: #"[",\n\r]"#, options: .regularExpression) != nil else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func slug(_ value: String) -> String {
        normalizeInput(value).replacingOccurrences(of: " ", with: "-").nilIfEmpty ?? "city"
    }

    private static func dateSlug() -> String {
        String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    }
}

enum SalespersonLeadsMode: Equatable {
    case contacts
    case lists
}

struct SalespersonLeadsView: View {
    @StateObject private var viewModel = SalespersonLeadsViewModel()
    @EnvironmentObject private var uiState: AppUIState
    @State private var showScraper = false
    @State private var showNewContact = false
    @State private var progressList: SalespersonLeadListGroup?
    @State private var scraperSavedList: SavedScraperList?
    @State private var selectedMode: SalespersonLeadsMode
    @State private var isSearchVisible = false
    @FocusState private var isSearchFocused: Bool

    init(mode: SalespersonLeadsMode = .lists) {
        _selectedMode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scraperDialerBanner
                contactsListsSwitcher
                if isSearchVisible {
                    salespersonListSearchBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if selectedMode == .contacts {
                    salespersonContactsList
                } else {
                    salespersonLeadsList
                }
            }
            .background(Color.bg.ignoresSafeArea())
            .animation(.easeInOut(duration: 0.2), value: isSearchVisible)
            .navigationTitle(selectedMode == .contacts ? "Contacts" : "Lead Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selectedMode == .contacts {
                        Button {
                            showNewContact = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .accessibilityLabel("Add contact")
                    } else {
                        Button {
                            showScraper = true
                        } label: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .accessibilityLabel("Create lead list")
                    }

                    Button {
                        withAnimation {
                            isSearchVisible.toggle()
                        }
                        if isSearchVisible {
                            isSearchFocused = true
                        } else {
                            viewModel.searchText = ""
                            isSearchFocused = false
                        }
                    } label: {
                        Image(systemName: isSearchVisible ? "xmark" : "magnifyingglass")
                    }
                    .accessibilityLabel(isSearchVisible ? "Close search" : "Search")
                }
            }
            .refreshable {
                await viewModel.load()
                applyPendingLeadListSelection()
            }
            .task {
                await viewModel.load()
                applyPendingLeadListSelection()
            }
            .onChange(of: uiState.pendingSalespersonLeadListSelection) { _, _ in
                applyPendingLeadListSelection()
            }
            .onChange(of: uiState.selectedTabIndex) { _, selectedTabIndex in
                guard selectedTabIndex == 2 else { return }
                Task { await viewModel.load() }
            }
            .navigationDestination(for: SalespersonLeadMasterRow.self) { lead in
                SalespersonLeadDetailView(lead: lead) { updatedLead in
                    viewModel.replaceLead(updatedLead)
                }
            }
            .fullScreenCover(isPresented: $showScraper, onDismiss: {
                Task { await viewModel.load() }
            }) {
                SalespersonLeadScraperView(
                    onOpenLeads: { savedList in
                        scraperSavedList = savedList
                        showScraper = false
                        Task { await viewModel.load() }
                    },
                    onOpenDialler: { savedList in
                        scraperSavedList = savedList
                        showScraper = false
                        uiState.openSalespersonDiallerList(id: savedList?.listId, title: savedList?.listName)
                    }
                )
            }
            .sheet(isPresented: $showNewContact) {
                SalespersonNewContactSheet { contact in
                    viewModel.addLead(contact)
                }
            }
            .sheet(item: $progressList) { list in
                SalespersonLeadListProgressSheet(list: list)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(selectedMode == .contacts ? "Contacts" : "Lists", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.errorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func applyPendingLeadListSelection() {
        guard let pending = uiState.pendingSalespersonLeadListSelection else { return }
        selectedMode = .lists
        _ = viewModel.openListMatching(id: pending.listId, title: pending.listTitle)
        uiState.pendingSalespersonLeadListSelection = nil
    }

    private var contactsListsSwitcher: some View {
        HStack(spacing: 0) {
            modeButton(title: "Contacts", mode: .contacts)
            modeButton(title: "Lists", mode: .lists)
        }
        .padding(.horizontal, 16)
        .background(Color.bg)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func modeButton(title: String, mode: SalespersonLeadsMode) -> some View {
        Button {
            guard selectedMode != mode else { return }
            selectedMode = mode
            viewModel.searchText = ""
            isSearchFocused = false
        } label: {
            VStack(spacing: 9) {
                Text(title)
                    .font(.system(size: 16, weight: selectedMode == mode ? .semibold : .medium))
                    .foregroundStyle(selectedMode == mode ? Color.text : Color.muted)
                    .frame(maxWidth: .infinity)

                Capsule()
                    .fill(selectedMode == mode ? Color.red : Color.clear)
                    .frame(height: 3)
            }
            .padding(.top, 12)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
    }

    @ViewBuilder
    private var scraperDialerBanner: some View {
        if let saved = scraperSavedList {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(saved.listName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                    Text("\(saved.contactCount) leads saved. \(saved.dialerImportedCount + saved.dialerSkippedCount) ready for dialer.")
                        .font(.system(size: 12))
                        .foregroundColor(.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button {
                    scraperSavedList = nil
                    uiState.selectedTabIndex = 3
                } label: {
                    Label("Add to Dialer", systemImage: "phone.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.10))
        }
    }

    private var salespersonListSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.muted)
                .font(.system(size: 16))
            TextField(searchPlaceholder, text: $viewModel.searchText)
                .font(.system(size: 15))
                .foregroundColor(.text)
                .focused($isSearchFocused)
                .submitLabel(.search)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchPlaceholder: String {
        if selectedMode == .contacts {
            return "Search contacts..."
        }
        return viewModel.selectedList == nil ? "Search lists..." : "Search leads in this list..."
    }

    @ViewBuilder
    private var salespersonContactsList: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredLeads.isEmpty {
            ContentUnavailableView(
                viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No contacts" : "No matching contacts",
                systemImage: "person.crop.circle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredLeads) { lead in
                        NavigationLink(value: lead) {
                            SalespersonLeadRow(lead: lead, kind: .contact)
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 60)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var salespersonLeadsList: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let selectedList = viewModel.selectedList {
            VStack(spacing: 0) {
                selectedListHeader(selectedList)
                if viewModel.selectedListLeads.isEmpty {
                    ContentUnavailableView(
                        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No leads in this list" : "No matching leads",
                        systemImage: "person.text.rectangle"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.selectedListLeads) { lead in
                                NavigationLink(value: lead) {
                                    SalespersonLeadRow(lead: lead, kind: .listLead)
                                }
                                .buttonStyle(.plain)
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        } else if viewModel.filteredLeadLists.isEmpty {
            ContentUnavailableView(
                viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No lead lists" : "No matching lists",
                systemImage: "list.bullet.rectangle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.filteredLeadLists) { list in
                        Button {
                            viewModel.openList(list)
                        } label: {
                            SalespersonLeadListSummaryRow(list: list)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    private func selectedListHeader(_ list: SalespersonLeadListGroup) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    viewModel.closeList()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(list.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(list.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                Button {
                    uiState.openSalespersonDiallerList(id: list.id, title: list.title)
                } label: {
                    Label("Dial", systemImage: "phone.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(list.dialableCount == 0)

                Button {
                    progressList = list
                } label: {
                    Label("Progress", systemImage: "chart.bar.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

private struct SalespersonLeadListProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    let list: SalespersonLeadListGroup

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(list.attemptedLeadCount) of \(list.dialableCount) leads attempted")
                                .font(.headline)
                            Spacer(minLength: 12)
                            Text(list.completionFraction, format: .percent.precision(.fractionLength(0)))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.red)
                        }

                        ProgressView(value: list.completionFraction)
                            .tint(.red)
                    }
                    .padding(16)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        progressMetric(
                            value: list.callsMade.formatted(),
                            label: "Calls made",
                            systemImage: "phone.arrow.up.right.fill",
                            tint: .red
                        )
                        progressMetric(
                            value: list.connectedCount.formatted(),
                            label: "Connected",
                            systemImage: "phone.connection.fill",
                            tint: .green
                        )
                        progressMetric(
                            value: list.connectionRate.formatted(.percent.precision(.fractionLength(0))),
                            label: "Connection rate",
                            systemImage: "chart.line.uptrend.xyaxis",
                            tint: .blue
                        )
                        progressMetric(
                            value: list.remainingToCall.formatted(),
                            label: "Remaining",
                            systemImage: "person.crop.circle.badge.clock",
                            tint: .orange
                        )
                    }

                    Text("Calls made includes repeat attempts. Connected includes calls marked Interested, Connected, or Appointment Set.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("List Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func progressMetric(
        value: String,
        label: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.text)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(14)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SalespersonLeadListSummaryRow: View {
    let list: SalespersonLeadListGroup

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 34, height: 34)
                .background(Color.red.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(list.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let location = list.locationLine {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(list.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.bgSecondary)
                    .clipShape(Capsule())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SalespersonNewContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var company = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var contactPhoto: UIImage?
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onCreated: (SalespersonLeadMasterRow) -> Void

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photo (optional)") {
                    HStack(spacing: 16) {
                        Group {
                            if let contactPhoto {
                                Image(uiImage: contactPhoto)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundStyle(Color.muted)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .background(Color.gray.opacity(0.12))
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 10) {
                            Button("Choose Photo") { showPhotoLibrary = true }
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button("Take Photo") { showCamera = true }
                            }
                            if contactPhoto != nil {
                                Button("Remove Photo", role: .destructive) { contactPhoto = nil }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Contact") {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                    TextField("Last name", text: $lastName)
                        .textContentType(.familyName)
                        .textInputAutocapitalization(.words)
                    TextField("Company (optional)", text: $company)
                        .textContentType(.organizationName)
                        .textInputAutocapitalization(.words)
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    TextField("Address", text: $address)
                        .textContentType(.fullStreetAddress)
                }

                Section("Notes") {
                    TextField("Add notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(trimmedFirstName.isEmpty || trimmedLastName.isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("New Contact", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unable to create contact.")
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(sourceType: .photoLibrary) { contactPhoto = $0 }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera) { contactPhoto = $0 }
            }
        }
    }

    private func save() async {
        guard !trimmedFirstName.isEmpty, !trimmedLastName.isEmpty, !isSaving else { return }
        guard AuthManager.shared.user != nil else {
            errorMessage = "Sign in to create a contact."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let photoData = contactPhoto?.jpegData(compressionQuality: 0.82)
            let contact = try await SalespersonMobileAPI.shared.createSalespersonContact(
                firstName: trimmedFirstName,
                lastName: trimmedLastName,
                company: company.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                photoData: photoData
            )
            onCreated(contact)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SalespersonContactPhotoView: View {
    let path: String?
    let size: CGFloat
    @State private var signedURL: URL?

    var body: some View {
        Group {
            if let signedURL {
                AsyncImage(url: signedURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder
                    } else {
                        ProgressView()
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.gray.opacity(0.12))
        .clipShape(Circle())
        .task(id: path) {
            signedURL = nil
            guard let path = path?.nilIfEmpty else { return }
            signedURL = try? await SupabaseManager.shared.client.storage
                .from("contact-photos")
                .createSignedURL(path: path, expiresIn: 60 * 60)
        }
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.red.opacity(0.85))
            .padding(size * 0.12)
    }
}

private enum SalespersonLeadRowKind: Equatable {
    case contact
    case listLead
}

private struct SalespersonLeadRow: View {
    let lead: SalespersonLeadMasterRow
    let kind: SalespersonLeadRowKind

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if kind == .contact {
                SalespersonContactPhotoView(path: lead.metadata?.photoPath, size: 40)
            } else {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.text)
                    .lineLimit(1)

                if let address = lead.address?.nilIfEmpty {
                    Text(address)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.text)
                        .lineLimit(1)
                }

                if let company = lead.company?.nilIfEmpty {
                    Text(company)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if kind == .listLead {
                Text("LEAD")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(height: 72)
        .contentShape(Rectangle())
    }
}

private struct SalespersonDiallerDateGroup: Identifiable {
    let id: String
    let title: String
    let leads: [SalespersonDiallerLead]
    let createdAt: Date
    private static let noDate = Date(timeIntervalSince1970: 0)

    static func makeGroups(from leads: [SalespersonDiallerLead]) -> [SalespersonDiallerDateGroup] {
        let sorted = leads.sorted {
            ($0.createdAt ?? noDate) > ($1.createdAt ?? noDate)
        }
        let calendar = Calendar.current
        let groups = Dictionary(grouping: sorted) { lead in
            guard let createdAt = lead.createdAt else { return noDate }
            return calendar.startOfDay(for: createdAt)
        }

        return groups.map { day, leads in
            let sortedLeads = leads.sorted {
                ($0.createdAt ?? noDate) > ($1.createdAt ?? noDate)
            }
            return SalespersonDiallerDateGroup(
                id: "dialler-day-\(day.timeIntervalSince1970)",
                title: title(for: day),
                leads: sortedLeads,
                createdAt: sortedLeads.compactMap(\.createdAt).max() ?? day
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private static func title(for day: Date) -> String {
        guard day != noDate else { return "No date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct SalespersonDiallerQueueRow: View {
    let lead: SalespersonDiallerLead
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isSelected ? "phone.circle.fill" : "person.text.rectangle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isSelected ? .red : .accent)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayBusinessName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(1)

                Text(lead.phone)
                    .font(.system(size: 15))
                    .foregroundColor(.text)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(detailLine)
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if lead.isStarred == true {
                    Image(systemName: "star.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
                if lead.latestCallRecording?.available == true {
                    Image(systemName: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.muted)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var detailLine: String {
        [
            lead.createdAt.map { $0.formatted(date: .abbreviated, time: .shortened) },
            lead.email?.nilIfEmpty,
            lead.websiteDomain?.nilIfEmpty ?? lead.website?.nilIfEmpty
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }
}

private struct SalespersonDiallerListSummaryRow: View {
    let list: SalespersonDiallerListGroup

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "phone.badge.waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 34, height: 34)
                .background(Color.red.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(list.subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text("\(list.dialableCount)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.bgSecondary)
                    .clipShape(Capsule())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private enum SalespersonContactComposerChannel: String, Identifiable {
    case sms
    case email

    var id: String { rawValue }
    var title: String { self == .sms ? "New Message" : "New Email" }
}

private enum SalespersonDemoLink {
    static let url = URL(string: "https://wolfgrid.app/demo100")!
}

// Copy shared with backend-api-routes/lib/email/demo.ts. Sending this template
// uses the existing web endpoint so its HTML and configured sender stay shared.
private enum SalespersonDemoEmailTemplate {
    static let title = "WolfGrid Demo100"
    static let subject = "Your WolfGrid demo"

    static func body(recipientName: String?) -> String {
        let name = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return """
        Hi \(name ?? "there"),

        Here’s the WolfGrid demo. Take a look at how you can plan your territory, organize leads, and keep your team’s follow-up in one place.

        Watch the demo: \(SalespersonDemoLink.url.absoluteString)

        Have a question or want to talk through how WolfGrid could fit your business? Just reply to this email — I’m happy to help.
        """
    }

    static func matches(subject: String, body: String, recipientName: String?) -> Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines) == self.subject
            && body.trimmingCharacters(in: .whitespacesAndNewlines) == self.body(recipientName: recipientName)
    }
}

private enum SalespersonOutreachTemplate: String, Identifiable {
    case individualAgent
    case realEstateTeam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individualAgent: "Individual Agent Demo"
        case .realEstateTeam: "Real Estate Team Demo"
        }
    }

    var emailSubject: String {
        switch self {
        case .individualAgent: "The quick WolfGrid demo I promised"
        case .realEstateTeam: "A quick WolfGrid demo for your team"
        }
    }

    func smsBody(recipientName: String?, senderName: String) -> String {
        let greetingName = Self.firstName(from: recipientName)
        switch self {
        case .individualAgent:
            return """
            Hey \(greetingName), it’s \(senderName) from WolfGrid. Here’s that quick demo I mentioned:
            \(SalespersonDemoLink.url.absoluteString)

            It shows you how to create your first 3D prospecting map. You can try it free afterward—no credit card needed. Let me know what you think!
            """
        case .realEstateTeam:
            return """
            Hey \(greetingName), it’s \(senderName) from WolfGrid. Here’s the quick real estate team demo I mentioned:
            \(SalespersonDemoLink.url.absoluteString)

            It gives you a quick look at how WolfGrid could work for your team. You can create a map free afterward—no credit card needed. Let me know what you think!
            """
        }
    }

    func emailBody(recipientName: String?) -> String {
        let greetingName = Self.firstName(from: recipientName)
        switch self {
        case .individualAgent:
            return """
            Hi \(greetingName),

            Thanks for taking my call earlier. I completely understand that now may not be the right time for a meeting.

            Here’s a quick demo showing how to create a 3D prospecting map with WolfGrid:

            \(SalespersonDemoLink.url.absoluteString)

            If it looks useful, you can create your first map free afterward—no credit card or commitment required.

            If you have any questions, just reply to this email.
            """
        case .realEstateTeam:
            return """
            Hi \(greetingName),

            Thanks for speaking with me earlier. I understand that scheduling a meeting may not make sense right now.

            Here’s a quick demo showing how WolfGrid works for real estate teams:

            \(SalespersonDemoLink.url.absoluteString)

            You can also create your first 3D prospecting map free afterward—no credit card or commitment required.

            If it looks like something your agents could use, I’d be happy to answer any questions or show you how it could fit your team.
            """
        }
    }

    private static func firstName(from name: String?) -> String {
        let firstName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)
        return firstName?.nilIfEmpty ?? "there"
    }
}

private struct SalespersonLeadDetailView: View {
    @State private var lead: SalespersonLeadMasterRow
    @State private var name: String
    @State private var company: String
    @State private var phone: String
    @State private var email: String
    @State private var notes: String
    @State private var isEditing = false
    @State private var integrations: [UserIntegration] = []
    @State private var composer: SalespersonContactComposerChannel?
    @State private var isSaving = false
    @State private var isCreatingContact = false
    @State private var isCalling = false
    @State private var isPushingToCRM = false
    @State private var didPushToCRM = false
    @State private var showCallConfirmation = false
    @State private var showSyncSettings = false
    @State private var showShareSheet = false
    @State private var showCompanyResearch = false
    @State private var shareItems: [Any] = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @ObservedObject private var voice = SalespersonVoiceCallService.shared
    @Environment(\.openURL) private var openURL
    let onLeadUpdated: (SalespersonLeadMasterRow) -> Void

    init(lead: SalespersonLeadMasterRow, onLeadUpdated: @escaping (SalespersonLeadMasterRow) -> Void) {
        _lead = State(initialValue: lead)
        _name = State(initialValue: lead.name)
        _company = State(initialValue: lead.company ?? "")
        _phone = State(initialValue: lead.phone ?? "")
        _email = State(initialValue: lead.email ?? "")
        _notes = State(initialValue: lead.notes ?? "")
        self.onLeadUpdated = onLeadUpdated
    }

    private var hasEdits: Bool {
        name != lead.name || company != (lead.company ?? "") || phone != (lead.phone ?? "") ||
        email != (lead.email ?? "") || notes != (lead.notes ?? "")
    }

    private var validPhone: String? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.filter(\.isNumber).count >= 8 ? trimmed : nil
    }

    private var validEmail: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".") ? trimmed : nil
    }

    private var address: String? { lead.address?.nilIfEmpty ?? lead.locationLine }
    private var isContact: Bool { lead.isContact }
    private var connectedProvider: IntegrationProvider? {
        integrations.first {
            $0.isConnected && [.fub, .boldtrail, .hubspot].contains($0.provider)
        }?.provider
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                Button {
                    showCompanyResearch = true
                } label: {
                    Label("Research Company", systemImage: "sparkle.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                contactFields
                addressSection
                metadataSection
                crmSection
                shareButton
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.gray.opacity(0.15), Color.clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()
        )
        .navigationTitle(isContact ? "Contact" : "Lead")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editControls
        }
        .task { await loadIntegrations() }
        .confirmationDialog(
            "Call \(name.nilIfEmpty ?? lead.displayName)?",
            isPresented: $showCallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Call with WolfGrid") { Task { await call() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(validPhone ?? "")
        }
        .sheet(item: $composer) { channel in
            SalespersonContactComposerSheet(
                channel: channel,
                leadId: lead.id.uuidString,
                contactId: lead.salesContactId,
                recipient: channel == .sms ? phone : email,
                recipientName: name.nilIfEmpty ?? lead.displayName
            ) { statusMessage = $0 }
        }
        .sheet(isPresented: $showSyncSettings) { IntegrationsView() }
        .sheet(isPresented: $showShareSheet) { SalespersonShareSheet(activityItems: shareItems) }
        .sheet(isPresented: $showCompanyResearch) { SalespersonCompanyResearchSheet(lead: lead) }
        .alert(isContact ? "Contact" : "Lead", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
    }

    private var headerSection: some View {
        VStack(spacing: 36) {
            if isContact {
                SalespersonContactPhotoView(path: lead.metadata?.photoPath, size: 104)
            } else {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 104, height: 104)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.text)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .allowsHitTesting(isEditing)

            HStack(spacing: 24) {
                actionButton("message.fill", label: "Message", enabled: validPhone != nil) { composer = .sms }
                actionButton(isCalling ? "hourglass" : "phone.fill", label: "Call", enabled: validPhone != nil && !isCalling) {
                    showCallConfirmation = true
                }
                actionButton("envelope.fill", label: "Email", enabled: validEmail != nil) { composer = .email }
                actionButton("mappin.circle.fill", label: "Maps", enabled: address != nil) { openMaps() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func actionButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(enabled ? Color.white : Color.gray)
                .frame(width: 50, height: 50)
                .background(enabled ? Color.red : Color.gray.opacity(0.3))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var contactFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            contactField("building.2.fill", label: "Company", text: $company, placeholder: "Company (optional)", keyboard: .default)
            Divider().background(Color.border).padding(.vertical, 12)
            contactField("phone.fill", label: "Phone", text: $phone, placeholder: "Phone number", keyboard: .phonePad)
            Divider().background(Color.border).padding(.vertical, 12)
            contactField("envelope.fill", label: "Email", text: $email, placeholder: "Email", keyboard: .emailAddress)
            Divider().background(Color.border).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.muted)
                TextEditor(text: $notes)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88)
                    .padding(10)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Add notes…")
                                .foregroundStyle(Color.muted)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    }
                    .allowsHitTesting(isEditing)
            }
        }
    }

    private func contactField(
        _ icon: String,
        label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Color.muted).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption.weight(.medium)).foregroundStyle(Color.muted)
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                    .allowsHitTesting(isEditing)
            }
        }
    }

    @ViewBuilder
    private var editControls: some View {
        VStack(spacing: 0) {
            Divider()
            if isEditing {
                HStack(spacing: 12) {
                    Button("Cancel") { cancelEditing() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save Changes")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(hasEdits ? Color.red : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!hasEdits || isSaving)
                }
            } else if isContact {
                Button {
                    statusMessage = nil
                    isEditing = true
                } label: {
                    Label("Edit Contact", systemImage: "pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                VStack(spacing: 10) {
                    Button {
                        Task { await createContact() }
                    } label: {
                        Group {
                            if isCreatingContact {
                                ProgressView().tint(.white)
                            } else {
                                Label("Create Contact", systemImage: "person.crop.circle.badge.plus")
                            }
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isCreatingContact)

                    Button {
                        statusMessage = nil
                        isEditing = true
                    } label: {
                        Label("Edit Lead", systemImage: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.gray.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isCreatingContact)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func cancelEditing() {
        name = lead.name
        company = lead.company ?? ""
        phone = lead.phone ?? ""
        email = lead.email ?? ""
        notes = lead.notes ?? ""
        isEditing = false
    }

    @ViewBuilder
    private var addressSection: some View {
        if let address {
            VStack(alignment: .leading, spacing: 8) {
                Label("Address", systemImage: "mappin.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.muted)
                Text(address).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.text)
                Button("Open in Maps") { openMaps() }.foregroundStyle(Color.red)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isContact ? "Contact" : "Lead from list", systemImage: isContact ? "person.crop.circle.fill" : "person.crop.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isContact ? Color.green : Color.orange)
            Text("Status: \(lead.leadState.replacingOccurrences(of: "_", with: " ").capitalized)")
            Text("Source: \(lead.sourceLabel)")
            Text("Added \(lead.createdAt.formatted(date: .abbreviated, time: .shortened))")
            if let website = lead.website?.nilIfEmpty {
                Button(website) { openExternal(website) }.foregroundStyle(Color.red)
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(Color.muted)
    }

    private var crmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let provider = connectedProvider {
                Label("Connected to \(provider.displayName)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                Button { Task { await pushToCRM() } } label: {
                    if isPushingToCRM {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(didPushToCRM ? "Pushed" : "Push to CRM", systemImage: didPushToCRM ? "checkmark.circle.fill" : "arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isPushingToCRM)
            } else {
                Text("Connect a CRM to sync this \(isContact ? "contact" : "lead") to your office.")
                    .font(.system(size: 14)).foregroundStyle(Color.muted)
                Button("Connect CRM →") { showSyncSettings = true }.foregroundStyle(Color.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var shareButton: some View {
        Button { share() } label: {
            Label(isContact ? "Share Contact" : "Share Lead", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        guard hasEdits, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await SalespersonMobileAPI.shared.updateSalespersonLead(
                id: lead.id, name: name, company: company, phone: phone, email: email, notes: notes
            )
            lead = updated
            name = updated.name
            company = updated.company ?? ""
            phone = updated.phone ?? ""
            email = updated.email ?? ""
            notes = updated.notes ?? ""
            onLeadUpdated(updated)
            statusMessage = isContact ? "Contact saved." : "Lead saved."
            isEditing = false
        } catch { errorMessage = error.localizedDescription }
    }

    private func createContact() async {
        guard !isContact, !isCreatingContact else { return }
        isCreatingContact = true
        defer { isCreatingContact = false }
        do {
            let updated = try await SalespersonMobileAPI.shared.createSalespersonContact(from: lead)
            lead = updated
            name = updated.name
            company = updated.company ?? ""
            phone = updated.phone ?? ""
            email = updated.email ?? ""
            notes = updated.notes ?? ""
            onLeadUpdated(updated)
            statusMessage = "Contact created."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func call() async {
        guard let validPhone, !isCalling else { return }
        isCalling = true
        defer { isCalling = false }
        let diallerLead = SalespersonDiallerLead(
            id: lead.id, name: name.nilIfEmpty ?? lead.displayName, phone: validPhone,
            company: company.nilIfEmpty, email: email.nilIfEmpty, website: lead.website,
            websiteDomain: lead.websiteHost, listId: lead.listId, listName: lead.listName,
            latestCallRecording: nil, isStarred: false, disposition: lead.disposition,
            notes: notes.nilIfEmpty, calledAt: nil, createdAt: lead.createdAt
        )
        do {
            voice.endActiveCall()
            let call = try await SalespersonMobileAPI.shared.startDiallerCall(lead: diallerLead)
            try await voice.startOutboundCall(
                label: name.nilIfEmpty ?? lead.displayName,
                callRequestId: call.callRequestId,
                destinationNumber: call.toNumber,
                fromNumber: call.fromNumber
            )
            statusMessage = "Calling \(name.nilIfEmpty ?? lead.displayName)."
        } catch { errorMessage = error.localizedDescription }
    }

    private func openMaps() {
        guard let address,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        openURL(url)
    }

    private func openExternal(_ raw: String) {
        guard let url = URL(string: raw.contains("://") ? raw : "https://\(raw)") else { return }
        openURL(url)
    }

    private func loadIntegrations() async {
        guard let userId = AuthManager.shared.user?.id else { return }
        integrations = (try? await CRMIntegrationManager.shared.fetchIntegrations(userId: userId)) ?? []
    }

    private func pushToCRM() async {
        guard AuthManager.shared.user?.id != nil, !isPushingToCRM else { return }
        isPushingToCRM = true
        defer { isPushingToCRM = false }
        guard let provider = connectedProvider else { return }
        do {
            try await SalespersonMobileAPI.shared.pushSalespersonLeadToCRM(
                provider: provider,
                lead: lead,
                name: name,
                phone: phone,
                email: email,
                notes: notes
            )
            didPushToCRM = true
            statusMessage = "Contact sent to \(provider.displayName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share() {
        shareItems = [[name.nilIfEmpty ?? lead.displayName, company.nilIfEmpty, phone.nilIfEmpty, email.nilIfEmpty, address, notes.nilIfEmpty]
            .compactMap { $0 }.joined(separator: "\n")]
        showShareSheet = true
    }
}

private struct SalespersonShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SalespersonEmailSocialLink: Identifiable {
    let id: String
    let destination: URL
    let icon: URL

    static let all: [SalespersonEmailSocialLink] = [
        socialLink("Instagram", domain: "instagram.com"),
        socialLink("YouTube", domain: "youtube.com"),
        socialLink("LinkedIn", domain: "linkedin.com"),
        socialLink("Facebook", domain: "facebook.com")
    ]

    private static func socialLink(_ name: String, domain: String) -> SalespersonEmailSocialLink {
        SalespersonEmailSocialLink(
            id: name,
            destination: URL(string: "https://\(domain)")!,
            icon: URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64")!
        )
    }
}

private struct SalespersonEmailSignaturePreview: View {
    let senderEmail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(Color.flyrPrimary)
                .frame(width: 3, height: 106)

            VStack(alignment: .leading, spacing: 4) {
                Text("Daniel Phillippe")
                    .font(.system(size: 15, weight: .bold))

                HStack(spacing: 5) {
                    Text("Founder")
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 3, height: 3)
                    Link("WolfGrid", destination: URL(string: "https://wolfgrid.app")!)
                        .fontWeight(.semibold)
                        .tint(Color.flyrPrimary)
                }
                .font(.caption)

                HStack(spacing: 5) {
                    Link("wolfgrid.app", destination: URL(string: "https://wolfgrid.app")!)
                    Text("|")
                        .foregroundStyle(.tertiary)
                    Link(senderEmail, destination: URL(string: "mailto:\(senderEmail)")!)
                }
                .font(.caption)
                .tint(.primary)

                HStack(spacing: 7) {
                    ForEach(SalespersonEmailSocialLink.all) { socialLink in
                        Link(destination: socialLink.destination) {
                            AsyncImage(url: socialLink.icon) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFit()
                                } else {
                                    Image(systemName: "link")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 16, height: 16)
                            .frame(width: 26, height: 26)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .accessibilityLabel(socialLink.id)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Email signature: Daniel Phillippe, Founder at WolfGrid, wolfgrid.app, \(senderEmail), with Instagram, YouTube, LinkedIn, and Facebook links.")
    }
}

struct SalespersonEmailComposer: View {
    @Binding var recipient: String
    @Binding var subject: String
    @Binding var messageBody: String
    let recipientName: String?
    let recipientIsEditable: Bool
    let isSending: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSend: () -> Void
    @FocusState private var focusedField: Field?

    private enum Field {
        case recipient
        case subject
        case body
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .accessibilityLabel("Close email")

                Spacer()

                Menu {
                    Button {
                        subject = SalespersonDemoEmailTemplate.subject
                        messageBody = SalespersonDemoEmailTemplate.body(recipientName: recipientName)
                        focusedField = .body
                    } label: {
                        Label(SalespersonDemoEmailTemplate.title, systemImage: "play.rectangle")
                    }
                    Divider()
                    Button {
                        applyTemplate(.individualAgent)
                    } label: {
                        Label(SalespersonOutreachTemplate.individualAgent.title, systemImage: "person.crop.circle")
                    }
                    Button {
                        applyTemplate(.realEstateTeam)
                    } label: {
                        Label(SalespersonOutreachTemplate.realEstateTeam.title, systemImage: "person.3")
                    }
                    Divider()
                    Button(action: applyFollowUpTemplate) {
                        Label("Follow-up", systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 30, height: 38)
                }
                .accessibilityLabel("Email templates")

                Button(action: onSend) {
                    if isSending {
                        ProgressView()
                            .frame(width: 30, height: 38)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .frame(width: 30, height: 38)
                    }
                }
                .disabled(!canSend)
                .accessibilityLabel("Send email")
            }
            .overlay {
                Text("New Email")
                    .font(.headline)
                    .allowsHitTesting(false)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)

            composeRow(label: "To") {
                if recipientIsEditable {
                    TextField("Email address", text: $recipient)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .recipient)
                } else {
                    Text(recipient)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            composeRow(label: "From") {
                Text(senderEmail)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Divider()

            composeRow(label: "Subject") {
                TextField("Enter subject", text: $subject)
                    .textFieldStyle(.plain)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .subject)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .onSubmit { focusedField = .body }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if messageBody.isEmpty {
                            Text("Compose email")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 21)
                                .padding(.vertical, 17)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $messageBody)
                            .focused($focusedField, equals: .body)
                            .scrollContentBackground(.hidden)
                            .scrollDisabled(true)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(Color.clear)
                    }
                    .frame(minHeight: 120)

                    SalespersonEmailSignaturePreview(senderEmail: senderEmail)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 16)

                    if let errorMessage = errorMessage?.nilIfEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSending)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focusedField = nil
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16, weight: .semibold))
                }
                .accessibilityLabel("Hide keyboard")
            }
        }
        .onAppear {
            focusedField = recipientIsEditable && recipient.isEmpty ? .recipient : .subject
        }
    }

    private var senderEmail: String {
        AuthManager.shared.user?.email.nilIfEmpty ?? "WolfGrid Mail"
    }

    private var canSend: Bool {
        !isSending
            && recipient.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
            && recipient.trimmingCharacters(in: .whitespacesAndNewlines).contains(".")
            && !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func composeRow<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.body)
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
    }

    private func applyFollowUpTemplate() {
        let firstName = recipientName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)
        subject = "Quick follow-up"
        messageBody = """
        Hi \(firstName?.nilIfEmpty ?? "there"),

        It was great speaking with you. I wanted to follow up and see if you had any questions.
        """
        focusedField = .body
    }

    private func applyTemplate(_ template: SalespersonOutreachTemplate) {
        subject = template.emailSubject
        messageBody = template.emailBody(recipientName: recipientName)
        focusedField = .body
    }
}

private struct SalespersonContactComposerSheet: View {
    let channel: SalespersonContactComposerChannel
    let leadId: String
    let contactId: String?
    let recipient: String
    let recipientName: String
    let onSent: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var subject = "Following up"
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    @ViewBuilder
    var body: some View {
        if channel == .email {
            SalespersonEmailComposer(
                recipient: .constant(recipient),
                subject: $subject,
                messageBody: $message,
                recipientName: recipientName,
                recipientIsEditable: false,
                isSending: isSending,
                errorMessage: errorMessage,
                onCancel: { dismiss() },
                onSend: { Task { await send() } }
            )
        } else {
            NavigationStack {
                VStack(spacing: 0) {
                    SalespersonMessageRecipientHeader(
                        name: recipientName,
                        phone: recipient
                    )

                    Divider()
                    Spacer(minLength: 24)

                    if let errorMessage = errorMessage?.nilIfEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    SalespersonMessageComposeBar(
                        text: $message,
                        placeholder: "Text Message",
                        isSending: isSending,
                        canSend: canSend && !isSending,
                        onSend: { Task { await send() } }
                    )
                }
                .background(Color(uiColor: .systemBackground))
                .navigationTitle(channel.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                applyTextTemplate(.individualAgent)
                            } label: {
                                Label(SalespersonOutreachTemplate.individualAgent.title, systemImage: "person.crop.circle")
                            }
                            Button {
                                applyTextTemplate(.realEstateTeam)
                            } label: {
                                Label(SalespersonOutreachTemplate.realEstateTeam.title, systemImage: "person.3")
                            }
                        } label: {
                            Label("Templates", systemImage: "doc.on.doc")
                        }
                    }
                }
                .alert(channel.title, isPresented: Binding(
                    get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
                )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Unable to send.") }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var canSend: Bool {
        !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (channel == .sms || !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func applyTextTemplate(_ template: SalespersonOutreachTemplate) {
        let senderName = AuthManager.shared.user?.displayName?.nilIfEmpty ?? "Daniel"
        message = template.smsBody(recipientName: recipientName, senderName: senderName)
    }

    private func send() async {
        guard canSend, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let warning: String?
            if channel == .sms {
                warning = try await SalespersonMobileAPI.shared.sendInboxText(
                    leadId: leadId, contactId: contactId, body: message, phone: recipient
                )
            } else {
                warning = try await SalespersonMobileAPI.shared.sendInboxEmail(
                    leadId: leadId, contactId: contactId, to: recipient, subject: subject, body: message,
                    useDemoTemplate: SalespersonDemoEmailTemplate.matches(
                        subject: subject, body: message, recipientName: recipientName
                    )
                )
            }
            onSent(warning ?? "\(channel == .sms ? "Message" : "Email") sent to \(recipientName).")
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SalespersonLeadScraperView: View {
    @StateObject private var viewModel = SalespersonScraperViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showSaveListSheet = false
    @State private var listNameDraft = ""
    @State private var listNameError: String?
    let onOpenLeads: (SavedScraperList?) -> Void
    let onOpenDialler: (SavedScraperList?) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchControls
                    metricsSection
                    statusSection
                    savedListSection
                    resultsSection
                }
                .padding()
            }
            .blur(radius: showSaveListSheet ? 2 : 0)
            .animation(.easeInOut(duration: 0.18), value: showSaveListSheet)
            .navigationTitle("Add Leads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await viewModel.loadOptions() }
            .alert("Scraper", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .sheet(isPresented: $showSaveListSheet) {
                saveLeadListSheet
                    .presentationDetents([.height(260)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let run = viewModel.selectedRun {
                Text("Last hit \(run.createdAt.formatted(date: .abbreviated, time: .shortened)): \(run.uniqueCount) unique, \(run.dialerCount) dialer rows.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            scraperControlRow(title: "Country") {
                Picker("Country", selection: Binding(
                    get: { viewModel.countryCode },
                    set: { viewModel.selectCountry($0) }
                )) {
                    ForEach(viewModel.countryOptions, id: \.0) { option in
                        Text(option.1).tag(option.0)
                    }
                }
                .pickerStyle(.menu)
                .tint(.red)
            }

            scraperControlRow(title: "City") {
                TextField("Start typing a city", text: $viewModel.city)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .foregroundStyle(.red)
                    .tint(.red)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onChange(of: viewModel.city) { _, value in
                        Task { await viewModel.refreshCitySuggestions(for: value) }
                    }

                if viewModel.cityAutocompleteLoading {
                    Label("Searching cities", systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(viewModel.citySuggestions) { suggestion in
                    Button {
                        viewModel.selectCitySuggestion(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.city)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text([suggestion.region, suggestion.countryCode].filter { !$0.isEmpty }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            scraperControlRow(title: "Industry") {
                Picker("Industry", selection: Binding(
                    get: { viewModel.industry },
                    set: { viewModel.selectIndustry(named: $0) }
                )) {
                    Text("Pick an industry").tag("")
                    ForEach(viewModel.industryOptions) { industry in
                        Text(industry.name).tag(industry.name)
                    }
                }
                .pickerStyle(.menu)
                .tint(.red)
            }

            if viewModel.realEstateMode {
                scraperControlRow(title: "Filter") {
                    Picker("Real estate target", selection: $viewModel.realEstateTarget) {
                        ForEach(viewModel.realEstateTargetOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.red)
                }
            }

            Toggle(isOn: $viewModel.researchModeEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Research mode", systemImage: "sparkle.magnifyingglass")
                        .font(.headline)
                    Text("Research every company after this lead list is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.red)
            .accessibilityHint("Uses public sources to prepare company and call research for the generated leads")

            Button {
                openSaveListSheet()
            } label: {
                Label(viewModel.isSearching ? "Adding Leads" : "Add Leads", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(!viewModel.canSubmit)
        }
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func openSaveListSheet() {
        listNameDraft = viewModel.defaultListName
        listNameError = nil
        showSaveListSheet = true
    }

    private func saveNamedList() {
        let cleanedName = listNameDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !cleanedName.isEmpty else {
            listNameError = "Name your list before saving."
            return
        }

        listNameError = nil
        Task {
            let didCreateLeads = await viewModel.runSearch(listName: String(cleanedName.prefix(120)))
            if didCreateLeads {
                showSaveListSheet = false
                onOpenLeads(viewModel.summary?.savedList)
            }
        }
    }

    private var saveLeadListSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
                    .background(Color.red.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Save Lead List")
                        .font(.headline)
                    Text("Name this list before WolfGrid saves the leads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField(viewModel.defaultListName, text: $listNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)

                if let listNameError {
                    Text(listNameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Uses the same naming style as your saved lead lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button("Cancel") {
                    showSaveListSheet = false
                    listNameError = nil
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button {
                    saveNamedList()
                } label: {
                    if viewModel.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Save Leads", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isSearching)
            }
        }
        .padding()
    }

    private func scraperControlRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
                .font(.title2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metricsSection: some View {
        HStack(spacing: 10) {
            metric("Unique", value: "\(viewModel.summary?.uniqueResultCount ?? viewModel.prospects.count)")
            metric("Raw", value: "\(viewModel.summary?.rawResultCount ?? 0)")
            metric("Queries", value: "\(viewModel.summary?.queryCount ?? 0)")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status = viewModel.statusMessage {
            Text(status)
                .font(.subheadline)
                .foregroundStyle(.green)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var savedListSection: some View {
        if let saved = viewModel.summary?.savedList {
            VStack(alignment: .leading, spacing: 10) {
                Label(saved.listName, systemImage: "checklist")
                    .font(.headline)
                Text("\(saved.contactCount) saved. \(saved.dialerImportedCount) added to dialer, \(saved.dialerSkippedCount) already queued.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let warning = saved.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button {
                        onOpenLeads(saved)
                    } label: {
                        Label("Open in Leads", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onOpenDialler(saved)
                    } label: {
                        Label("Add to Dialer", systemImage: "phone.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color.green.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Places leads", systemImage: "building.2")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.prospects.count) shown")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.isSearching {
                ProgressView("Searching Google Places")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if viewModel.prospects.isEmpty {
                ContentUnavailableView("No Places leads yet", systemImage: "building.2")
                    .frame(minHeight: 160)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.prospects) { lead in
                        PlacesLeadResultRow(
                            lead: lead,
                            onCopy: { viewModel.copyLead(lead) },
                            onOpen: openExternal
                        )
                    }
                }
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func openExternal(_ rawValue: String) {
        let value = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard let url = URL(string: value) else { return }
        openURL(url)
    }
}

private struct PlacesLeadResultRow: View {
    let lead: PlacesLead
    let onCopy: () -> Void
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lead.name)
                        .font(.headline)
                    Text(lead.primaryType ?? lead.industry ?? "Lead")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let domain = lead.websiteDomain {
                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(lead.confidenceScore)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(lead.confidenceScore >= 75 ? Color.green.opacity(0.18) : Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let phone = lead.phone {
                Label(phone, systemImage: "phone")
                    .font(.subheadline)
                    .foregroundStyle(Color.flyrPrimary)
            }
            if let address = lead.formattedAddress {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let evidence = lead.evidenceSummary {
                Text(evidence)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let maps = lead.googleMapsUrl {
                    Button {
                        onOpen(maps)
                    } label: {
                        Label("Maps", systemImage: "mappin")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let website = lead.website {
                    Button {
                        onOpen(website)
                    } label: {
                        Label("Website", systemImage: "globe")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SalespersonHomeView: View {
    @StateObject private var home = SalespersonHomeViewModel()
    @ObservedObject private var voice = SalespersonVoiceCallService.shared
    @Environment(\.openURL) private var openURL
    @State private var isDemoPresented = false
    @State private var isVoicemailSettingsPresented = false
    @State private var isCallingVoicemail = false
    @State private var voicemailStatusMessage: String?
    @State private var voicemailErrorMessage: String?
    @State private var settingsDialNumber = ""
    @State private var isCallingSettingsNumber = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    homeHeader

                    if home.isLoading && home.performance == nil {
                        ProgressView("Loading performance")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }

                    if let error = home.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Retry") {
                                Task { await home.load() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    LazyVGrid(columns: metricColumns, spacing: 10) {
                        ForEach(performanceMetrics, id: \.title) { item in
                            metric(
                                item.title,
                                value: item.value,
                                currentValue: item.currentValue,
                                caption: item.caption,
                                comparison: item.comparison
                            )
                        }
                    }

                    mrrSummary

                    demoVideoLinkSection

                    accountActions
                }
                .padding()
                .padding(.top, 2)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $isDemoPresented) {
                TeamWebHandoffSafariView(url: home.demoVideoURL)
            }
            .sheet(isPresented: $isVoicemailSettingsPresented) {
                SalespersonVoicemailSettingsSheet(
                    isCallingVoicemail: isCallingVoicemail,
                    statusMessage: voicemailStatusMessage,
                    errorMessage: voicemailErrorMessage,
                    registrationError: voice.registrationError,
                    dialNumber: $settingsDialNumber,
                    isCallingNumber: isCallingSettingsNumber,
                    onCallVoicemail: {
                        Task { await callVoicemail() }
                    },
                    onCallNumber: {
                        Task { await callSettingsNumber() }
                    },
                    onOpenTelnyx: {
                        if let url = URL(string: "https://portal.telnyx.com/") {
                            openURL(url)
                        }
                    }
                )
            }
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(home.displayName)
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 8)

            Menu {
                ForEach(SalespersonHomeViewModel.Period.allCases) { period in
                    Button {
                        Task { await home.selectPeriod(period) }
                    } label: {
                        if period == home.selectedPeriod {
                            Label(period.menuLabel, systemImage: "checkmark")
                        } else {
                            Text(period.menuLabel)
                        }
                    }
                }
            } label: {
                Label(home.selectedPeriod.menuLabel, systemImage: "chevron.down")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    private var performanceMetrics: [(
        title: String,
        value: String,
        currentValue: Int,
        caption: String,
        comparison: SalespersonPerformanceResponse.MetricComparison?
    )] {
        let periodCaption = home.selectedPeriod.caption
        guard let performance = home.performance else {
            return [
                ("Calls Made", "0", 0, periodCaption, nil),
                ("Answers", "0", 0, periodCaption, nil),
                ("Texts", "0", 0, periodCaption, nil),
                ("Emails", "0", 0, periodCaption, nil),
                ("DMs", "0", 0, periodCaption, nil),
                ("Posts", "0", 0, periodCaption, nil),
                ("Meetings Booked", "0", 0, periodCaption, nil),
                ("Meetings Held", "0", 0, periodCaption, nil),
                ("Sign Ups", "0", 0, periodCaption, nil),
                ("Paid Teams", "0", 0, periodCaption, nil),
            ]
        }

        let comparisons = performance.comparisons

        return [
            ("Calls Made", formatCount(performance.outreach.calls), performance.outreach.calls, periodCaption, comparisons?.outreach.calls),
            ("Answers", formatCount(performance.outreach.answers), performance.outreach.answers, periodCaption, comparisons?.outreach.answers),
            ("Texts", formatCount(performance.outreach.outboundMessages), performance.outreach.outboundMessages, periodCaption, comparisons?.outreach.messages),
            ("Emails", formatCount(performance.outreach.emails), performance.outreach.emails, periodCaption, comparisons?.outreach.emails),
            ("DMs", formatCount(performance.outreach.directMessages), performance.outreach.directMessages, periodCaption, comparisons?.outreach.directMessages),
            ("Posts", formatCount(performance.outreach.posts), performance.outreach.posts, periodCaption, comparisons?.outreach.posts),
            ("Meetings Booked", formatCount(performance.outreach.meetingsBooked), performance.outreach.meetingsBooked, periodCaption, comparisons?.outreach.meetingsBooked),
            ("Meetings Held", formatCount(performance.outreach.meetingsHeld), performance.outreach.meetingsHeld, periodCaption, comparisons?.outreach.meetingsHeld),
            ("Sign Ups", formatCount(performance.links.signups), performance.links.signups, periodCaption, comparisons?.links.signups),
            ("Paid Teams", formatCount(performance.revenue.paidTeams), performance.revenue.paidTeams, periodCaption, comparisons?.revenue.paidTeams),
        ]
    }

    private var mrrSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MRR")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(mrrRows, id: \.currency) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.formattedValue)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    trendBadge(comparison: row.comparison, currentValue: row.cents)
                }
            }

            Text("Monthly recurring revenue from Stripe subscriptions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var mrrRows: [(
        currency: String,
        cents: Int,
        formattedValue: String,
        comparison: SalespersonPerformanceResponse.MetricComparison?
    )] {
        guard let performance = home.performance,
              !performance.revenue.mrrByCurrency.isEmpty else {
            return [("USD", 0, "$0", nil)]
        }

        return performance.revenue.mrrByCurrency
            .sorted { $0.key < $1.key }
            .map { currency, cents in
                let amount = Decimal(cents) / 100
                let formattedValue = amount.formatted(
                    .currency(code: currency.uppercased())
                        .precision(.fractionLength(0...2))
                )
                return (
                    currency,
                    cents,
                    formattedValue,
                    performance.comparisons?.revenue.mrrByCurrency[currency]
                )
            }
    }

    @ViewBuilder
    private var demoVideoLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("WolfGrid demo", systemImage: "play.rectangle.fill")
                    .font(.headline)
                Spacer()
                Button {
                    home.copyDemoVideoLink()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                isDemoPresented = true
            } label: {
                Label("Open demo", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text(home.demoVideoLink)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            if let message = home.linkCopyMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var accountActions: some View {
        HStack(spacing: 12) {
            Button {
                isVoicemailSettingsPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)

            Button {
                Task {
                    await AuthManager.shared.signOut()
                }
            } label: {
                Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    private func callVoicemail() async {
        guard !isCallingVoicemail else { return }
        isCallingVoicemail = true
        voicemailStatusMessage = nil
        voicemailErrorMessage = nil
        defer { isCallingVoicemail = false }

        do {
            SalespersonVoiceCallService.shared.endActiveCall()
            SalespersonVoiceCallService.shared.clearRegistrationError()
            try await voice.startOutboundCall(
                label: "Voicemail",
                callRequestId: UUID().uuidString,
                destinationNumber: "*98",
                fromNumber: nil
            )
            voicemailStatusMessage = "Calling voicemail."
        } catch {
            voicemailErrorMessage = error.localizedDescription
        }
    }

    private func callSettingsNumber() async {
        guard !isCallingSettingsNumber else { return }
        let trimmed = settingsDialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            voicemailStatusMessage = nil
            voicemailErrorMessage = "Enter a phone number to call."
            return
        }

        isCallingSettingsNumber = true
        voicemailStatusMessage = nil
        voicemailErrorMessage = nil
        defer { isCallingSettingsNumber = false }

        do {
            SalespersonVoiceCallService.shared.endActiveCall()
            SalespersonVoiceCallService.shared.clearRegistrationError()
            try await voice.startOutboundCall(
                label: trimmed,
                callRequestId: UUID().uuidString,
                destinationNumber: trimmed,
                fromNumber: nil
            )
            voicemailStatusMessage = "Calling \(trimmed)."
        } catch {
            voicemailErrorMessage = error.localizedDescription
        }
    }

    private func load() async {
        await home.load()
    }

    private func metric(
        _ title: String,
        value: String,
        currentValue: Int,
        caption: String,
        comparison: SalespersonPerformanceResponse.MetricComparison?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 2)

                trendBadge(comparison: comparison, currentValue: currentValue)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func trendBadge(
        comparison: SalespersonPerformanceResponse.MetricComparison?,
        currentValue: Int
    ) -> some View {
        let presentation = trendPresentation(comparison: comparison, currentValue: currentValue)
        return Text(presentation.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(presentation.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(presentation.color.opacity(0.14))
            .clipShape(Capsule())
            .fixedSize()
            .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func trendPresentation(
        comparison: SalespersonPerformanceResponse.MetricComparison?,
        currentValue: Int
    ) -> (label: String, color: Color, accessibilityLabel: String) {
        guard let previousValue = comparison?.previousValue else {
            return ("—", .secondary, "Previous-period comparison unavailable")
        }

        if previousValue == 0, currentValue > 0 {
            return ("New", .green, "New compared with the previous period")
        }

        guard let percentage = comparison?.percentageChange else {
            return ("—", .secondary, "Previous-period comparison unavailable")
        }

        let rounded = Int(percentage.rounded())
        if percentage > 0 {
            return ("+\(rounded)%", .green, "Up \(rounded) percent from the previous period")
        }
        if percentage < 0 {
            return ("−\(abs(rounded))%", .red, "Down \(abs(rounded)) percent from the previous period")
        }
        return ("0%", .secondary, "No change from the previous period")
    }

    private func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let safeSeconds = max(0, Int(seconds.rounded()))
        let minutes = safeSeconds / 60
        let remainder = safeSeconds % 60
        if minutes <= 0 { return "\(remainder)s" }
        return "\(minutes)m \(String(format: "%02d", remainder))s"
    }
}

private struct SalespersonVoicemailSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var voice = SalespersonVoiceCallService.shared
    let isCallingVoicemail: Bool
    let statusMessage: String?
    let errorMessage: String?
    let registrationError: String?
    @Binding var dialNumber: String
    let isCallingNumber: Bool
    let onCallVoicemail: () -> Void
    let onCallNumber: () -> Void
    let onOpenTelnyx: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Voicemail", systemImage: "recordingtape")
                            .font(.title3.weight(.bold))

                        VStack(spacing: 10) {
                            Button(action: onCallVoicemail) {
                                Label(isCallingVoicemail ? "Calling..." : "Call Voicemail", systemImage: "phone.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCallingVoicemail)

                            Button(action: onOpenTelnyx) {
                                Label("Telnyx Portal", systemImage: "safari.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Call a number", systemImage: "phone.arrow.up.right.fill")
                            .font(.title3.weight(.bold))

                        HStack(spacing: 10) {
                            TextField("+1 555 555 5555", text: $dialNumber)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 48)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button(action: onCallNumber) {
                                Label(isCallingNumber ? "Calling..." : "Call", systemImage: "phone.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.headline)
                                    .frame(width: 48, height: 48)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCallingNumber || dialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel(isCallingNumber ? "Calling" : "Call number")
                        }
                    }
                    .padding()
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if shouldShowKeypad {
                        SalespersonDTMFKeypad()
                            .padding()
                            .background(Color.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        voicemailRow("Access code", value: "*98")
                        voicemailRow("Greeting", value: "Managed in voicemail call")
                        voicemailRow("PIN", value: "Managed in Telnyx")
                    }
                    .padding()
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let statusMessage {
                        statusBanner(statusMessage, systemImage: "checkmark.circle.fill", color: .green)
                    }

                    if let errorMessage {
                        statusBanner(errorMessage, systemImage: "exclamationmark.triangle.fill", color: .red)
                    } else if let registrationError {
                        statusBanner(registrationError, systemImage: "exclamationmark.triangle.fill", color: .orange)
                    }
                }
                .padding()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var shouldShowKeypad: Bool {
        switch voice.callPhase {
        case .connecting, .connected:
            return voice.activeCallLabel?.localizedCaseInsensitiveContains("voicemail") == true
        case .idle, .ended:
            return false
        }
    }

    private func voicemailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func statusBanner(_ message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SalespersonDTMFKeypad: View {
    @ObservedObject private var voice = SalespersonVoiceCallService.shared
    @State private var sentDigits = ""
    @State private var errorMessage: String?

    private var canSendDigits: Bool {
        voice.callPhase == .connected
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Keypad", systemImage: "circle.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(canSendDigits ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(canSendDigits ? "Connected" : "Connecting")
            }

            Text(sentDigits.isEmpty ? "Digits sent will appear here" : sentDigits)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(sentDigits.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            SalespersonPhoneKeypadGrid(isEnabled: canSendDigits) { digit in
                send(digit)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !canSendDigits {
                Label("Wait until the call connects before entering your PIN.", systemImage: "clock.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .dynamicTypeSize(.medium ... .xLarge)
    }

    private func send(_ digit: String) {
        do {
            try voice.sendDTMF(digit)
            sentDigits += digit
            errorMessage = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SalespersonPhoneKeypadGrid: View {
    let isEnabled: Bool
    var supportsInternationalPrefix = false
    let onDigit: (String) -> Void

    private let spacing: CGFloat = 18
    private let rows: [[Key]] = [
        [Key("1", ""), Key("2", "ABC"), Key("3", "DEF")],
        [Key("4", "GHI"), Key("5", "JKL"), Key("6", "MNO")],
        [Key("7", "PQRS"), Key("8", "TUV"), Key("9", "WXYZ")],
        [Key("*", ""), Key("0", "+"), Key("#", "")],
    ]

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row) { key in
                        Button {
                            onDigit(key.digit)
                        } label: {
                            VStack(spacing: 1) {
                                Text(key.digit)
                                    .font(.system(size: 32, weight: .regular, design: .rounded))
                                    .lineLimit(1)
                                Text(key.subtitle)
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.2)
                                    .foregroundStyle(.secondary)
                                    .frame(height: 12)
                            }
                            .foregroundStyle(.primary)
                            .frame(width: 76, height: 76)
                            .background(Color.primary.opacity(0.10))
                            .clipShape(Circle())
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.35)
                        .accessibilityLabel(keyAccessibilityLabel(key))
                        .onLongPressGesture(minimumDuration: 0.45) {
                            guard isEnabled, supportsInternationalPrefix, key.digit == "0" else { return }
                            onDigit("+")
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func keyAccessibilityLabel(_ key: Key) -> String {
        if supportsInternationalPrefix, key.digit == "0" {
            return "0, touch and hold for plus"
        }
        return key.digit
    }

    private struct Key: Identifiable, Hashable {
        let digit: String
        let subtitle: String
        var id: String { digit }

        init(_ digit: String, _ subtitle: String) {
            self.digit = digit
            self.subtitle = subtitle
        }
    }
}

private struct SalespersonManualDialPad: View {
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var isCalling = false
    @State private var validationMessage: String?
    let onCall: (String) async -> Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 12) {
                        Text(number.isEmpty ? "Enter a phone number" : number)
                            .font(.system(size: 30, weight: .medium, design: .rounded))
                            .foregroundStyle(number.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 48)

                        Button {
                            guard !number.isEmpty else { return }
                            number.removeLast()
                            validationMessage = nil
                        } label: {
                            Image(systemName: "delete.left.fill")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(number.isEmpty || isCalling)
                        .opacity(number.isEmpty ? 0.35 : 1)
                        .onLongPressGesture {
                            number = ""
                            validationMessage = nil
                        }
                        .accessibilityLabel("Delete digit")
                    }
                    .padding(.horizontal, 8)

                    SalespersonPhoneKeypadGrid(
                        isEnabled: !isCalling,
                        supportsInternationalPrefix: true
                    ) { digit in
                        append(digit)
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    Button {
                        startCall()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 78, height: 78)
                            if isCalling {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isCalling || number.filter(\.isNumber).count < 8)
                    .opacity(number.filter(\.isNumber).count < 8 ? 0.45 : 1)
                    .accessibilityLabel(isCalling ? "Calling" : "Call number")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationTitle("Manual Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isCalling)
                }
            }
        }
    }

    private func append(_ digit: String) {
        guard number.count < 18 else { return }
        if digit == "+" {
            guard number.isEmpty else { return }
        }
        number += digit
        validationMessage = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func startCall() {
        guard number.filter(\.isNumber).count >= 8 else {
            validationMessage = "Enter a valid phone number."
            return
        }
        isCalling = true
        Task {
            let didStart = await onCall(number)
            isCalling = false
            if didStart {
                dismiss()
            } else {
                validationMessage = "The call could not be started."
            }
        }
    }
}

private enum SalespersonDiallerNewLeadKind: String, Identifiable {
    case company
    case person

    var id: String { rawValue }

    var title: String {
        switch self {
        case .company: return "Add Company"
        case .person: return "Add Person"
        }
    }
}

private struct SalespersonDiallerNewLeadSheet: View {
    let kind: SalespersonDiallerNewLeadKind
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var personName = ""
    @State private var companyName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var isSaving = false

    private var trimmedPersonName: String {
        personName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCompanyName: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedName: String {
        switch kind {
        case .company:
            return trimmedPersonName.nilIfEmpty ?? trimmedCompanyName
        case .person:
            return trimmedPersonName
        }
    }

    private var canSave: Bool {
        let hasIdentity = kind == .company ? !trimmedCompanyName.isEmpty : !trimmedPersonName.isEmpty
        return hasIdentity && phone.filter(\.isNumber).count >= 8 && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(content: {
                    if kind == .company {
                        TextField("Company name", text: $companyName)
                            .textContentType(.organizationName)
                            .textInputAutocapitalization(.words)
                        TextField("Contact person (optional)", text: $personName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                    } else {
                        TextField("Person name", text: $personName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                        TextField("Company name (optional)", text: $companyName)
                            .textContentType(.organizationName)
                            .textInputAutocapitalization(.words)
                    }
                }, header: {
                    Text(kind == .company ? "Company lead" : "Person")
                }, footer: {
                    if kind == .person {
                        Text("Adding a company name links it to this person.")
                    } else {
                        Text("You can add a contact person now or use the company as the lead name.")
                    }
                })

                Section("Contact details") {
                    TextField("Phone", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField("Email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    TextField("Address (optional)", text: $address)
                        .textContentType(.fullStreetAddress)
                }

                Section("Notes") {
                    TextField("Add notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage = viewModel.errorMessage?.nilIfEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            let didSave = await viewModel.addManualLead(
                name: resolvedName,
                company: trimmedCompanyName,
                phone: phone,
                email: email,
                address: address,
                notes: notes,
                isCompanyLead: kind == .company
            )
            isSaving = false
            if didSave {
                dismiss()
            }
        }
    }
}

struct SalespersonDiallerView: View {
    @StateObject private var viewModel = SalespersonDiallerViewModel()
    @ObservedObject private var voice = SalespersonVoiceCallService.shared
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.openURL) private var openURL
    @State private var isSmartListSheetPresented = false
    @State private var isRecordingsSheetPresented = false
    @State private var isFollowUpSheetPresented = false
    @State private var isListSheetPresented = false
    @State private var isSettingsPresented = false
    @State private var isAudioRouteDialogPresented = false
    @State private var isKeypadPresented = false
    @State private var isManualKeypadPresented = false
    @State private var isTextSheetPresented = false
    @State private var isEmailSheetPresented = false
    @State private var isMeetingSheetPresented = false
    @State private var profileLead: SalespersonDiallerLead?
    @State private var researchLead: SalespersonDiallerLead?
    @State private var inlineResearchResponse: SalespersonCompanyResearchResponse?
    @State private var newLeadKind: SalespersonDiallerNewLeadKind?

    private var isBusy: Bool {
        viewModel.isPlacingCall ||
        viewModel.isSaving ||
        viewModel.isSavingContent ||
        viewModel.isDroppingVoicemail ||
        viewModel.isSendingTextDrop ||
        viewModel.isSendingCallbackText ||
        viewModel.isSendingEmail ||
        viewModel.isOpeningTestLead ||
        viewModel.isLoadingSmartLists ||
        viewModel.isCreatingSmartList ||
        viewModel.isImportingSmartList ||
        viewModel.isLoadingRecordings ||
        viewModel.isExportingRecording
    }

    private var shouldShowCallStatus: Bool {
        switch voice.callPhase {
        case .connecting, .connected:
            return true
        case .idle, .ended:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    diallerEntryActions

                    if viewModel.manualCallNumber != nil {
                        diallerWorkspace(lead: nil)
                    } else if let lead = viewModel.selectedLead {
                        diallerWorkspace(lead: lead)
                    } else if viewModel.activeList != nil {
                        diallerQueue
                    } else if viewModel.isLoading {
                        diallerWorkspace(lead: nil)
                            .overlay(alignment: .topTrailing) {
                                ProgressView()
                                    .padding(.top, 12)
                            }
                    } else if viewModel.mainList == nil {
                        diallerWorkspace(lead: nil)
                    } else {
                        diallerListOverview
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.bottom, 28)
            }
	            .navigationTitle("")
	            .toolbar(.hidden, for: .navigationBar)
	            .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        if let message = viewModel.statusMessage {
                            Text(message)
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.bgSecondary)
                                .clipShape(Capsule())
                        }

                        if isBusy {
                            ProgressView()
                                .padding(.vertical, 2)
                        }

                        HStack(spacing: 10) {
                            Button {
                                newLeadKind = .company
                            } label: {
                                Label("Add Company", systemImage: "building.2.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                newLeadKind = .person
                            } label: {
                                Label("Add Person", systemImage: "person.crop.circle.badge.plus")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .disabled(isBusy || viewModel.isCallSessionActive || viewModel.isDiallerSessionActive)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
	            }
	            .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button {
                                Task { await viewModel.openGabeTestLead() }
                            } label: {
                                Label("Gabe Phillippe", systemImage: "person.fill")
                            }

                            Button {
                                Task { await viewModel.openSantanaTestLead() }
                            } label: {
                                Label("Santana Phillippe", systemImage: "person.fill")
                            }

                            Button {
                                Task { await viewModel.openDanielQaqishTestLead() }
                            } label: {
                                Label("Daniel Qaqish", systemImage: "person.fill")
                            }
                        } label: {
                            Label("Test", systemImage: "phone.fill")
                        }
                        .disabled(viewModel.isOpeningTestLead)
                        .accessibilityLabel("Open test lead")
                    }

	                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            if viewModel.selectedLead != nil || viewModel.activeList != nil {
                                viewModel.closeList()
                            } else {
                                viewModel.openMainList()
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Dialler lists")

                        Button {
                            isSettingsPresented = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Dialler settings")
                    }
	            }
                .sheet(isPresented: $isSmartListSheetPresented) {
                    SalespersonDiallerSmartListSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $isSettingsPresented) {
                    SettingsView()
                }
                .sheet(isPresented: $isListSheetPresented) {
                    SalespersonDiallerListsSheet(viewModel: viewModel) { list in
                        isListSheetPresented = false
                        uiState.openSalespersonLeadList(id: list.id, title: list.title)
                    }
                }
                .sheet(isPresented: $isRecordingsSheetPresented) {
                    SalespersonDiallerRecordingsSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $isKeypadPresented) {
                    NavigationStack {
                        SalespersonDTMFKeypad()
                            .padding()
                            .navigationTitle("Keypad")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { isKeypadPresented = false }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $isManualKeypadPresented) {
                    SalespersonManualDialPad { number in
                        await viewModel.callManual(number: number)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(item: $newLeadKind) { kind in
                    SalespersonDiallerNewLeadSheet(kind: kind, viewModel: viewModel)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(item: $researchLead, onDismiss: {
                    Task { await loadInlineResearch(for: viewModel.selectedLead) }
                }) { lead in
                    SalespersonCompanyResearchSheet(lead: lead)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .confirmationDialog("Audio", isPresented: $isAudioRouteDialogPresented, titleVisibility: .visible) {
                    ForEach(voice.audioRouteOptions) { option in
                        Button {
                            voice.selectAudioRoute(option)
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                    }
                } message: {
                    Text("Choose where this call plays.")
                }
                .sheet(isPresented: $isFollowUpSheetPresented) {
                    if let lead = viewModel.selectedLead {
                        SalespersonDiallerFollowUpSheet(lead: lead) { title, date in
                            Task {
                                await viewModel.scheduleFollowUp(name: title, at: date)
                                isFollowUpSheetPresented = false
                            }
                        }
                    }
                }
                .sheet(isPresented: $isTextSheetPresented) {
                    SalespersonDiallerTextSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $isEmailSheetPresented) {
                    SalespersonDiallerEmailSheet(viewModel: viewModel)
                }
                .sheet(isPresented: $isMeetingSheetPresented) {
                    if let lead = viewModel.selectedLead {
                        SalespersonDiallerMeetingSheet(lead: lead, viewModel: viewModel)
                    }
                }
                .sheet(item: $profileLead) { lead in
                    NavigationStack {
                        SalespersonDiallerContactProfileView(lead: lead) {
                            profileLead = nil
                            Task { @MainActor in
                                isEmailSheetPresented = true
                            }
                        }
                    }
                }
                .sheet(item: $viewModel.recordingExport) { export in
                    NavigationStack {
                        VStack(spacing: 16) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 42))
                                .foregroundStyle(Color.flyrPrimary)
                            ShareLink(item: export.url) {
                                Label("Export Recording", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .navigationTitle("Recording")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { viewModel.recordingExport = nil }
                            }
                        }
                    }
                }
	            .refreshable {
                    await viewModel.load()
                    applyPendingDiallerListSelection()
                }
	            .task {
                    await viewModel.load()
                    applyPendingDiallerListSelection()
                }
	            .task { await voice.refreshRegistrationIfNeeded() }
                .task(id: viewModel.selectedLead?.id) {
                    await loadInlineResearch(for: viewModel.selectedLead)
                }
                .onChange(of: uiState.pendingSalespersonDiallerListSelection) { _, _ in
                    applyPendingDiallerListSelection()
                }
                .onChange(of: voice.callConnectedAt) { _, connectedAt in
                    if connectedAt != nil {
                        viewModel.markCurrentCallAnswered()
                    }
                }
                .onChange(of: voice.callPhase) { _, phase in
                    if phase == .ended {
                        viewModel.callDidEnd()
                    }
                }
	            .alert("Dialler", isPresented: Binding(
	                get: { viewModel.errorMessage != nil },
	                set: { if !$0 { viewModel.errorMessage = nil } }
	            )) {
	                Button("OK", role: .cancel) {}
	            } message: {
	                Text(viewModel.errorMessage ?? "")
            }
	        }
	    }

    private func applyPendingDiallerListSelection() {
        guard let pending = uiState.pendingSalespersonDiallerListSelection else { return }
        viewModel.openListMatching(id: pending.listId, title: pending.listTitle)
        uiState.pendingSalespersonDiallerListSelection = nil
    }

    private var diallerEntryActions: some View {
        HStack(spacing: 10) {
            diallerTopIconButton(
                systemImage: "circle.grid.3x3.fill",
                fill: Color.flyrPrimary,
                foreground: .white,
                accessibilityLabel: "Manual dialler keypad",
                disabled: isBusy || viewModel.isCallSessionActive || viewModel.isDiallerSessionActive
            ) {
                isManualKeypadPresented = true
            }

            Button {
                if viewModel.activeList == nil && viewModel.leadLists.isEmpty {
                    isSmartListSheetPresented = true
                    Task { await viewModel.loadSmartLists() }
                } else {
                    isListSheetPresented = true
                }
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.activeList?.title ?? "Add List")
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .multilineTextAlignment(.center)

                    Image(systemName: viewModel.activeList == nil ? "text.badge.plus" : "chevron.down")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 12)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.border.opacity(0.45))
                }
            }
            .buttonStyle(.plain)
            .disabled(isBusy || viewModel.isCallSessionActive || viewModel.isDiallerSessionActive)
            .opacity(isBusy || viewModel.isCallSessionActive || viewModel.isDiallerSessionActive ? 0.45 : 1)
            .accessibilityLabel(viewModel.activeList == nil ? "Add list" : "Change list, currently \(viewModel.activeList?.title ?? "")")

            let contentSaved = viewModel.activeCall?.isContentSaved == true
            diallerTopIconButton(
                systemImage: contentSaved ? "star.fill" : "star",
                foreground: contentSaved ? Color(red: 1, green: 0.76, blue: 0.16) : .primary,
                accessibilityLabel: contentSaved ? "Conversation saved for content" : "Save conversation for content",
                disabled: viewModel.activeCall == nil || viewModel.isSavingContent
            ) {
                Task { await viewModel.saveCurrentConversation() }
            }
            .accessibilityValue(contentSaved ? "Saved" : "Not saved")
        }
    }

    private var diallerListOverview: some View {
        LazyVStack(spacing: 10) {
            ForEach(viewModel.leadLists) { list in
                Button {
                    viewModel.openList(list)
                } label: {
                    SalespersonDiallerListSummaryRow(list: list)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectedLeadHeader(_ lead: SalespersonDiallerLead) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.closeLead()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayBusinessName)
                    .font(.headline)
                    .lineLimit(2)

                Text(viewModel.activeList?.subtitle ?? "\(viewModel.leads.count) queued")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func diallerWorkspace(lead: SalespersonDiallerLead?) -> some View {
        sessionMetricsHeader
        leadIdentityPanel(lead)
        compactCallControls(hasLead: lead != nil)
        if viewModel.isDiallerSessionActive {
            activeSessionControls
        }
        communicationActions(hasLead: lead != nil)
        compactNotes
        if let lead {
            SalespersonDiallerCallHistoryView(
                lead: lead,
                callPhase: voice.callPhase,
                activeCall: viewModel.activeCall
            )
            .id(lead.id)
            compactResearch(for: lead)
        }

        if viewModel.shouldChooseStatus {
            dispositionPicker
        }
    }

    private var sessionMetricsHeader: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            HStack(alignment: .center) {
                metric(value: viewModel.callsMade, label: "Calls made", alignment: .leading)

                Spacer(minLength: 8)

                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(formatCallElapsed(
                            from: voice.callConnectedAt ?? voice.callStartedAt,
                            now: context.date
                        ))
                            .font(.system(.title3, design: .monospaced).weight(.bold))

                        if let sessionStartedAt = viewModel.diallerSessionStartedAt {
                            Text("Session \(formatCallElapsed(from: sessionStartedAt, now: context.date))")
                                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                                .foregroundStyle(.secondary.opacity(0.62))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(timerAccessibilityLabel(now: context.date))

                    Text(shouldShowCallStatus ? label(for: voice.callPhase) : "Timer")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 84)

                Spacer(minLength: 8)

                metric(value: viewModel.callsAnswered, label: "Answered", alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .background(Color.clear)
        }
    }

    private func metric(value: Int, label: String, alignment: Alignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 2) {
            Text(value.formatted())
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func leadIdentityPanel(_ lead: SalespersonDiallerLead?) -> some View {
        HStack(spacing: 12) {
            if let lead {
                VStack(alignment: .leading, spacing: 5) {
                    Button {
                        profileLead = lead
                    } label: {
                        HStack(spacing: 6) {
                            Text(lead.name.nilIfEmpty ?? lead.displayBusinessName)
                                .font(.title3.weight(.bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the complete contact profile")

                    if let companyAndRole = lead.companyAndRoleLine {
                        Text(companyAndRole)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let location = lead.locationLine {
                        TimelineView(.periodic(from: Date(), by: 60)) { context in
                            Text(locationAndLocalTime(for: lead, location: location, now: context.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text("Last contacted: \(lastContactedText(for: lead))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(lead.phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if viewModel.isCallSessionActive {
                    keypadShortcut
                }
            } else if let manualNumber = viewModel.manualCallNumber {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manual call")
                        .font(.title3.weight(.bold))
                    Text(manualNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if viewModel.isCallSessionActive {
                    keypadShortcut
                }
            } else {
                Color.clear
                    .frame(height: 64)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    @ViewBuilder
    private func compactCallControls(hasLead: Bool) -> some View {
        if hasLead || viewModel.isCallSessionActive {
            HStack(spacing: 10) {
            compactButton(
                viewModel.isCallSessionActive ? "Hang Up" : "Call",
                systemImage: viewModel.isCallSessionActive ? "phone.down.fill" : "phone.fill",
                fill: viewModel.isCallSessionActive ? .red : Color.flyrPrimary,
                foreground: .white,
                disabled: (!hasLead && !viewModel.isCallSessionActive) ||
                    viewModel.isPlacingCall ||
                    (viewModel.isDiallerSessionActive && viewModel.isDiallerSessionPaused)
            ) {
                if viewModel.isCallSessionActive {
                    viewModel.hangUp()
                } else {
                    Task { await viewModel.callSelected() }
                }
            }

                if viewModel.isCallSessionActive {
                    compactButton(
                        "Speaker",
                        systemImage: voice.isSpeakerActive ? "speaker.wave.3.fill" : "speaker.wave.2",
                        fill: voice.isSpeakerActive ? Color.yellow.opacity(0.18) : Color.bgSecondary,
                        foreground: voice.isSpeakerActive ? .yellow : .primary
                    ) {
                        voice.toggleSpeaker()
                    }
                } else if hasLead {
                    compactButton(
                        "Next",
                        systemImage: "forward.fill",
                        disabled: viewModel.isPlacingCall || viewModel.isSavingContent || viewModel.leads.count < 2 || viewModel.isDiallerSessionActive
                    ) {
                        viewModel.advanceToNextLead()
                    }
                } else {
                    compactButton(
                        "Keypad",
                        systemImage: "circle.grid.3x3.fill",
                        disabled: viewModel.isPlacingCall || !viewModel.isCallSessionActive
                    ) {
                        isKeypadPresented = true
                    }
                }
            }
        }
    }

    private var activeSessionControls: some View {
        HStack(spacing: 8) {
            compactButton(
                viewModel.isDiallerSessionPaused ? "Resume" : "Pause",
                systemImage: viewModel.isDiallerSessionPaused ? "play.fill" : "pause.fill",
                disabled: viewModel.isPlacingCall
            ) {
                if viewModel.isDiallerSessionPaused {
                    Task { await viewModel.resumeSession() }
                } else {
                    viewModel.pauseSession()
                }
            }

            compactButton(
                "Skip",
                systemImage: "forward.end.fill",
                disabled: viewModel.isPlacingCall || viewModel.leads.count < 2
            ) {
                Task { await viewModel.skipCurrentLead() }
            }

            compactButton(
                "End Session",
                systemImage: "xmark.circle.fill",
                foreground: .red,
                disabled: viewModel.isPlacingCall
            ) {
                viewModel.endSession()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Active dialler session controls")
    }

    private func locationAndLocalTime(for lead: SalespersonDiallerLead, location: String, now: Date) -> String {
        guard let timeZone = lead.resolvedTimeZone else { return location }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(location) · \(formatter.string(from: now)) local time"
    }

    private func lastContactedText(for lead: SalespersonDiallerLead) -> String {
        guard let lastContacted = lead.lastContactedDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastContacted, relativeTo: Date())
    }

    private var keypadShortcut: some View {
        Button {
            isKeypadPresented = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.headline)
                Text("Keypad")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(Color.primary)
            .frame(width: 64, height: 52)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open call keypad")
    }

    private func communicationActions(hasLead: Bool) -> some View {
        HStack(spacing: 8) {
            shortcutButton("Text", systemImage: "message.fill", disabled: !hasLead) {
                isTextSheetPresented = true
            }
            shortcutButton("Email", systemImage: "envelope.fill", disabled: !hasLead) {
                isEmailSheetPresented = true
            }
            shortcutButton("Follow Up", systemImage: "clock.fill", disabled: !hasLead) {
                isFollowUpSheetPresented = true
            }
            shortcutButton("Meeting", systemImage: "calendar.badge.plus", disabled: !hasLead) {
                isMeetingSheetPresented = true
            }
        }
    }

    private var compactNotes: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))

            TextEditor(text: $viewModel.notes)
                .frame(height: 72)
                .padding(6)
                .disabled(viewModel.selectedLead == nil)
                .scrollContentBackground(.hidden)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.border))
        }
    }

    @ViewBuilder
    private func compactResearch(for lead: SalespersonDiallerLead) -> some View {
        if let result = inlineResearchResponse?.latest?.result {
            VStack(alignment: .leading, spacing: 7) {
                Text("Research")
                    .font(.subheadline.weight(.semibold))

                Button {
                    researchLead = lead
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 8) {
                            Label("Research", systemImage: "sparkle.magnifyingglass")
                                .font(.subheadline.weight(.semibold))

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }

                        if let website = result.website {
                            Label(website, systemImage: "globe")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let instagram = result.instagram {
                            Label(instagram, systemImage: "camera")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let timeInBusiness = result.timeInBusiness {
                            Label(timeInBusiness, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let googleReviews = result.googleReviews {
                            Label(googleReviews, systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !result.hasVisibleResearch {
                            Text("No verified website, Instagram, business age, or Google reviews found.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.border))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the complete company research")
            }
        } else if inlineResearchResponse?.active != nil {
            VStack(alignment: .leading, spacing: 7) {
                Text("Research")
                    .font(.subheadline.weight(.semibold))

                Button {
                    researchLead = lead
                } label: {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Researching company…")
                                .font(.subheadline.weight(.semibold))
                            Text("Public-source research is being prepared.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.border))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func loadInlineResearch(for lead: SalespersonDiallerLead?) async {
        inlineResearchResponse = nil
        guard let lead else { return }

        do {
            var latest = try await SalespersonMobileAPI.shared.fetchCompanyResearch(leadId: lead.id)
            guard viewModel.selectedLead?.id == lead.id else { return }
            inlineResearchResponse = latest

            while latest.active != nil && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled, viewModel.selectedLead?.id == lead.id else { return }
                latest = try await SalespersonMobileAPI.shared.fetchCompanyResearch(leadId: lead.id)
                inlineResearchResponse = latest
            }
        } catch {
            guard viewModel.selectedLead?.id == lead.id else { return }
            inlineResearchResponse = nil
        }
    }

    private var dispositionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Call status")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                dispositionButton("Interested", systemImage: "hand.thumbsup.fill", tint: .green, value: "interested")
                dispositionButton("Not Interested", systemImage: "hand.thumbsdown.fill", tint: .orange, value: "not_interested")
                dispositionButton("Bad Number", systemImage: "phone.down.fill", tint: .red, value: "bad_number")
            }
        }
        .padding(12)
        .background(Color.bgSecondary.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dispositionButton(_ title: String, systemImage: String, tint: Color, value: String) -> some View {
        Button {
            Task { await viewModel.log(disposition: value) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                Text(title)
                    .font(.caption2.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.bg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving)
        .opacity(viewModel.isSaving ? 0.45 : 1)
    }

    private func compactButton(
        _ title: String,
        systemImage: String,
        fill: Color = Color.bgSecondary,
        foreground: Color = Color.primary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(foreground)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.border.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func diallerTopIconButton(
        systemImage: String,
        fill: Color = Color.bgSecondary,
        foreground: Color = Color.primary,
        accessibilityLabel: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 56, height: 56)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.border.opacity(0.45))
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    private func shortcutButton(_ title: String, systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

	    private var diallerQueue: some View {
	        VStack(alignment: .leading, spacing: 10) {
	            Text(viewModel.activeList?.title ?? "Dialler queue")
	                .font(.subheadline.weight(.semibold))

                if viewModel.visibleLeads.isEmpty {
                    ContentUnavailableView("No leads in this list", systemImage: "phone")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
	            LazyVStack(spacing: 0) {
	                ForEach(SalespersonDiallerDateGroup.makeGroups(from: viewModel.visibleLeads)) { group in
	                    VStack(alignment: .leading, spacing: 0) {
	                        Text(group.title)
	                            .font(.caption.weight(.semibold))
	                            .foregroundStyle(.secondary)
	                            .padding(.top, 10)
	                            .padding(.bottom, 4)

	                        ForEach(group.leads) { lead in
	                            Button {
	                                viewModel.select(lead)
	                            } label: {
	                                SalespersonDiallerQueueRow(
	                                    lead: lead,
	                                    isSelected: lead.id == viewModel.selectedLead?.id
	                                )
	                            }
	                            .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.removeLead(lead) }
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        Task { await viewModel.toggleStar(lead) }
                                    } label: {
                                        Label(lead.isStarred == true ? "Unstar" : "Star", systemImage: lead.isStarred == true ? "star.slash" : "star")
                                    }
                                    .tint(.yellow)
                                }
                                .contextMenu {
                                    Button {
                                        Task { await viewModel.toggleStar(lead) }
                                    } label: {
                                        Label(lead.isStarred == true ? "Unstar Lead" : "Star Lead", systemImage: lead.isStarred == true ? "star.slash" : "star")
                                    }
                                    Button(role: .destructive) {
                                        Task { await viewModel.removeLead(lead) }
                                    } label: {
                                        Label("Remove Lead", systemImage: "trash")
                                    }
                                }

	                            if lead.id != group.leads.last?.id {
	                                Divider()
	                                    .padding(.leading, 44)
	                            }
	                        }
	                    }
	                }
	            }
                }
	        }
	    }

	    private func bottomActionBar() -> some View {
	        HStack(spacing: 10) {
            Button {
                isFollowUpSheetPresented = true
            } label: {
                Label("Follow up", systemImage: "arrow.uturn.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSaving)

            outcomeButton("DNC", value: "do_not_call", systemImage: "hand.raised.fill", role: .destructive)
                .buttonStyle(.bordered)
                .tint(.red)
	        }
	    }

    private func openExternal(_ rawValue: String) {
        let value = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard let url = URL(string: value) else { return }
        openURL(url)
    }

    private func callStatusPanel() -> some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let phase = voice.callPhase
            let tint = color(for: phase)
            let startedAt = phase == .connected
                ? (voice.callConnectedAt ?? voice.callStartedAt)
                : voice.callStartedAt

            HStack(spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(label(for: phase))

                Text(formatCallElapsed(from: startedAt, now: context.date))
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)

                if let activeCallLabel = voice.activeCallLabel?.nilIfEmpty {
                    Text(activeCallLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if voice.hasIncomingCall {
                    Button {
                        voice.answerActiveCall()
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.caption.weight(.bold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.white)
                            .background(Color.green)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Answer")
                }

                Button {
                    isKeypadPresented = true
                } label: {
                    Label("Keypad", systemImage: "circle.grid.3x3.fill")
                        .font(.caption.weight(.bold))
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keypad")

                Button {
                    voice.refreshAudioRoutes()
                    isAudioRouteDialogPresented = true
                } label: {
                    Image(systemName: selectedAudioRouteIcon)
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Audio route")

                Button {
                    viewModel.hangUp()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.white)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hang up")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.18), lineWidth: 1))
        }
    }

    private func outcomeButton(_ title: String, value: String, systemImage: String? = nil, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            Task { await viewModel.log(disposition: value) }
        } label: {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity)
            }
        }
        .disabled(viewModel.isSaving)
    }

    private func label(for phase: VoiceCallPhase) -> String {
        switch phase {
        case .idle: return "Ready"
        case .connecting: return "Calling"
        case .connected: return "Connected"
        case .ended: return "Call ended"
        }
    }

    private func icon(for phase: VoiceCallPhase) -> String {
        switch phase {
        case .idle: return "phone"
        case .connecting: return "phone.arrow.up.right"
        case .connected: return "phone.fill"
        case .ended: return "phone.down"
        }
    }

    private func color(for phase: VoiceCallPhase) -> Color {
        switch phase {
        case .connected: return .green
        case .connecting: return .orange
        case .ended: return .secondary
        case .idle: return Color.flyrPrimary
        }
    }

    private var selectedAudioRouteIcon: String {
        voice.audioRouteOptions.first(where: { $0.id == voice.selectedAudioRouteId })?.systemImage
            ?? "speaker.wave.2.fill"
    }

    private func formatCallElapsed(from startedAt: Date?, now: Date) -> String {
        guard let startedAt else { return "00:00" }
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func timerAccessibilityLabel(now: Date) -> String {
        let callTime = formatCallElapsed(
            from: voice.callConnectedAt ?? voice.callStartedAt,
            now: now
        )
        guard let sessionStartedAt = viewModel.diallerSessionStartedAt else {
            return "Current call \(callTime)"
        }
        let sessionTime = formatCallElapsed(from: sessionStartedAt, now: now)
        return "Current call \(callTime), dialler session \(sessionTime)"
    }

}

private struct SalespersonDiallerCallHistoryView: View {
    let lead: SalespersonDiallerLead
    let callPhase: VoiceCallPhase
    let activeCall: SalespersonDiallerCall?
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var logs: [SalespersonCallLog] = []
    @State private var isLoading = false
    @State private var hasMore = false
    @State private var errorMessage: String?
    @State private var requestID = UUID()
    @State private var refreshID = UUID()
    @State private var nextOffset = 0

    private var refreshKey: String {
        "\(lead.id):\(auth.user?.id.uuidString ?? ""): \(workspace.workspaceId?.uuidString ?? ""):\(callPhase):\(activeCall?.id.uuidString ?? ""):\(activeCall?.disposition ?? ""):\(refreshID)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Call Logs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { refreshID = UUID() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Refresh call logs")
            }

            ForEach(logs) { log in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: log.direction == "inbound" ? "phone.arrow.down.left" : "phone.arrow.up.right")
                        .foregroundStyle(Color.flyrPrimary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(log.direction == "inbound" ? "Incoming" : "Outgoing") · \(log.outcome)")
                            .font(.subheadline.weight(.semibold))
                        Text(log.occurredAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let duration = log.durationSeconds, duration > 0 {
                            Text("Duration: \(duration / 60)m \(duration % 60)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let note = log.note?.nilIfEmpty {
                            Text(note)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if isLoading {
                ProgressView("Loading call logs…")
                    .font(.caption)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try Again") { refreshID = UUID() }
            } else if logs.isEmpty {
                Text("No call logs yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hasMore {
                Button("Show Older Calls") { Task { await load(reset: false) } }
                    .font(.subheadline)
            }
        }
        .task(id: refreshKey) {
            await load(reset: true)
            // Call completion webhooks can arrive just after the device hangs up.
            if callPhase == .ended {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await load(reset: true)
            }
        }
    }

    @MainActor
    private func load(reset: Bool) async {
        let currentRequest = UUID()
        requestID = currentRequest
        if reset {
            logs = []
            nextOffset = 0
            hasMore = false
        }
        isLoading = true
        errorMessage = nil
        defer { if requestID == currentRequest { isLoading = false } }
        do {
            let page = try await SalespersonMobileAPI.shared.fetchCallLogs(for: lead, offset: nextOffset)
            try Task.checkCancellation()
            guard requestID == currentRequest else { return }
            let existingIDs = Set(logs.map(\.id))
            logs.append(contentsOf: page.filter { !existingIDs.contains($0.id) })
            nextOffset += page.count
            hasMore = page.count == 25
        } catch {
            guard !Task.isCancelled, requestID == currentRequest else { return }
            errorMessage = "Unable to load call logs. Please try again."
        }
    }
}

private struct SalespersonDiallerContactProfileView: View {
    let lead: SalespersonDiallerLead
    let onComposeEmail: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lead.name.nilIfEmpty ?? lead.displayBusinessName)
                        .font(.title2.weight(.bold))

                    if let companyAndRole = lead.companyAndRoleLine {
                        Text(companyAndRole)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if let location = lead.locationLine {
                        TimelineView(.periodic(from: Date(), by: 60)) { context in
                            Text(locationAndLocalTime(location: location, now: context.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Last contacted: \(lastContactedText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section("Contact") {
                Button {
                    open("tel://\(lead.phone.filter { $0.isNumber || $0 == "+" })")
                } label: {
                    LabeledContent("Phone", value: lead.phone)
                }

                if let email = lead.email?.nilIfEmpty {
                    Button(action: onComposeEmail) {
                        LabeledContent("Email", value: email)
                    }
                }

                if let website = lead.website?.nilIfEmpty ?? lead.websiteDomain?.nilIfEmpty {
                    Button {
                        open(website.contains("://") ? website : "https://\(website)")
                    } label: {
                        LabeledContent("Website", value: website)
                    }
                }

                if let address = lead.address?.nilIfEmpty {
                    LabeledContent("Address", value: address)
                }
            }

            if let notes = lead.notes?.nilIfEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section("Details") {
                if let listName = lead.listName?.nilIfEmpty {
                    LabeledContent("List", value: listName)
                }
                if let added = lead.createdAt {
                    LabeledContent("Added", value: added.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .navigationTitle("Contact Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var lastContactedText: String {
        guard let lastContacted = lead.lastContactedDate else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastContacted, relativeTo: Date())
    }

    private func locationAndLocalTime(location: String, now: Date) -> String {
        guard let timeZone = lead.resolvedTimeZone else { return location }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(location) · \(formatter.string(from: now)) local time"
    }

    private func open(_ rawValue: String) {
        guard let url = URL(string: rawValue) else { return }
        openURL(url)
    }
}

private struct SalespersonMessageAvatar: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemGray4),
                            Color(uiColor: .systemGray5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.43, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.primary.opacity(0.07), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        guard parts.contains(where: { $0.contains(where: { $0.isLetter }) }) else { return "" }
        return parts
            .prefix(2)
            .compactMap { $0.first(where: { $0.isLetter }) }
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct SalespersonMessageRecipientHeader: View {
    let name: String
    let phone: String

    var body: some View {
        VStack(spacing: 5) {
            SalespersonMessageAvatar(name: name, size: 62)

            HStack(spacing: 4) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            Text(phone)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Message (displayName), (phone)")
    }

    private var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? phone
    }
}

private struct SalespersonMessageComposeBar: View {
    @Binding var text: String
    let placeholder: String
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: 6) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.leading, 12)
                    .padding(.vertical, 9)
                    .disabled(isSending)
                    .submitLabel(.send)
                    .onSubmit {
                        guard canSend else { return }
                        onSend()
                    }

                Button(action: onSend) {
                    Group {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(canSend ? Color(uiColor: .systemBlue) : Color.secondary.opacity(0.38), in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
                .padding(.trailing, 3)
                .padding(.bottom, 3)
            }
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(Color.secondary.opacity(0.28), lineWidth: 0.75)
            )
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

private struct SalespersonDiallerTextSheet: View {
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(viewModel: SalespersonDiallerViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.textDropBody)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let lead = viewModel.selectedLead {
                    SalespersonMessageRecipientHeader(
                        name: lead.name.nilIfEmpty ?? lead.displayBusinessName,
                        phone: lead.phone
                    )
                    Divider()
                }

                Spacer(minLength: 24)

                if let error = viewModel.errorMessage?.nilIfEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                SalespersonMessageComposeBar(
                    text: $draft,
                    placeholder: "Text Message",
                    isSending: viewModel.isSendingCallbackText,
                    canSend: canSend,
                    onSend: send
                )
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSend: Bool {
        !viewModel.isSendingCallbackText
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        Task {
            if await viewModel.sendTextMessage(draft) {
                dismiss()
            }
        }
    }
}

private struct SalespersonDiallerEmailSheet: View {
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipient: String
    @State private var subject = ""
    @State private var messageBody = ""

    init(viewModel: SalespersonDiallerViewModel) {
        self.viewModel = viewModel
        _recipient = State(initialValue: viewModel.email)
        _subject = State(initialValue: SalespersonDemoEmailTemplate.subject)
        _messageBody = State(initialValue: SalespersonDemoEmailTemplate.body(recipientName: viewModel.selectedLead?.name))
    }

    var body: some View {
        SalespersonEmailComposer(
            recipient: $recipient,
            subject: $subject,
            messageBody: $messageBody,
            recipientName: viewModel.selectedLead?.name,
            recipientIsEditable: true,
            isSending: viewModel.isSendingEmail,
            errorMessage: viewModel.errorMessage,
            onCancel: { dismiss() },
            onSend: sendEmail
        )
        .onChange(of: recipient) { _, updatedRecipient in
            viewModel.associateEmailWithSelectedLead(updatedRecipient)
        }
    }

    private func sendEmail() {
        Task {
            if await viewModel.sendEmailMessage(to: recipient, subject: subject, body: messageBody) {
                dismiss()
            }
        }
    }
}

private struct SalespersonDiallerMeetingSheet: View {
    let lead: SalespersonDiallerLead
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var title: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var attendeeEmail: String
    @State private var notes = ""
    @State private var addToAppleCalendar = true
    @State private var isSaving = false
    @State private var isCheckingZoom = true
    @State private var isConnectingZoom = false
    @State private var isZoomConnected = false
    @State private var zoomEmail: String?
    @State private var errorMessage: String?

    init(lead: SalespersonDiallerLead, viewModel: SalespersonDiallerViewModel) {
        self.lead = lead
        self.viewModel = viewModel
        let start = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        _title = State(initialValue: "Meeting with \(lead.displayBusinessName)")
        _startAt = State(initialValue: start)
        _endAt = State(initialValue: Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start)
        _attendeeEmail = State(initialValue: lead.email ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Zoom") {
                    if isCheckingZoom {
                        HStack {
                            ProgressView()
                            Text("Checking Zoom connection…")
                                .foregroundStyle(.secondary)
                        }
                    } else if isZoomConnected {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Zoom connected")
                                if let zoomEmail = zoomEmail?.nilIfEmpty {
                                    Text(zoomEmail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "video.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button {
                            connectZoom()
                        } label: {
                            HStack {
                                Label("Connect Zoom", systemImage: "video.fill")
                                Spacer()
                                if isConnectingZoom {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isConnectingZoom)
                    }
                }

                Section {
                    TextField("Meeting title", text: $title)
                    DatePicker("Starts", selection: $startAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $endAt, in: startAt..., displayedComponents: [.date, .hourAndMinute])
                }

                Section("Guest") {
                    TextField("Email address", text: $attendeeEmail)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Your calendar") {
                    Toggle("Add to Apple Calendar", isOn: $addToAppleCalendar)
                    Text("Includes the Zoom link and a reminder 10 minutes before the meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 90)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Meeting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Creating…" : "Create") {
                        createMeeting()
                    }
                    .disabled(!canCreateMeeting)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            await refreshZoomStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshZoomStatus() }
        }
    }

    private var canCreateMeeting: Bool {
        let cleanEmail = attendeeEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailIsValid = cleanEmail.isEmpty || cleanEmail.contains("@")
        return isZoomConnected
            && !isCheckingZoom
            && !isSaving
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && endAt > startAt
            && emailIsValid
    }

    @MainActor
    private func refreshZoomStatus() async {
        isCheckingZoom = true
        defer { isCheckingZoom = false }
        do {
            let status = try await ZoomMeetingAPI.shared.status()
            isZoomConnected = status.connected
            zoomEmail = status.email
            if status.connected {
                errorMessage = nil
            }
        } catch {
            isZoomConnected = false
            zoomEmail = nil
            errorMessage = error.localizedDescription
        }
    }

    private func connectZoom() {
        guard !isConnectingZoom else { return }
        isConnectingZoom = true
        errorMessage = nil
        Task {
            do {
                let url = try await ZoomMeetingAPI.shared.authorizeURL()
                isConnectingZoom = false
                openURL(url)
            } catch {
                isConnectingZoom = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createMeeting() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let attendeeEmails = attendeeEmail.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty.map { [$0] } ?? []
        let draft = ZoomMeetingDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startAt: startAt,
            endAt: endAt,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            attendeeEmails: attendeeEmails,
            workspaceId: WorkspaceContext.shared.workspaceId?.uuidString,
            contactName: lead.name.nilIfEmpty,
            timeZone: TimeZone.current.identifier
        )

        Task {
            do {
                let result = try await ZoomMeetingAPI.shared.createMeeting(draft)
                var addedToAppleCalendar = false
                var appleCalendarWarning: String?
                if addToAppleCalendar, let joinURL = result.meeting.conferenceJoinURL {
                    do {
                        try await AppleCalendarService.shared.addMeeting(
                            title: result.meeting.title,
                            startAt: result.meeting.startAt,
                            endAt: result.meeting.endAt,
                            notes: result.meeting.notes,
                            joinURL: joinURL
                        )
                        addedToAppleCalendar = true
                    } catch {
                        appleCalendarWarning = error.localizedDescription
                    }
                }
                if result.invitationsRequested > 0, result.invitationsSent > 0 {
                    viewModel.statusMessage = addedToAppleCalendar
                        ? "Zoom meeting booked, invitation sent, and added to Apple Calendar."
                        : "Zoom meeting booked and invitation sent."
                } else if result.invitationsRequested > 0 {
                    viewModel.statusMessage = "Zoom meeting booked. Invitation delivery is not configured."
                } else {
                    viewModel.statusMessage = addedToAppleCalendar
                        ? "Zoom meeting booked and added to Apple Calendar."
                        : "Zoom meeting booked."
                }
                if let appleCalendarWarning {
                    viewModel.statusMessage = "\(viewModel.statusMessage ?? "Zoom meeting booked.") \(appleCalendarWarning)"
                }
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct SalespersonDiallerListsSheet: View {
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss
    let onOpenInLeads: (SalespersonDiallerListGroup) -> Void

    var body: some View {
        NavigationStack {
            List {
                if viewModel.leadLists.isEmpty {
                    ContentUnavailableView("No dialler lists", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(viewModel.leadLists) { list in
                        Section {
                            Button {
                                viewModel.openList(list)
                                dismiss()
                            } label: {
                                SalespersonDiallerListSummaryRow(list: list)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)

                            Button {
                                onOpenInLeads(list)
                            } label: {
                                Label("Open in Leads", systemImage: "person.2")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct SalespersonCompanyResearchSheet: View {
    let leadId: UUID
    let displayBusinessName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var response: SalespersonCompanyResearchResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didAutoStart = false

    init(lead: SalespersonDiallerLead) {
        leadId = lead.id
        displayBusinessName = lead.displayBusinessName
    }

    init(lead: SalespersonLeadMasterRow) {
        leadId = lead.id
        displayBusinessName = lead.company?.nilIfEmpty ?? lead.name
    }

    private var research: SalespersonCompanyResearchRecord? { response?.latest }

    var body: some View {
        NavigationStack {
            Group {
                if let research, let result = research.result {
                    List {
                        if let website = result.website, let url = externalURL(website) {
                            Section("Website") {
                                Button { openURL(url) } label: {
                                    Label(website, systemImage: "globe")
                                        .lineLimit(2)
                                }
                            }
                        }

                        if let instagram = result.instagram, let url = externalURL(instagram) {
                            Section("Instagram") {
                                Button { openURL(url) } label: {
                                    Label(instagram, systemImage: "camera")
                                        .lineLimit(2)
                                }
                            }
                        }

                        if result.timeInBusiness != nil || result.googleReviews != nil {
                            Section("Business") {
                                if let timeInBusiness = result.timeInBusiness {
                                    LabeledContent("Time in business", value: timeInBusiness)
                                }
                                if let googleReviews = result.googleReviews {
                                    LabeledContent("Google reviews", value: googleReviews)
                                }
                            }
                        }

                        if !result.hasVisibleResearch {
                            Section {
                                ContentUnavailableView(
                                    "No verified details found",
                                    systemImage: "magnifyingglass",
                                    description: Text("Website, Instagram, business age, and Google reviews were not available.")
                                )
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                } else if response?.active != nil || isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Researching public sources…")
                            .font(.headline)
                        Text("You can close this sheet. The research will keep running in the background.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                } else {
                    ContentUnavailableView(
                        "No company research",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text(errorMessage ?? "Research this company using verified public sources.")
                    )
                }
            }
            .navigationTitle("Company Research")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await startResearch() }
                    } label: {
                        Label(research == nil ? "Research" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || response?.active != nil)
                }
            }
            .task { await loadAndStartIfNeeded() }
        }
    }

    private func externalURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: "https://\(value)")
    }

    @MainActor
    private func loadAndStartIfNeeded() async {
        await refresh()
        guard response?.latest == nil, response?.active == nil, !didAutoStart, errorMessage == nil else {
            await pollWhileActive()
            return
        }
        didAutoStart = true
        await startResearch()
    }

    @MainActor
    private func refresh() async {
        isLoading = response == nil
        defer { isLoading = false }
        do {
            response = try await SalespersonMobileAPI.shared.fetchCompanyResearch(leadId: leadId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func startResearch() async {
        isLoading = true
        errorMessage = nil
        do {
            try await SalespersonMobileAPI.shared.startCompanyResearch(leadId: leadId)
            response = try await SalespersonMobileAPI.shared.fetchCompanyResearch(leadId: leadId)
            isLoading = false
            await pollWhileActive()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func pollWhileActive() async {
        while response?.active != nil && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}

private struct SalespersonListResearchSheet: View {
    let list: SalespersonDiallerSmartListOption
    @Environment(\.dismiss) private var dismiss
    @State private var response: SalespersonCompanyResearchBatchResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isConfirmationPresented = false

    private var completed: Int {
        (response?.counts?["completed"] ?? 0) + (response?.counts?["partial"] ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Companies", value: "Up to \(min(list.count, 100))")
                    if let response {
                        LabeledContent("Status", value: response.batch.status.capitalized)
                        LabeledContent("Completed", value: "\(completed)/\(response.batch.requestedCount)")
                        LabeledContent("Skipped/current", value: response.batch.skippedCount.formatted())
                        if let failed = response.counts?["failed"], failed > 0 {
                            LabeledContent("Failed", value: failed.formatted()).foregroundStyle(.red)
                        }
                    }
                } footer: {
                    Text("Research uses your OpenAI account. Results are shared between iOS and web and remain attached to each company.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    if let failed = response?.counts?["failed"], failed > 0 {
                        Button {
                            Task { await retryFailed() }
                        } label: {
                            Label("Retry \(failed) Failed", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoading)
                    }
                    Button {
                        isConfirmationPresented = true
                    } label: {
                        Label(response == nil ? "Research list" : "Refresh all", systemImage: "sparkle.magnifyingglass")
                    }
                    .disabled(isLoading || response?.batch.isActive == true || list.count == 0)
                }
            }
            .navigationTitle(list.name)
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if isLoading { ProgressView() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Research \(min(list.count, 100)) companies?", isPresented: $isConfirmationPresented, titleVisibility: .visible) {
                Button("Use OpenAI to Research") { Task { await start(refreshAll: response != nil) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only publicly accessible sources will be used. Existing research from the last 30 days is skipped unless this is a refresh.")
            }
        }
    }

    @MainActor
    private func retryFailed() async {
        guard let batchId = response?.batch.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await SalespersonMobileAPI.shared.retryCompanyResearch(batchId: batchId)
            response = try await SalespersonMobileAPI.shared.fetchCompanyResearch(batchId: batchId)
            isLoading = false
            await pollWhileActive()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func start(refreshAll: Bool) async {
        isLoading = true
        errorMessage = nil
        do {
            response = try await SalespersonMobileAPI.shared.startCompanyResearch(listId: list.id, refreshAll: refreshAll)
            isLoading = false
            await pollWhileActive()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func pollWhileActive() async {
        while response?.batch.isActive == true && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard let batchId = response?.batch.id, !Task.isCancelled else { return }
            do {
                response = try await SalespersonMobileAPI.shared.fetchCompanyResearch(batchId: batchId)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }
}

private struct SalespersonDiallerSmartListSheet: View {
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLeadGeneratorPresented = false
    @State private var researchList: SalespersonDiallerSmartListOption?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingSmartLists {
                    ProgressView()
                }

                ForEach(viewModel.smartLists) { list in
                    VStack(spacing: 8) {
                        Button {
                            Task {
                                await viewModel.importSmartList(list)
                                dismiss()
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.title3)
                                .foregroundStyle(Color.flyrPrimary)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(list.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(list.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                Text("\(list.dialableCount) dialable of \(list.count)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer(minLength: 8)
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.flyrPrimary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isImportingSmartList || list.dialableCount == 0)

                        Button {
                            researchList = list
                        } label: {
                            Label("Research list", systemImage: "sparkle.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderless)
                        .disabled(list.count == 0)
                    }
                }
            }
            .navigationTitle("Add Created List")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if !viewModel.isLoadingSmartLists && viewModel.smartLists.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("No created lists")
                            .font(.title2.weight(.bold))
                        Text("Lists created from Google Places or anywhere else in WolfGrid will appear here on both iOS and web.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button {
                            isLeadGeneratorPresented = true
                        } label: {
                            Label("Create List", systemImage: "sparkle.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isLeadGeneratorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create list")

                    Button {
                        Task { await viewModel.loadSmartLists() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingSmartLists || viewModel.isCreatingSmartList)
                }
            }
            .fullScreenCover(isPresented: $isLeadGeneratorPresented, onDismiss: {
                Task { await viewModel.loadSmartLists() }
            }) {
                SalespersonLeadScraperView(
                    onOpenLeads: { _ in
                        isLeadGeneratorPresented = false
                    },
                    onOpenDialler: { _ in
                        isLeadGeneratorPresented = false
                    }
                )
            }
            .sheet(item: $researchList) { list in
                SalespersonListResearchSheet(list: list)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

private struct SalespersonDiallerRecordingsSheet: View {
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingRecordings {
                    ProgressView()
                }

                ForEach(viewModel.recordings) { group in
                    Section {
                        ForEach(group.recordings) { recording in
                            HStack(spacing: 12) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.flyrPrimary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.weight(.semibold))
                                    Text(recording.durationSeconds.map(formatDuration) ?? "Duration pending")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    Task { await viewModel.exportRecording(recording, leadName: group.leadName) }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .disabled(viewModel.isExportingRecording)
                            }
                            .padding(.vertical, 3)
                        }
                    } header: {
                        HStack {
                            Text(group.leadName)
                            if group.isStarred {
                                Image(systemName: "star.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Content")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if !viewModel.isLoadingRecordings && viewModel.recordings.isEmpty {
                    ContentUnavailableView("No recordings", systemImage: "waveform")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadRecordings(starredOnly: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingRecordings)
                }
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 { return "\(remainder)s" }
        return "\(minutes)m \(String(format: "%02d", remainder))s"
    }
}

private enum SalespersonFollowUpChoice: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case custom

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

private struct SalespersonDiallerFollowUpSheet: View {
    let lead: SalespersonDiallerLead
    let onSave: (String, Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: SalespersonFollowUpChoice = .today
    @State private var title: String
    @State private var customDate: Date

    init(lead: SalespersonDiallerLead, onSave: @escaping (String, Date) -> Void) {
        self.lead = lead
        self.onSave = onSave
        _title = State(initialValue: "Follow up with \(lead.displayBusinessName)")
        _customDate = State(initialValue: Self.defaultDate(for: .today))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Follow up title", text: $title)

                    Picker("When", selection: $choice) {
                        ForEach(SalespersonFollowUpChoice.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: choice) { _, newValue in
                        customDate = Self.defaultDate(for: newValue)
                    }

                    DatePicker(
                        "Date and time",
                        selection: $customDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle("Follow Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        onSave(title, customDate)
                    }
                }
            }
        }
    }

    private static func defaultDate(for choice: SalespersonFollowUpChoice) -> Date {
        let calendar = Calendar.current
        let now = Date()
        switch choice {
        case .today:
            return calendar.date(byAdding: .hour, value: 4, to: now) ?? now
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case .custom:
            return calendar.date(byAdding: .hour, value: 4, to: now) ?? now
        }
    }
}

struct SalespersonInboxView: View {
    @StateObject private var viewModel: SalespersonInboxViewModel
    @StateObject private var mailboxViewModel = SalespersonEmailMailboxViewModel()
    @State private var isComposingEmail = false
    @State private var isComposingMessage = false
    @State private var isStartingCall = false
    @State private var isShowingMailboxSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Binding private var isShowingThread: Bool
    private let title: String

    init(
        source: String = "all",
        title: String = "Messages",
        isShowingThread: Binding<Bool> = .constant(false)
    ) {
        _viewModel = StateObject(wrappedValue: SalespersonInboxViewModel(selectedSource: source))
        _isShowingThread = isShowingThread
        self.title = title
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.selectedSource == "email",
                   mailboxViewModel.hasLoaded,
                   !mailboxViewModel.isConnected {
                    SalespersonEmailMailboxRow(
                        mailbox: mailboxViewModel.mailbox,
                        isLoading: mailboxViewModel.isLoading,
                        action: { isShowingMailboxSettings = true }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                ForEach(viewModel.threads) { thread in
                    NavigationLink {
                        SalespersonInboxThreadView(
                            thread: thread,
                            viewModel: viewModel,
                            isShowingThread: $isShowingThread
                        )
                    } label: {
                        SalespersonInboxRow(thread: thread)
                    }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(thread.needsResponse ? Color.flyrPrimary.opacity(0.08) : Color(.systemBackground))
                }
            }
            .listStyle(.plain)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.threads.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(emptyMessage, systemImage: icon(for: viewModel.selectedSource))
                        if viewModel.selectedSource == "email", !mailboxViewModel.isConnected {
                            Button("Connect Email") {
                                isShowingMailboxSettings = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.flyrPrimary)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                floatingActionButton
                    .padding(18)
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .task(id: viewModel.selectedSource) {
                guard viewModel.selectedSource == "email" else { return }
                await mailboxViewModel.load()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await viewModel.load() }
            }
            .onChange(of: viewModel.selectedSource) { _, _ in
                Task { await viewModel.load() }
            }
            .sheet(isPresented: $isComposingEmail) {
                SalespersonNewEmailSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $isComposingMessage) {
                SalespersonNewMessageSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $isStartingCall) {
                SalespersonManualDialPad { number in
                    await viewModel.callManual(number: number)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isShowingMailboxSettings) {
                SalespersonEmailMailboxSettingsView(viewModel: mailboxViewModel)
            }
            .alert(title, isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var floatingActionButton: some View {
        switch viewModel.selectedSource {
        case "sms":
            floatingButton(systemImage: "message.fill", accessibilityLabel: "New message") {
                isComposingMessage = true
            }
        case "email":
            floatingButton(systemImage: "square.and.pencil", accessibilityLabel: "Compose email") {
                if mailboxViewModel.isConnected {
                    isComposingEmail = true
                } else {
                    isShowingMailboxSettings = true
                }
            }
        case "call":
            floatingButton(systemImage: "phone.fill", accessibilityLabel: "Start a call") {
                isStartingCall = true
            }
        default:
            EmptyView()
        }
    }

    private func floatingButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.flyrPrimary, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func icon(for source: String) -> String {
        switch source {
        case "all": return "message"
        case "sms": return "message"
        case "email": return "envelope"
        case "call": return "phone"
        default: return "bell"
        }
    }

    private func label(for source: String) -> String {
        switch source {
        case "all": return "All"
        case "sms": return "Messages"
        case "email": return "Email"
        case "call": return "Calls"
        default: return source.capitalized
        }
    }

    private var emptyMessage: String {
        viewModel.selectedSource == "all" ? "No messages yet" : "No \(label(for: viewModel.selectedSource).lowercased())"
    }
}

private struct SalespersonInboxRow: View {
    let thread: SalespersonInboxThread

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                SalespersonMessageAvatar(name: thread.rowTitle, size: 44)
                if thread.unreadCount > 0 {
                    Circle()
                        .fill(Color(uiColor: .systemBlue))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(thread.rowTitle)
                        .font(.subheadline.weight(thread.unreadCount > 0 ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(thread.latestAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(thread.rowPreview ?? thread.subtitle?.normalizedInboxLine ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 68, alignment: .center)
        .contentShape(Rectangle())
    }
}

private struct SalespersonInboxThreadView: View {
    @State var thread: SalespersonInboxThread
    @ObservedObject var viewModel: SalespersonInboxViewModel
    @Binding var isShowingThread: Bool
    @State private var draft = ""
    @State private var emailSubject = ""
    @State private var isComposingEmail = false
    @State private var selectedMediaItem: PhotosPickerItem?
    @State private var pendingAttachment: SalespersonInboxPendingAttachment?
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(thread.events.enumerated()), id: \.element.id) { index, event in
                        if shouldShowTimestamp(before: index) {
                            SalespersonMessageTimestamp(date: event.occurredAt)
                                .padding(.vertical, 9)
                        }
                        SalespersonInboxThreadEventView(
                            event: event,
                            showsDeliveryStatus: showsDeliveryStatus(after: index)
                        )
                        .id(event.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemBackground))
            .onAppear {
                if let lastId = thread.events.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
            .onChange(of: thread.events.count) { _, _ in
                if let lastId = thread.events.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEmailThread { emailComposerLauncher } else { textComposer }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    SalespersonMessageAvatar(name: thread.rowTitle, size: 32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(thread.rowTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let phone = thread.textPhone?.nilIfEmpty, !isEmailThread {
                            Text(phone)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(thread.rowTitle)
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isEmailThread {
                    Button {
                        isComposingEmail = true
                    } label: {
                        Image(systemName: "envelope")
                    }
                    .disabled(!thread.canEmail)
                    .accessibilityLabel("Compose email")
                } else if let phone = thread.textPhone,
                          let url = URL(string: "tel://\(phone.normalizedPhoneDigits)") {
                    Link(destination: url) {
                        Image(systemName: "phone.fill")
                    }
                }
            }
        }
        .alert("Messages", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isComposingEmail) {
            SalespersonEmailComposer(
                recipient: .constant(thread.emailRecipient ?? ""),
                subject: $emailSubject,
                messageBody: $draft,
                recipientName: thread.contact?.displayName ?? thread.rowTitle,
                recipientIsEditable: false,
                isSending: viewModel.isSending,
                errorMessage: viewModel.errorMessage,
                onCancel: { isComposingEmail = false },
                onSend: {
                    Task {
                        if await sendEmail() {
                            isComposingEmail = false
                        }
                    }
                }
            )
        }
        .task {
            isShowingThread = true
            if emailSubject.isEmpty {
                emailSubject = Self.replySubject(for: thread)
            }
            await viewModel.markThreadRead(thread)
        }
        .onDisappear {
            isShowingThread = false
        }
        .onChange(of: selectedMediaItem) { _, item in
            guard let item else { return }
            Task { await loadAttachment(from: item) }
        }
    }

    private var textComposer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let status = viewModel.statusMessage?.nilIfEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let pendingAttachment {
                HStack(spacing: 9) {
                    Group {
                        if let preview = pendingAttachment.previewImage {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "video.fill")
                                .font(.title2)
                                .foregroundStyle(Color.flyrPrimary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.flyrPrimary.opacity(0.1))
                        }
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Text(pendingAttachment.isVideo ? "Video" : "Photo")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button {
                        self.pendingAttachment = nil
                        selectedMediaItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Remove attachment")
                }
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedMediaItem, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
                .disabled(!thread.canText || viewModel.isSending)
                .accessibilityLabel("Add a photo or video")

                HStack(alignment: .bottom, spacing: 6) {
                    TextField(thread.canText ? "Message" : "No phone on contact", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .padding(.leading, 12)
                        .padding(.vertical, 9)
                        .disabled(!thread.canText || viewModel.isSending)

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(canSendText ? Color(uiColor: .systemBlue) : Color.secondary.opacity(0.45), in: Circle())
                    }
                    .disabled(!canSendText)
                    .accessibilityLabel("Send message")
                    .padding(.trailing, 3)
                    .padding(.bottom, 3)
                }
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.secondary.opacity(0.24), lineWidth: 1))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial)
    }

    private var emailComposerLauncher: some View {
        VStack(spacing: 7) {
            if let status = viewModel.statusMessage?.nilIfEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                isComposingEmail = true
            } label: {
                Label(thread.canEmail ? "Reply by email" : "No email on contact", systemImage: "envelope.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(thread.canEmail ? Color.flyrPrimary : Color.secondary.opacity(0.35))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!thread.canEmail || viewModel.isSending)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    private var isEmailThread: Bool {
        viewModel.selectedSource == "email" || thread.latestSource == "email"
    }

    private var canSendText: Bool {
        thread.canText
            && !viewModel.isSending
            && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachment != nil)
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!body.isEmpty || pendingAttachment != nil), let phone = thread.textPhone else { return }

        let pendingID = "pending-sms-\(UUID().uuidString)"
        let originalThread = thread
        let attachment = pendingAttachment
        draft = ""
        pendingAttachment = nil
        selectedMediaItem = nil
        thread = threadByAddingPendingText(
            body,
            phone: phone,
            pendingID: pendingID,
            sentAt: Date(),
            attachmentDescription: attachment.map { $0.isVideo ? "Video" : "Photo" }
        )

        if let refreshed = await viewModel.sendText(in: thread, body: body, pendingAttachment: attachment) {
            thread = refreshed
        } else {
            thread = originalThread
            if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft = body
            }
            if pendingAttachment == nil {
                pendingAttachment = attachment
            }
        }
    }

    private func loadAttachment(from item: PhotosPickerItem) async {
        do {
            guard let originalData = try await item.loadTransferable(type: Data.self) else {
                throw SalespersonAPIError.status(0, "The selected photo or video could not be loaded.")
            }
            let videoType = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) })
            let isVideo = videoType != nil
            let mimeType: String
            let fileExtension: String
            let data: Data
            let preview: UIImage?
            if isVideo {
                mimeType = videoType?.preferredMIMEType ?? "video/quicktime"
                fileExtension = videoType?.preferredFilenameExtension ?? "mov"
                data = originalData
                preview = nil
            } else {
                let image = UIImage(data: originalData)
                mimeType = "image/jpeg"
                fileExtension = "jpg"
                data = image?.jpegData(compressionQuality: 0.72) ?? originalData
                preview = image
            }
            guard data.count <= 10 * 1_024 * 1_024 else {
                throw SalespersonAPIError.status(413, "Choose a photo or video smaller than 10 MB.")
            }
            pendingAttachment = SalespersonInboxPendingAttachment(
                data: data,
                fileName: "message-\(UUID().uuidString).\(fileExtension)",
                mimeType: mimeType,
                previewImage: preview
            )
            composerFocused = true
        } catch {
            selectedMediaItem = nil
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func shouldShowTimestamp(before index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = thread.events[index].occurredAt
        let previous = thread.events[index - 1].occurredAt
        return !Calendar.current.isDate(current, inSameDayAs: previous)
            || current.timeIntervalSince(previous) >= 15 * 60
    }

    private func showsDeliveryStatus(after index: Int) -> Bool {
        let event = thread.events[index]
        guard event.isOutboundMessage else { return false }
        guard index + 1 < thread.events.count else { return true }
        return !thread.events[index + 1].isOutboundMessage
    }

    private func threadByAddingPendingText(
        _ body: String,
        phone: String,
        pendingID: String,
        sentAt: Date,
        attachmentDescription: String?
    ) -> SalespersonInboxThread {
        let event = SalespersonInboxEvent(
            id: pendingID,
            source: "sms",
            kind: "sms_item",
            direction: "outbound",
            title: "Sending message",
            preview: body.nilIfEmpty ?? attachmentDescription,
            body: body,
            status: "sending",
            occurredAt: sentAt,
            readAt: sentAt,
            fromLabel: nil,
            fromEmail: nil,
            fromPhone: nil,
            toLabel: thread.contact?.displayName,
            toEmail: nil,
            toPhone: phone,
            contactId: thread.contactId,
            href: nil
        )

        return SalespersonInboxThread(
            id: thread.id,
            contactId: thread.contactId,
            contact: thread.contact,
            title: thread.title,
            subtitle: thread.subtitle,
            primaryPhone: thread.primaryPhone ?? phone,
            primaryEmail: thread.primaryEmail,
            latestAt: sentAt,
            latestSource: "sms",
            latestPreview: body.nilIfEmpty ?? attachmentDescription,
            unreadCount: thread.unreadCount,
            needsResponse: false,
            events: (thread.events + [event]).sorted { $0.occurredAt < $1.occurredAt }
        )
    }

    private func sendEmail() async -> Bool {
        guard let recipient = thread.emailRecipient else { return false }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        if let refreshed = await viewModel.sendEmail(
            contactId: thread.contactId,
            to: recipient,
            subject: emailSubject,
            body: body,
            matching: thread
        ) {
            draft = ""
            thread = refreshed
            emailSubject = Self.replySubject(for: refreshed)
            return true
        } else if viewModel.errorMessage == nil {
            draft = ""
            return true
        }
        return false
    }

    private static func replySubject(for thread: SalespersonInboxThread) -> String {
        let subject = thread.events.reversed()
            .first(where: { $0.source == "email" })?
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !subject.isEmpty else { return "Following up" }
        return subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }
}

private struct SalespersonNewEmailSheet: View {
    @ObservedObject var viewModel: SalespersonInboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var subject = ""
    @State private var messageBody = ""

    var body: some View {
        SalespersonEmailComposer(
            recipient: $recipient,
            subject: $subject,
            messageBody: $messageBody,
            recipientName: nil,
            recipientIsEditable: true,
            isSending: viewModel.isSending,
            errorMessage: viewModel.errorMessage,
            onCancel: { dismiss() },
            onSend: { Task { await send() } }
        )
    }

    private func send() async {
        _ = await viewModel.sendEmail(
            contactId: nil,
            to: recipient,
            subject: subject,
            body: messageBody
        )
        if viewModel.errorMessage == nil {
            dismiss()
        }
    }
}

private struct SalespersonNewMessageSheet: View {
    @ObservedObject var viewModel: SalespersonInboxViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var messageBody = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case recipient
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("To:")
                        .foregroundStyle(.secondary)

                    TextField("Phone number", text: $recipient)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .recipient)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .font(.body)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)

                Divider()
                Spacer(minLength: 24)

                if let error = viewModel.errorMessage?.nilIfEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                SalespersonMessageComposeBar(
                    text: $messageBody,
                    placeholder: "Text Message",
                    isSending: viewModel.isSending,
                    canSend: canSend,
                    onSend: sendMessage
                )
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSending)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isSending)
        .onAppear { focusedField = .recipient }
    }

    private var canSend: Bool {
        !viewModel.isSending
            && recipient.normalizedPhoneDigits.count >= 8
            && !messageBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        if await viewModel.sendNewText(to: recipient, body: messageBody) {
            dismiss()
        }
    }

    private func sendMessage() {
        guard canSend else { return }
        Task { await send() }
    }
}

private struct SalespersonInboxThreadEventView: View {
    let event: SalespersonInboxEvent
    var showsDeliveryStatus = false

    var body: some View {
        if event.source == "sms" {
            messageBubble
        } else {
            timelineCard
        }
    }

    private var messageBubble: some View {
        HStack {
            if event.isOutboundMessage { Spacer(minLength: 44) }

            VStack(alignment: event.isOutboundMessage ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(event.attachments ?? []) { attachment in
                        attachmentView(attachment)
                    }

                    if let text = (event.body ?? event.preview)?.nilIfEmpty {
                        Text(text)
                            .font(.body)
                            .foregroundStyle(event.isOutboundMessage ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }
                }
                .background(event.isOutboundMessage ? Color(uiColor: .systemBlue) : Color(.secondarySystemGroupedBackground))
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 19,
                        bottomLeadingRadius: event.isOutboundMessage ? 19 : 5,
                        bottomTrailingRadius: event.isOutboundMessage ? 5 : 19,
                        topTrailingRadius: 19,
                        style: .continuous
                    )
                )

                if event.status == "sending" {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color(uiColor: .systemBlue))
                        .frame(width: 72)
                        .accessibilityLabel("Sending message")
                } else if showsDeliveryStatus {
                    Text(deliveryStatus)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }

            if !event.isOutboundMessage { Spacer(minLength: 44) }
        }
    }

    @ViewBuilder
    private func attachmentView(_ attachment: SalespersonInboxAttachment) -> some View {
        if let url = URL(string: attachment.url) {
            if attachment.isVideo {
                Link(destination: url) {
                    ZStack {
                        Color.black.opacity(0.78)
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    .frame(width: 220, height: 150)
                }
                .accessibilityLabel("Open video")
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 220, height: 180)
                .clipped()
            }
        }
    }

    private var deliveryStatus: String {
        switch event.status.lowercased() {
        case "delivered", "finalized": return "Delivered"
        case "failed", "delivery_failed": return "Not Delivered"
        default: return "Sent"
        }
    }

    private var timelineCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: event.source))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.flyrPrimary)
                .frame(width: 28, height: 28)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(event.occurredAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let body = (event.body ?? event.preview)?.nilIfEmpty {
                    Text(body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func icon(for source: String) -> String {
        switch source {
        case "sms": return "message"
        case "email": return "envelope"
        case "call": return "phone"
        default: return "bell"
        }
    }
}

private struct SalespersonMessageTimestamp: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(date.formatted(date: .complete, time: .shortened))
    }

    private var label: String {
        if Calendar.current.isDateInToday(date) {
            return "Today \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

struct SalespersonTasksView: View {
    @StateObject private var viewModel = SalespersonTasksViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Due date", selection: $viewModel.selectedDueFilter) {
                    ForEach(SalespersonTaskDueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                taskList
            }
            .task { await viewModel.load() }
            .alert("Follow Up", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var taskList: some View {
        List {
            ForEach(viewModel.filteredItems) { item in
                taskRow(item)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Complete") { Task { await viewModel.complete(item) } }
                            .tint(Color.flyrPrimary)
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.isLoading { ProgressView() }
            else if viewModel.filteredItems.isEmpty {
                ContentUnavailableView(
                    viewModel.selectedDueFilter == .today ? "No tasks today" : "No future tasks",
                    systemImage: "checklist"
                )
            }
        }
        .refreshable { await viewModel.load() }
    }

    private func taskRow(_ item: SalespersonCalendarItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: item.eventType))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.flyrPrimary)
                .frame(width: 28, height: 28)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if let contactName = item.contactName { Text(contactName).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 6) {
                    Text(item.startAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if viewModel.isOverdue(item) {
                        Label("Overdue", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func icon(for eventType: String) -> String {
        switch eventType {
        case SalespersonCalendarEventType.call.rawValue: return "phone"
        case SalespersonCalendarEventType.followUp.rawValue: return "arrow.uturn.forward"
        default: return "checklist"
        }
    }
}

private extension ISO8601DateFormatter {
    static let flyrInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let flyrInternetNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var normalizedInboxLine: String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var normalizedPhoneDigits: String {
        filter(\.isNumber)
    }
}
