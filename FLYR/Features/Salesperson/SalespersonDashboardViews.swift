import Foundation
import Combine
import SwiftUI
import Supabase
import UIKit

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
    var name: String
    var phone: String
    var company: String?
    var email: String?
    var website: String?
    var websiteDomain: String?
    var listId: String?
    var listName: String?
    var latestCallRecording: SalespersonDiallerRecordingSummary?
    var isStarred: Bool?
    var disposition: String?
    var notes: String?
    var calledAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case phone
        case company
        case email
        case website
        case websiteDomain = "website_domain"
        case listId = "list_id"
        case listName = "list_name"
        case latestCallRecording = "latest_call_recording"
        case isStarred = "is_starred"
        case disposition
        case notes
        case calledAt = "called_at"
        case createdAt = "created_at"
    }

    var displayBusinessName: String {
        company?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "Unnamed business"
    }

    var listGroupTitle: String {
        if let listName = listName?.nilIfEmpty {
            return listName
        }
        guard let createdAt else { return "Dialler queue" }
        return "Dialler queue - \(createdAt.formatted(date: .abbreviated, time: .omitted))"
    }

    var listGroupId: String {
        listId?.nilIfEmpty ?? listGroupTitle.lowercased()
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
    let id: UUID
    let callRequestId: String
    let toNumber: String?
    let fromNumber: String?
    let status: String?
    let disposition: String?

    enum CodingKeys: String, CodingKey {
        case id
        case callRequestId = "call_request_id"
        case toNumber = "to_number_e164"
        case fromNumber = "from_number_e164"
        case status
        case disposition
    }
}

private struct SalespersonDiallerCallResponse: Decodable {
    let call: SalespersonDiallerCall
}

private struct SalespersonDemoMessageResponse: Decodable, Equatable {
    let demoUrl: String
    let demoLinkToken: String?
    let textBody: String?
    let emailSubject: String?
    let emailBody: String?
    let tracked: Bool?
}

private struct SalespersonInboxResponse: Decodable {
    let items: [SalespersonInboxItem]
    let counts: [String: Int]?
}

private struct SalespersonInboxItem: Identifiable, Decodable, Equatable {
    let id: String
    let source: String
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

private struct SalespersonLeadMasterRow: Identifiable, Decodable, Equatable, Hashable {
    let id: UUID
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
    let disposition: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
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
        case listId = "list_id"
        case listName = "list_name"
        case countryCode = "country_code"
        case leadState = "lead_state"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var primaryLine: String {
        phone?.nilIfEmpty ?? address?.nilIfEmpty ?? email?.nilIfEmpty ?? website?.nilIfEmpty ?? "No contact detail"
    }

    var displayName: String {
        company?.nilIfEmpty ?? name.nilIfEmpty ?? "Unnamed lead"
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

    var subtitle: String {
        let newest = createdAt.formatted(date: .abbreviated, time: .omitted)
        let dialable = leads.filter { $0.phone?.nilIfEmpty != nil }.count
        let source = leads.first?.sourceLabel ?? "Leads"
        return "\(count) leads • \(dialable) dialable • \(source) • \(newest)"
    }

    var locationLine: String? {
        let locations = leads
            .compactMap(\.locationLine)
            .filter { !$0.isEmpty }
        return locations.first
    }

    static func makeGroups(from leads: [SalespersonLeadMasterRow]) -> [SalespersonLeadListGroup] {
        let groups = Dictionary(grouping: leads) { lead in
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
        let groups = Dictionary(grouping: leads) { lead in
            lead.listGroupId
        }
        return groups.map { key, rows in
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
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.title < rhs.title
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
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
    }

    struct Links: Decodable, Equatable {
        let opens: Int
        let signups: Int
    }

    struct Revenue: Decodable, Equatable {
        let payingUsers: Int
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
}

private actor SalespersonMobileAPI {
    static let shared = SalespersonMobileAPI()
    private static let fallbackDemoVideoLink = "https://www.flyrpro.app/demo-1?source=DANIELPHILLIPPE"

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
        return try await ContactsService.shared.fetchContacts(
            userID: context.userId,
            workspaceId: context.workspaceId
        )
    }

    private func salespersonLead(from contact: Contact) -> SalespersonLeadMasterRow {
        SalespersonLeadMasterRow(
            id: contact.id,
            name: contact.fullName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? contact.address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Unnamed lead",
            company: nil,
            phone: contact.phone?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            email: contact.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            website: nil,
            address: contact.address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            city: nil,
            region: nil,
            countryCode: nil,
            source: "contacts",
            listId: nil,
            listName: nil,
            leadState: contact.status.rawValue,
            disposition: contact.status == .new ? nil : contact.status.displayName,
            notes: contact.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdAt: contact.createdAt,
            updatedAt: contact.updatedAt
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
            company: nil,
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
            createdAt: contact.createdAt
        )
    }

    private func request(path: String, queryItems: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> URLRequest {
        var components = URLComponents(url: Config.backendAPIURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SalespersonAPIError.badURL }

        let session = try await SupabaseManager.shared.client.auth.session
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SalespersonAPIError.status(0, "No response from server.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode([String: String].self, from: data)["error"])
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            if http.statusCode == 403,
               message.localizedCaseInsensitiveContains("workspace"),
               let retryRequest = await requestByRefreshingWorkspaceId(request) {
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retryRequest)
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
        guard request.httpMethod == nil || request.httpMethod == "GET",
              let url = request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "workspaceId" }) == true else {
            return nil
        }

        await refreshWorkspaceContext()

        guard let workspaceId = await MainActor.run(body: { WorkspaceContext.shared.workspaceId }) else {
            return nil
        }

        components.queryItems = components.queryItems?.map { item in
            item.name == "workspaceId"
                ? URLQueryItem(name: item.name, value: workspaceId.uuidString)
                : item
        }
        guard let retryURL = components.url, retryURL != url else {
            return nil
        }

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
        let contacts = try await ContactsService.shared.fetchContacts(
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

        let updated = try await ContactsService.shared.updateContact(
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
            let response = try decoder.decode(SalespersonDiallerLeadsResponse.self, from: try await data(for: request))
            if !response.leads.isEmpty {
                return response.leads
            }
        } catch SalespersonAPIError.status(404, _) {
            return try await fetchExistingContacts().compactMap(diallerLead(from:))
        } catch SalespersonAPIError.status(403, _) {
            return try await fetchExistingContacts().compactMap(diallerLead(from:))
        }
        return try await fetchExistingContacts().compactMap(diallerLead(from:))
    }

    func fetchDiallerSmartLists() async throws -> [SalespersonDiallerSmartListOption] {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/dialer/smart-list-imports",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        )
        do {
            return try decoder.decode(SalespersonDiallerSmartListsResponse.self, from: try await data(for: request)).lists
        } catch SalespersonAPIError.status(404, _) {
            return []
        }
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
        do {
            let response = try decoder.decode(SalespersonLeadListResponse.self, from: try await data(for: request))
            if !response.leads.isEmpty {
                return response.leads
            }
        } catch SalespersonAPIError.status(404, _) {
            return try await fetchExistingContacts().map(salespersonLead(from:))
        } catch SalespersonAPIError.status(403, _) {
            return try await fetchExistingContacts().map(salespersonLead(from:))
        }
        return try await fetchExistingContacts().map(salespersonLead(from:))
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
        leadIntent: String
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
            leadIntent: leadIntent
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/salesperson/google-places", method: "POST", body: body)
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
            let contacts = try await ContactsService.shared.fetchContacts(
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
                disposition: nil
            )
        }
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

    func prepareDemoMessage(for lead: SalespersonDiallerLead) async throws -> SalespersonDemoMessageResponse {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let email: String?
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            email: lead.email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/leads/\(lead.id.uuidString)/demo-message",
            method: "POST",
            body: body
        )
        do {
            return try decoder.decode(SalespersonDemoMessageResponse.self, from: try await data(for: request))
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            return fallbackDemoMessage()
        }
    }

    func prepareDemoMessage(for lead: SalespersonDiallerLead, email: String?) async throws -> SalespersonDemoMessageResponse {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let email: String?
        }
        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            email: email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/leads/\(lead.id.uuidString)/demo-message",
            method: "POST",
            body: body
        )
        do {
            return try decoder.decode(SalespersonDemoMessageResponse.self, from: try await data(for: request))
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            return fallbackDemoMessage()
        }
    }

    private func fallbackDemoMessage() -> SalespersonDemoMessageResponse {
        let link = Self.fallbackDemoVideoLink
        return SalespersonDemoMessageResponse(
            demoUrl: link,
            demoLinkToken: nil,
            textBody: "Hey, Daniel with FLYR. Here is a quick demo: \(link)",
            emailSubject: "Quick FLYR demo",
            emailBody: "Hey,\n\nDaniel with FLYR here. Here is a quick demo video: \(link)\n\nBest,\nDaniel",
            tracked: false
        )
    }

    func sendDemoText(leadId: UUID, body messageBody: String) async throws -> String? {
        let workspaceId = try await workspaceId()
        struct Payload: Encodable {
            let workspaceId: String
            let body: String
        }
        struct Response: Decodable {
            let warning: String?
        }
        let payload = Payload(workspaceId: workspaceId.uuidString, body: messageBody)
        let body = try encoder.encode(payload)
        let request = try await request(
            path: "api/dialer/leads/\(leadId.uuidString)/sms",
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

    func sendDemoEmail(lead: SalespersonDiallerLead, email: String?, message: SalespersonDemoMessageResponse, notes: String?) async throws -> (SalespersonDiallerLead, String?) {
        let workspaceId = try await workspaceId()
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            throw SalespersonAPIError.status(400, "Add an email before sending the demo.")
        }
        guard let emailBody = message.emailBody?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            throw SalespersonAPIError.status(400, "Demo email is not ready yet.")
        }

        struct Payload: Encodable {
            let workspaceId: String
            let id: String
            let email: String
            let notes: String?
            let saveContact: Bool
            let sendDemoEmail: Bool
            let demoEmailSubject: String?
            let demoEmailBody: String
            let demoLinkToken: String?
        }
        struct Response: Decodable {
            let lead: SalespersonDiallerLead?
            let warning: String?
        }

        let payload = Payload(
            workspaceId: workspaceId.uuidString,
            id: lead.id.uuidString,
            email: email,
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            saveContact: true,
            sendDemoEmail: true,
            demoEmailSubject: message.emailSubject,
            demoEmailBody: emailBody,
            demoLinkToken: message.demoLinkToken
        )
        let body = try encoder.encode(payload)
        let request = try await request(path: "api/dialer/leads", method: "PATCH", body: body)
        do {
            let response = try decoder.decode(Response.self, from: try await data(for: request))
            guard let updatedLead = response.lead else {
                throw SalespersonAPIError.status(500, "Demo email sent, but the lead response was missing.")
            }
            return (updatedLead, response.warning)
        } catch {
            guard isDiallerBackendUnavailable(error) else { throw error }
            let lead = try await contactBackedLead(
                id: lead.id,
                notes: notes,
                email: email,
                markContacted: false
            )
            return (lead, "Demo email delivery backend is not configured yet. Contact saved locally.")
        }
    }

    func fetchInbox(source: String = "all", status: String = "open", limit: Int = 75) async throws -> SalespersonInboxResponse {
        let workspaceId = try await workspaceId()
        let request = try await request(
            path: "api/inbox",
            queryItems: [
                URLQueryItem(name: "workspaceId", value: workspaceId.uuidString),
                URLQueryItem(name: "source", value: source),
                URLQueryItem(name: "status", value: status),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        return try decoder.decode(SalespersonInboxResponse.self, from: try await data(for: request))
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

@MainActor
private final class SalespersonDiallerViewModel: ObservableObject {
    @Published var leads: [SalespersonDiallerLead] = []
    @Published var selectedListId: String?
    @Published var selectedLead: SalespersonDiallerLead?
    @Published var notes = ""
    @Published var email = ""
    @Published var textDropBody = ""
    @Published var activeCall: SalespersonDiallerCall?
    @Published var isCallSessionActive = false
    @Published var isLoading = false
    @Published var isPlacingCall = false
    @Published var isSaving = false
    @Published var isDroppingVoicemail = false
    @Published var isSendingTextDrop = false
    @Published var isSendingCallbackText = false
    @Published var isSendingDemoText = false
    @Published var isSendingDemoEmail = false
    @Published var isOpeningTestLead = false
    @Published var smartLists: [SalespersonDiallerSmartListOption] = []
    @Published var recordings: [SalespersonDiallerRecordingGroup] = []
    @Published var isLoadingSmartLists = false
    @Published var isImportingSmartList = false
    @Published var isLoadingRecordings = false
    @Published var isExportingRecording = false
    @Published var recordingExport: SalespersonRecordingExport?
    @Published var statusMessage: String?
    @Published var errorMessage: String?

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
    private var emailAutosaveTask: Task<Void, Never>?

    deinit {
        emailAutosaveTask?.cancel()
    }

    var leadLists: [SalespersonDiallerListGroup] {
        SalespersonDiallerListGroup.makeGroups(from: leads)
    }

    var selectedList: SalespersonDiallerListGroup? {
        guard let selectedListId else { return nil }
        return leadLists.first { $0.id == selectedListId }
    }

    var activeList: SalespersonDiallerListGroup? {
        selectedList ?? leadLists.first
    }

    var visibleLeads: [SalespersonDiallerLead] {
        activeList?.leads ?? []
    }

    func load() async {
        emailAutosaveTask?.cancel()
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await SalespersonMobileAPI.shared.fetchDiallerLeads()
            if let selectedListId, !leadLists.contains(where: { $0.id == selectedListId }) {
                self.selectedListId = leadLists.first?.id
            } else if selectedListId == nil {
                self.selectedListId = leadLists.first?.id
            }
            selectedLead = selectedLead.flatMap { selected in
                leads.first(where: { $0.id == selected.id })
            }
            if let selectedLead {
                selectedListId = selectedLead.listGroupId
                email = selectedLead.email ?? ""
                textDropBody = defaultTextDropBody(for: selectedLead)
            } else {
                notes = ""
                email = ""
                textDropBody = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openList(_ list: SalespersonDiallerListGroup) {
        emailAutosaveTask?.cancel()
        selectedListId = list.id
        selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        activeCall = nil
        isCallSessionActive = false
    }

    func closeList() {
        emailAutosaveTask?.cancel()
        selectedListId = nil
        selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        activeCall = nil
        isCallSessionActive = false
    }

    func closeLead() {
        emailAutosaveTask?.cancel()
        selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        activeCall = nil
        isCallSessionActive = false
    }

    func select(_ lead: SalespersonDiallerLead) {
        emailAutosaveTask?.cancel()
        selectedListId = lead.listGroupId
        selectedLead = lead
        notes = ""
        email = lead.email ?? ""
        textDropBody = defaultTextDropBody(for: lead)
        activeCall = nil
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
            leads.append(contentsOf: imported)
            selectedListId = list.id
            selectedLead = nil
            statusMessage = response.warning ?? "\(response.importedCount ?? imported.count) added from \(list.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecordings() async {
        guard !isLoadingRecordings else { return }
        isLoadingRecordings = true
        errorMessage = nil
        defer { isLoadingRecordings = false }
        do {
            recordings = try await SalespersonMobileAPI.shared.fetchDiallerRecordings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func callSelected() async {
        guard let selectedLead else { return }
        await placeCall(lead: selectedLead)
    }

    func openGabeTestLead() async {
        await openTestLead(name: "Gabe Phillippe", phone: gabeTestPhone, id: gabeTestLeadId)
    }

    func openSantanaTestLead() async {
        await openTestLead(name: "Santana Phillippe", phone: santanaTestPhone, id: santanaTestLeadId)
    }

    private func openTestLead(name: String, phone: String, id: UUID) async {
        guard !isOpeningTestLead else { return }
        if let existingLead = leads.first(where: { $0.phone.normalizedPhoneDigits == phone.normalizedPhoneDigits }) {
            select(existingLead)
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
                    company: nil,
                    email: nil
                )
            ])
            if let importedLead = response.leads?.first {
                replaceOrAppendLead(importedLead)
                select(importedLead)
                statusMessage = response.warning ?? "Opened \(name)."
                return
            }
            let fallbackLead = makeTestLead(name: name, phone: phone, id: id)
            replaceOrAppendLead(fallbackLead)
            select(fallbackLead)
            statusMessage = response.warning ?? "Opened \(name) for testing."
        } catch {
            let fallbackLead = makeTestLead(name: name, phone: phone, id: id)
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
        statusMessage = "No valid pending leads left."
    }

    func appendQuickNote(_ note: String) {
        let separator = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
        notes += "\(separator)\(note)"
    }

    func toggleStar(_ lead: SalespersonDiallerLead) async {
        let nextValue = !(lead.isStarred ?? false)
        do {
            let updatedLead = try await SalespersonMobileAPI.shared.toggleDiallerLeadStar(
                id: lead.id,
                isStarred: nextValue
            )
            replaceLead(updatedLead)
            statusMessage = nextValue ? "Lead starred for recordings." : "Lead removed from starred recordings."
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
        SalespersonVoiceCallService.shared.endActiveCall()
        isCallSessionActive = false
        statusMessage = "Call ended."
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
            _ = try await SalespersonMobileAPI.shared.sendDemoText(leadId: selectedLead.id, body: body)
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
            let warning = try await SalespersonMobileAPI.shared.sendDemoText(leadId: selectedLead.id, body: body)
            statusMessage = warning ?? "Text sent."
        } catch {
            errorMessage = error.localizedDescription
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

    func sendDemoText() async {
        guard let selectedLead else { return }
        isSendingDemoText = true
        errorMessage = nil
        statusMessage = nil
        defer { isSendingDemoText = false }

        do {
            let message = try await SalespersonMobileAPI.shared.prepareDemoMessage(for: selectedLead)
            guard let body = message.textBody?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
                throw SalespersonAPIError.status(400, "Demo text is not ready yet.")
            }
            let warning = try await SalespersonMobileAPI.shared.sendDemoText(leadId: selectedLead.id, body: body)
            statusMessage = warning ?? (message.tracked == true ? "Tracked demo text sent." : "Demo text sent.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendDemoEmail() async {
        guard let selectedLead else { return }
        emailAutosaveTask?.cancel()
        isSendingDemoEmail = true
        errorMessage = nil
        statusMessage = nil
        defer { isSendingDemoEmail = false }

        do {
            let message = try await SalespersonMobileAPI.shared.prepareDemoMessage(for: selectedLead, email: email)
            let (updatedLead, warning) = try await SalespersonMobileAPI.shared.sendDemoEmail(
                lead: selectedLead,
                email: email,
                message: message,
                notes: notes
            )
            if let index = leads.firstIndex(where: { $0.id == updatedLead.id }) {
                leads[index] = updatedLead
            }
            self.selectedLead = updatedLead
            self.email = updatedLead.email ?? email
            statusMessage = warning ?? (message.tracked == true ? "Tracked demo email sent." : "Demo email sent.")
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private func placeCall(lead: SalespersonDiallerLead) async {
        guard !isPlacingCall else { return }
        isPlacingCall = true
        errorMessage = nil
        statusMessage = nil
        defer { isPlacingCall = false }
        do {
            SalespersonVoiceCallService.shared.endActiveCall()
            let call = try await SalespersonMobileAPI.shared.startDiallerCall(lead: lead)
            activeCall = call
            let label = lead.displayBusinessName
            try await SalespersonVoiceCallService.shared.startOutboundCall(
                label: label,
                callRequestId: call.callRequestId,
                destinationNumber: call.toNumber,
                fromNumber: call.fromNumber
            )
            isCallSessionActive = true
            statusMessage = "Calling \(label)."
        } catch {
            activeCall = nil
            isCallSessionActive = false
            errorMessage = error.localizedDescription
        }
    }

    private func completeCurrentLead(message: String) {
        guard let selectedLead else { return }
        emailAutosaveTask?.cancel()
        leads.removeAll { $0.id == selectedLead.id }
        activeCall = nil
        isCallSessionActive = false
        self.selectedLead = nil
        notes = ""
        email = ""
        textDropBody = ""
        statusMessage = message
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
            listId: "test-dialler",
            listName: "Test dialler",
            latestCallRecording: nil,
            isStarred: false,
            disposition: nil,
            notes: nil,
            calledAt: nil,
            createdAt: Date()
        )
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        lead.disposition == nil &&
        !lead.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func defaultTextDropBody(for lead: SalespersonDiallerLead?) -> String {
        guard lead != nil else { return "" }
        return "Hey, Daniel with FLYR. Give me a call when you get a chance."
    }

    private func legacyLeadDisposition(for callDisposition: String) -> String {
        switch callDisposition {
        case "connected", "appointment_set": return "interested"
        case "callback_requested", "follow_up": return "callback"
        case "do_not_call": return "dnc"
        default: return "not_now"
        }
    }
}

@MainActor
private final class SalespersonInboxViewModel: ObservableObject {
    @Published var items: [SalespersonInboxItem] = []
    @Published var counts: [String: Int] = [:]
    @Published var selectedSource = "all"
    @Published var isLoading = false
    @Published var errorMessage: String?

    let sources = ["all", "sms", "email", "call"]

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await SalespersonMobileAPI.shared.fetchInbox(source: selectedSource)
            items = Self.sortedChronologically(response.items)
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
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markRead(_ item: SalespersonInboxItem) async {
        do {
            try await SalespersonMobileAPI.shared.updateInboxItem(id: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                await load()
                if index < items.count { items[index] = items[index] }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func sortedChronologically(_ items: [SalespersonInboxItem]) -> [SalespersonInboxItem] {
        items.sorted { lhs, rhs in
            if lhs.occurredAt == rhs.occurredAt {
                return lhs.id < rhs.id
            }
            return lhs.occurredAt > rhs.occurredAt
        }
    }
}

@MainActor
private final class SalespersonTasksViewModel: ObservableObject {
    @Published var items: [CalendarItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        let loaded = await FlyrCalendarService.shared.fetchCalendarItems(start: now.addingTimeInterval(-3600), end: end)
        items = loaded.filter { item in
            item.eventType == FlyrCalendarEventType.followUp.rawValue ||
            item.eventType == FlyrCalendarEventType.call.rawValue ||
            item.eventType == FlyrCalendarEventType.task.rawValue
        }
    }

    func complete(_ item: CalendarItem) async {
        do {
            try await FlyrCalendarService.shared.deleteEvent(id: item.sourceId)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private static let demoVideoLink = "https://www.flyrpro.app/demo-1?source=DANIELPHILLIPPE"

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

    var demoVideoLink: String {
        Self.demoVideoLink
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
        ("brokerages", "Brokerage"),
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

    func runSearch() async -> Bool {
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
                leadIntent: resolvedLeadIntent()
            )
            prospects = payload.prospects
            summary = payload
            let foundLabel = leadIntentLabel()
            if let saved = payload.savedList {
                statusMessage = "\(payload.prospects.count) \(foundLabel) found. Saved \"\(saved.listName)\" with \(saved.contactCount) list rows and \(saved.dialerLeadIds.count) dialer rows."
            } else {
                statusMessage = "\(payload.prospects.count) \(foundLabel) found."
            }
            await loadOptions()
            return true
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
        let brokerageTerms = realEstateMode && realEstateTarget == "brokerages"
            ? ["real estate brokerage", "real estate office", "realtor office", "realty brokerage"]
            : []
        return Array(Self.uniqueTerms(teamTerms + brokerageTerms + safeTerms).prefix(12))
    }

    private func resolvedLeadIntent() -> String {
        guard realEstateMode else { return "generic" }
        switch realEstateTarget {
        case "teams": return "real_estate_teams"
        case "individual_agents": return "real_estate_individual_agents"
        case "brokerages": return "real_estate_brokerages"
        default: return "real_estate_agents"
        }
    }

    private func leadIntentLabel() -> String {
        switch resolvedLeadIntent() {
        case "real_estate_teams": return "team leads"
        case "real_estate_brokerages": return "brokerage leads"
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

struct SalespersonLeadsView: View {
    @StateObject private var viewModel = SalespersonLeadsViewModel()
    @EnvironmentObject private var uiState: AppUIState
    @State private var showScraper = false
    @State private var scraperSavedList: SavedScraperList?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scraperDialerBanner
                salespersonListSearchBar
                salespersonLeadsList
            }
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle("Leads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScraper = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add leads")
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
            .navigationDestination(for: SalespersonLeadMasterRow.self) { lead in
                SalespersonLeadDetailView(lead: lead)
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
                        uiState.selectedTabIndex = 1
                    }
                )
            }
            .alert("Leads", isPresented: Binding(
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
        _ = viewModel.openListMatching(id: pending.listId, title: pending.listTitle)
        uiState.pendingSalespersonLeadListSelection = nil
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
                    uiState.selectedTabIndex = 1
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
            TextField(viewModel.selectedList == nil ? "Search lists..." : "Search leads in this list...", text: $viewModel.searchText)
                .font(.system(size: 15))
                .foregroundColor(.text)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(10)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                                    SalespersonLeadRow(lead: lead)
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
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
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

private struct SalespersonLeadRow: View {
    let lead: SalespersonLeadMasterRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: lead.phone?.nilIfEmpty == nil ? "building.2" : "phone.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.red)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(lead.detailLine)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(lead.leadState.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.flyrPrimary.opacity(0.12))
                        .clipShape(Capsule())
                    Text(lead.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lead.sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
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

private struct SalespersonLeadDetailView: View {
    let lead: SalespersonLeadMasterRow
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                Text(lead.displayName)
                    .font(.title2.bold())
                if let name = lead.name.nilIfEmpty, name != lead.displayName {
                    detailRow("Contact", name)
                }
                detailRow("State", lead.leadState.replacingOccurrences(of: "_", with: " ").capitalized)
                detailRow("Created", lead.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let disposition = lead.disposition?.nilIfEmpty {
                    detailRow("Disposition", disposition.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            }

            Section("Contact") {
                if let phone = lead.phone?.nilIfEmpty {
                    Button {
                        if let url = URL(string: "tel://\(phone.filter { $0.isNumber || $0 == "+" })") {
                            openURL(url)
                        }
                    } label: {
                        Label(phone, systemImage: "phone")
                    }
                }
                if let email = lead.email?.nilIfEmpty {
                    Button {
                        if let url = URL(string: "mailto:\(email)") {
                            openURL(url)
                        }
                    } label: {
                        Label(email, systemImage: "envelope")
                    }
                }
                if let website = lead.website?.nilIfEmpty {
                    Button {
                        openExternal(website)
                    } label: {
                        Label(website, systemImage: "globe")
                    }
                }
            }

            if let address = lead.address?.nilIfEmpty ?? lead.locationLine {
                Section("Location") {
                    Text(address)
                }
            }

            if let notes = lead.notes?.nilIfEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            Section("Source") {
                detailRow("Source", lead.sourceLabel)
                if let company = lead.company?.nilIfEmpty {
                    detailRow("Company", company)
                }
            }
        }
        .navigationTitle("Lead")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func openExternal(_ rawValue: String) {
        let value = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard let url = URL(string: value) else { return }
        openURL(url)
    }
}

private struct SalespersonLeadScraperView: View {
    @StateObject private var viewModel = SalespersonScraperViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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

                if viewModel.realEstateMode {
                    Picker("Real estate target", selection: $viewModel.realEstateTarget) {
                        ForEach(viewModel.realEstateTargetOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.red)
                }
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

            Button {
                Task {
                    let didCreateLeads = await viewModel.runSearch()
                    if didCreateLeads {
                        onOpenLeads(viewModel.summary?.savedList)
                    }
                }
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
    @State private var isVoicemailSettingsPresented = false
    @State private var isCallingVoicemail = false
    @State private var voicemailStatusMessage: String?
    @State private var voicemailErrorMessage: String?

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
                            metric(item.title, value: item.value, caption: item.caption)
                        }
                    }

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
            .sheet(isPresented: $isVoicemailSettingsPresented) {
                SalespersonVoicemailSettingsSheet(
                    isCallingVoicemail: isCallingVoicemail,
                    statusMessage: voicemailStatusMessage,
                    errorMessage: voicemailErrorMessage,
                    registrationError: voice.registrationError,
                    onCallVoicemail: {
                        Task { await callVoicemail() }
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

    private var performanceMetrics: [(title: String, value: String, caption: String)] {
        let periodCaption = home.selectedPeriod.caption
        guard let performance = home.performance else {
            return [
                ("Calls made", "0", periodCaption),
                ("Answers", "0", periodCaption),
                ("Texts sent", "0", periodCaption),
                ("Emails", "0", periodCaption),
                ("Demos sent", "0", periodCaption),
                ("Demos opened", "0", periodCaption),
                ("Watch time", "0s", "average \(periodCaption)"),
                ("Sign ups", "0", periodCaption),
            ]
        }

        return [
            ("Calls made", formatCount(performance.outreach.calls), periodCaption),
            ("Answers", formatCount(performance.outreach.answers), periodCaption),
            ("Texts sent", formatCount(performance.outreach.outboundMessages), periodCaption),
            ("Emails", formatCount(performance.outreach.emails), periodCaption),
            ("Demos sent", formatCount(performance.outreach.demosSent ?? 0), periodCaption),
            ("Demos opened", formatCount(performance.demoVideo.pageViews), periodCaption),
            ("Watch time", formatDuration(performance.demoVideo.averageWatchSeconds), "average \(periodCaption)"),
            ("Sign ups", formatCount(performance.links.signups), periodCaption),
        ]
    }

    @ViewBuilder
    private var demoVideoLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Demo video link", systemImage: "play.rectangle.fill")
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

    private func load() async {
        await home.load()
    }

    private func metric(_ title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
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
    let onCallVoicemail: () -> Void
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

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"],
    ]

    private var canSendDigits: Bool {
        voice.callPhase == .connected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Keypad", systemImage: "circle.grid.3x3.fill")
                    .font(.headline)
                Spacer()
                Text(canSendDigits ? "Connected" : "Connecting")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(canSendDigits ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((canSendDigits ? Color.green : Color.orange).opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(sentDigits.isEmpty ? "Digits sent will appear here" : sentDigits)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(sentDigits.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 10) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { digit in
                            Button {
                                send(digit)
                            } label: {
                                Text(digit)
                                    .font(.title2.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .foregroundStyle(.primary)
                                    .background(Color.primary.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSendDigits)
                            .opacity(canSendDigits ? 1 : 0.45)
                            .accessibilityLabel("Send \(digit)")
                        }
                    }
                }
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

struct SalespersonDiallerView: View {
    @StateObject private var viewModel = SalespersonDiallerViewModel()
    @ObservedObject private var voice = SalespersonVoiceCallService.shared
    @EnvironmentObject private var uiState: AppUIState
    @Environment(\.openURL) private var openURL
    @State private var isSmartListSheetPresented = false
    @State private var isRecordingsSheetPresented = false
    @State private var isFollowUpSheetPresented = false
    @State private var isListSheetPresented = false
    @State private var isAudioRouteDialogPresented = false
    @State private var isKeypadPresented = false

    private var isBusy: Bool {
        viewModel.isPlacingCall ||
        viewModel.isSaving ||
        viewModel.isDroppingVoicemail ||
        viewModel.isSendingTextDrop ||
        viewModel.isSendingCallbackText ||
        viewModel.isSendingDemoText ||
        viewModel.isSendingDemoEmail ||
        viewModel.isOpeningTestLead ||
        viewModel.isLoadingSmartLists ||
        viewModel.isImportingSmartList ||
        viewModel.isLoadingRecordings ||
        viewModel.isExportingRecording
    }

    private var editorHeight: CGFloat { 96 }

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
                if let lead = viewModel.selectedLead {
                    VStack(alignment: .leading, spacing: 18) {
                        selectedLeadHeader(lead)

                        actionBlock(lead: lead)
                        emailBlock
                        textBlock
                        notesBlock
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 28)
                } else if let list = viewModel.activeList {
                    VStack(alignment: .leading, spacing: 14) {
                        selectedDiallerListHeader(list)
                        diallerQueue
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .padding(.bottom, 28)
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if viewModel.leadLists.isEmpty {
                    ContentUnavailableView("No dialler lists", systemImage: "phone")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
	            .navigationTitle("Dialler")
	            .navigationBarTitleDisplayMode(.inline)
	            .safeAreaInset(edge: .bottom) {
                    if viewModel.statusMessage != nil || isBusy {
                        VStack(spacing: 10) {
                            if let message = viewModel.statusMessage {
                                Text(message)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }

                            if isBusy {
                                ProgressView()
                                    .padding(.vertical, 4)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                    }
	            }
                .safeAreaInset(edge: .top) {
                    if shouldShowCallStatus {
                        callStatusPanel()
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                            .background(Color.bg)
                    }
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
                        } label: {
                            Label("Test", systemImage: "phone.fill")
                        }
                        .disabled(viewModel.isOpeningTestLead)
                        .accessibilityLabel("Open test lead")
                    }

	                    ToolbarItemGroup(placement: .topBarTrailing) {
	                        Menu {
                            Button {
                                isSmartListSheetPresented = true
                                Task { await viewModel.loadSmartLists() }
                            } label: {
                                Label("Import Smart List", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                isRecordingsSheetPresented = true
                                Task { await viewModel.loadRecordings() }
                            } label: {
                                Label("Recordings", systemImage: "waveform")
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }

                        Button {
                            isListSheetPresented = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Dialler lists")
                    }
	            }
                .sheet(isPresented: $isSmartListSheetPresented) {
                    SalespersonDiallerSmartListSheet(viewModel: viewModel)
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
	            .refreshable { await viewModel.load() }
	            .task { await viewModel.load() }
	            .task { await voice.refreshRegistrationIfNeeded() }
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

    private func selectedDiallerListHeader(_ list: SalespersonDiallerListGroup) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.closeList()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color.bgSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(list.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(list.subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
    }

    private func actionBlock(lead: SalespersonDiallerLead) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                floatingActionButton(
                    viewModel.isCallSessionActive ? "Hang Up" : "Call",
                    systemImage: viewModel.isCallSessionActive ? "phone.down.fill" : "phone.fill",
                    fill: .red,
                    foreground: .white,
                    disabled: viewModel.isPlacingCall && !viewModel.isCallSessionActive
                ) {
                    if viewModel.isCallSessionActive {
                        viewModel.hangUp()
                    } else {
                        Task { await viewModel.callSelected() }
                    }
                }

                floatingActionButton(
                    "Next",
                    systemImage: "forward.fill",
                    disabled: viewModel.isPlacingCall || viewModel.leads.count < 2
                ) {
                    viewModel.advanceToNextLead()
                }
            }

            HStack(spacing: 12) {
                floatingActionButton(
                    "Demo Text",
                    systemImage: "message.fill",
                    disabled: viewModel.isSendingCallbackText
                ) {
                    Task { await viewModel.sendCallbackText() }
                }

                floatingActionButton(
                    "Demo Email",
                    systemImage: "envelope.fill",
                    disabled: viewModel.isSendingDemoEmail || viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    Task { await viewModel.sendDemoEmail() }
                }
            }

            HStack(spacing: 12) {
                floatingActionButton(
                    "Follow up",
                    systemImage: "arrow.uturn.right",
                    disabled: viewModel.isSaving
                ) {
                    isFollowUpSheetPresented = true
                }

                floatingActionButton(
                    "DNC",
                    systemImage: "hand.raised.fill",
                    foreground: .red,
                    disabled: viewModel.isSaving
                ) {
                    Task { await viewModel.log(disposition: "do_not_call") }
                }
            }
        }
    }

    private var emailBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Email")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Task { await viewModel.sendDemoEmail() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(Color.bgSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSendingDemoEmail || viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.isSendingDemoEmail || viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }

            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.secondary)
                TextField("Add email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 12)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border))
            .onChange(of: viewModel.email) { _, _ in
                viewModel.scheduleEmailAutosave()
            }
        }
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Text")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Task { await viewModel.sendCallbackText() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(Color.bgSecondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSendingCallbackText || viewModel.textDropBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.isSendingCallbackText || viewModel.textDropBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }

            TextEditor(text: $viewModel.textDropBody)
                .frame(height: editorHeight)
                .scrollContentBackground(.hidden)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border))
        }
    }

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $viewModel.notes)
                .frame(height: editorHeight)
                .scrollContentBackground(.hidden)
                .background(Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border))
        }
    }

    private func floatingActionButton(
        _ title: String,
        systemImage: String,
        fill: Color = Color.bgSecondary,
        foreground: Color = Color.flyrPrimary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 58)
                .foregroundStyle(foreground)
                .background(fill)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.border.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

	    private var diallerQueue: some View {
	        VStack(alignment: .leading, spacing: 10) {
	            Text("Leads")
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
                HStack(spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)

                    Text(label(for: phase))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.12))
                .clipShape(Capsule())

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

private struct SalespersonDiallerSmartListSheet: View {
    @ObservedObject var viewModel: SalespersonDiallerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoadingSmartLists {
                    ProgressView()
                }

                ForEach(viewModel.smartLists) { list in
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
                    .disabled(viewModel.isImportingSmartList || list.dialableCount == 0)
                }
            }
            .navigationTitle("Import Smart List")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if !viewModel.isLoadingSmartLists && viewModel.smartLists.isEmpty {
                    ContentUnavailableView("No smart lists", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadSmartLists() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingSmartLists)
                }
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
            .navigationTitle("Recordings")
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
                        Task { await viewModel.loadRecordings() }
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
    @StateObject private var viewModel = SalespersonInboxViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.items) { item in
                    SalespersonInboxRow(item: item)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowBackground(item.needsResponse ? Color.flyrPrimary.opacity(0.08) : Color(.systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Done") {
                                Task { await viewModel.markDone(item) }
                            }
                            .tint(Color.flyrPrimary)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Read") {
                                Task { await viewModel.markRead(item) }
                            }
                            .tint(.gray)
                        }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Text("Inbox")
                            .font(.headline)
                        Menu {
                            ForEach(viewModel.sources, id: \.self) { source in
                                Button {
                                    viewModel.selectSource(source)
                                } label: {
                                    Label(label(for: source), systemImage: viewModel.selectedSource == source ? "checkmark" : icon(for: source))
                                }
                            }
                        } label: {
                            Label(label(for: viewModel.selectedSource), systemImage: "line.3.horizontal.decrease.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.flyrPrimary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inbox source filter")
                    }
                }
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView(emptyMessage, systemImage: icon(for: viewModel.selectedSource))
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .onChange(of: viewModel.selectedSource) { _, _ in
                Task { await viewModel.load() }
            }
            .alert("Inbox", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func icon(for source: String) -> String {
        switch source {
        case "all": return "tray"
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
        viewModel.selectedSource == "all" ? "No inbox items" : "No \(label(for: viewModel.selectedSource).lowercased())"
    }
}

private struct SalespersonInboxRow: View {
    let item: SalespersonInboxItem

    private func contactLine(for item: SalespersonInboxItem) -> String? {
        [
            item.fromLabel,
            item.fromPhone,
            item.fromEmail
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        .first
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon(for: item.source))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.isUnread ? Color.flyrPrimary : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if item.isUnread {
                    Circle()
                        .fill(Color.flyrPrimary)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: -1)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(item.isUnread ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.occurredAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text((item.preview ?? item.body) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(contactLine(for: item) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(height: 72, alignment: .center)
        .contentShape(Rectangle())
    }

    private func icon(for source: String) -> String {
        switch source {
        case "all": return "tray"
        case "sms": return "message"
        case "email": return "envelope"
        case "call": return "phone"
        default: return "bell"
        }
    }
}

struct SalespersonTasksView: View {
    @StateObject private var viewModel = SalespersonTasksViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: item.eventType))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.flyrPrimary)
                            .frame(width: 28, height: 28)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if let contactName = item.contactName {
                                Text(contactName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(item.startAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Complete") {
                            Task { await viewModel.complete(item) }
                        }
                        .tint(Color.flyrPrimary)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    ContentUnavailableView("No tasks", systemImage: "checklist")
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .alert("Task", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private func icon(for eventType: String) -> String {
        switch eventType {
        case FlyrCalendarEventType.call.rawValue: return "phone"
        case FlyrCalendarEventType.followUp.rawValue: return "arrow.uturn.forward"
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

    var normalizedPhoneDigits: String {
        filter(\.isNumber)
    }
}
