import Foundation
import Combine
import Supabase

struct FieldSalesSnapshot: Decodable {
    let enabled: Bool
    var needs_setup: Bool?
    var role: String?
    var user_id: UUID?
    var currency: String?
    var timezone: String?
    var team_revenue_visible: Bool?
    var pro_sales_version: Int?
    var capabilities: [String: Bool]?
    var verification_required: Bool?
    var today: String?
    var month: String?
    var as_of: String?
    var period_start: String?
    var period_end: String?
    var coaching: String?
    var totals: Totals?
    var goal: Goal?
    var metrics: Metrics?
    var sales: [Sale]?
    var ranking: [Rank]?
    var feed: [Win]?
    var options: Options?
    struct Totals: Decodable {
        let sales: Int
        let revenue_minor: String?
        let weekly_sales: Int
        let weekly_revenue_minor: String?
        let monthly_sales: Int
        let monthly_revenue_minor: String?
    }
    struct Goal: Decodable { let target: Int?; let completed: Int; let remaining: Int? }
    struct Metrics: Decodable {
        let doors: Int; let conversations: Int; let leads: Int; let appointments: Int
        let lead_converted: Int; let appointment_converted: Int?; let unlinked_sales: Int
        let sales_per_100_doors: Double?
    }
    struct Sale: Decodable, Identifiable {
        let id: UUID; let rep_id: UUID; let rep_name: String; let status: String; let sold_on: String; let version: Int
        let value_minor: String?; let currency: String; let contact_id: UUID?; let appointment_id: UUID?; let campaign_id: UUID?; let territory_id: UUID?
        let notes: String?; let cancellation_reason: String?
        let can_edit: Bool; let can_verify: Bool; let can_cancel: Bool
    }
    struct Rank: Decodable, Identifiable {
        let rep_id: UUID; let rep_name: String; let sales: Int; let revenue_minor: String?
        var id: UUID { rep_id }
    }
    struct Win: Decodable, Identifiable { let id: UUID; let rep_name: String; let sold_on: String; let value_minor: String? }
    struct Options: Decodable {
        let leads: [Lead]; let appointments: [Appointment]; let campaigns: [CampaignOption]
    }
    struct Lead: Decodable, Identifiable { let id: UUID; let name: String; let campaign_id: UUID? }
    struct Appointment: Decodable, Identifiable { let id: UUID; let contact_id: UUID; let scheduled_at: String }
    struct CampaignOption: Decodable, Identifiable { let id: UUID; let name: String }
    var manager: Bool { role == "owner" || role == "admin" || role == "manager" }
}

extension Notification.Name { static let fieldSalesChanged = Notification.Name("fieldSalesChanged") }

enum FieldSalesService {
    struct Filter: Encodable, Equatable {
        let p_workspace: UUID
        var p_period = "month"
        var p_team = false
        var p_rep: UUID?
        var p_campaign: UUID?
        var p_status: String?
    }
    struct HistoryEvent: Decodable, Identifiable {
        let id: UUID; let action: String; let actor: String; let created_at: String; let status: String?
        let value_minor: String?; let currency: String?; let sold_on: String?; let version: Int?; let reason: String?
    }
    static func history(_ workspace: UUID, sale: UUID) async throws -> [HistoryEvent] {
        struct Params: Encodable { let p_workspace: UUID; let p_sale: UUID }
        return try await SupabaseManager.shared.client.rpc("field_sales_history", params: Params(p_workspace: workspace, p_sale: sale)).execute().value
    }
    static func bootstrap(_ workspace: UUID) async throws -> FieldSalesSnapshot {
        struct Params: Encodable { let p_workspace: UUID }
        return try await SupabaseManager.shared.client.rpc("field_sales_bootstrap", params: Params(p_workspace: workspace)).execute().value
    }
    static func snapshot(_ filter: Filter) async throws -> FieldSalesSnapshot {
        try await SupabaseManager.shared.client.rpc("field_sales_dashboard", params: filter).execute().value
    }
    static func command(_ workspace: UUID, _ action: String, _ data: [String: String]) async throws {
        struct Params: Encodable { let p_workspace: UUID; let p_action: String; let p_data: [String: String] }
        _ = try await SupabaseManager.shared.client.rpc("field_sales_command", params: Params(p_workspace: workspace, p_action: action, p_data: data)).execute()
        await MainActor.run { NotificationCenter.default.post(name: .fieldSalesChanged, object: nil) }
    }
    static func money(_ value: String?, currency: String?) -> String {
        guard let value, value.range(of: #"^-?[0-9]+$"#, options: .regularExpression) != nil else { return "Private" }
        let negative = value.hasPrefix("-")
        let magnitude = negative ? String(value.dropFirst()) : value
        let code = currency ?? "CAD"
        let amount = editableMoney(magnitude, currency: code).split(separator: ".")
        let digits = Array(String(amount[0]).reversed())
        let grouped = stride(from: 0, to: digits.count, by: 3).map { String(digits[$0..<min($0 + 3, digits.count)].reversed()) }.reversed().joined(separator: ",")
        return "\(code) \(negative ? "−" : "")\(grouped)" + (amount.count > 1 ? ".\(amount[1])" : "")
    }
    static func editableMoney(_ value: String?, currency: String?) -> String {
        guard let value else { return "" }
        if currency == "JPY" { return value }
        let padded = String(repeating: "0", count: max(0, 3 - value.count)) + value
        return "\(padded.dropLast(2)).\(padded.suffix(2))"
    }
    static func minorUnits(_ value: String, currency: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = currency == "JPY" ? #"^[0-9]+$"# : #"^[0-9]+(?:\.[0-9]{1,2})?$"#
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { throw validation("Enter a valid contract value.") }
        let minor = amount * (currency == "JPY" ? 1 : 100)
        guard minor > 0, minor <= Decimal(9_000_000_000_000_000 as Int64) else { throw validation("Contract value is outside the supported range.") }
        return NSDecimalNumber(decimal: minor).stringValue
    }
    static func validation(_ message: String) -> NSError { NSError(domain: "FieldSales", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func timestamp(_ value: String, timezone: String) -> String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: value) }
        guard let date else { return value }
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short; formatter.timeZone = TimeZone(identifier: timezone)
        return formatter.string(from: date)
    }
}

@MainActor final class FieldSalesModel: ObservableObject {
    @Published var data: FieldSalesSnapshot?
    @Published var error: String?
    @Published var loading = false
    private var generation = UUID()
    func cancelPending() { generation = UUID(); loading = false }
    func clear() { generation = UUID(); data = nil; error = nil; loading = false }
    func load(_ filter: FieldSalesService.Filter) async {
        let ticket = UUID(); generation = ticket; loading = true
        do {
            let next = try await FieldSalesService.snapshot(filter)
            guard ticket == generation, !Task.isCancelled else { return }
            data = next; error = nil
        } catch {
            guard ticket == generation, !Task.isCancelled else { return }
            data = nil; self.error = error.localizedDescription
        }
        if ticket == generation { loading = false }
    }
}
