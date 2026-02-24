import Foundation
import Supabase
import Combine

enum IndividualMetricTrend: String, Hashable {
    case up
    case down
    case flat
}

struct IndividualMetricDelta: Hashable {
    let abs: Double?
    let pct: Double?
    let trend: IndividualMetricTrend?
}

struct IndividualPerformanceMetric: Identifiable, Hashable {
    let key: String
    let value: Double
    let delta: IndividualMetricDelta?

    var id: String { key }

    var title: String {
        switch key {
        case "doors_knocked": return "Doors Knocked"
        case "flyers_delivered": return "Flyers Delivered"
        case "conversations": return "Conversations"
        case "leads_created": return "Leads Created"
        case "appointments_set": return "Appointments Set"
        case "time_spent_seconds": return "Time Spent"
        case "sessions_count": return "Sessions"
        case "conversation_to_lead_rate": return "Conversation -> Lead"
        case "conversation_to_appointment_rate": return "Conversation -> Appointment"
        case "leads": return "Leads"
        case "conversion_rate": return "Conversion Rate"
        case "flyers": return "Flyers"
        case "qr_codes_scanned": return "QR Scans"
        case "distance_walked": return "Distance Walked"
        case "xp": return "XP"
        default:
            return key
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    var formattedValue: String {
        if key == "time_spent_seconds" {
            let totalSeconds = max(0, Int(value.rounded()))
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(minutes)m"
        }

        if key.contains("rate") {
            let percent = value <= 1.0 ? value * 100.0 : value
            return String(format: "%.1f%%", percent)
        }

        if key == "distance_walked" {
            return String(format: "%.1f", value)
        }

        if abs(value.rounded() - value) < 0.0001 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    var formattedDeltaAbs: String? {
        guard let deltaAbs = delta?.abs else { return nil }
        let sign = deltaAbs >= 0 ? "+" : ""

        if key == "time_spent_seconds" {
            let deltaSeconds = Int(abs(deltaAbs).rounded())
            let hours = deltaSeconds / 3600
            let minutes = (deltaSeconds % 3600) / 60
            let valueText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            return "\(sign)\(valueText)"
        }

        if key.contains("rate") {
            let percent = deltaAbs <= 1.0 && deltaAbs >= -1.0 ? deltaAbs * 100.0 : deltaAbs
            return String(format: "%@%.1f%%", sign, percent)
        }

        if abs(deltaAbs.rounded() - deltaAbs) < 0.0001 {
            return "\(sign)\(Int(deltaAbs.rounded()))"
        }
        return String(format: "%@%.1f", sign, deltaAbs)
    }

    var formattedDeltaPct: String? {
        guard let pct = delta?.pct else { return nil }
        return String(format: "(%.1f%%)", pct)
    }

    var resolvedTrend: IndividualMetricTrend {
        if let trend = delta?.trend { return trend }
        guard let value = delta?.abs else { return .flat }
        if value > 0 { return .up }
        if value < 0 { return .down }
        return .flat
    }
}

enum IndividualReportPeriod: String, Codable, CaseIterable {
    case weekly
    case monthly
    case yearly

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    static let displayOrder: [IndividualReportPeriod] = [.weekly, .monthly, .yearly]
}

struct IndividualPerformanceReport: Identifiable, Hashable {
    let id: UUID
    let period: IndividualReportPeriod
    let periodStart: Date
    let periodEnd: Date
    let generatedAt: Date
    let summary: String?
    let recommendations: [String]
    let metrics: [IndividualPerformanceMetric]

    var rangeLabel: String {
        "\(periodStart.toMediumString()) – \(periodEnd.toMediumString())"
    }
}

actor PerformanceReportsService {
    static let shared = PerformanceReportsService()

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private init() {}

    func fetchLatestIndividualReports(userID: UUID, workspaceID: UUID?) async throws -> [IndividualPerformanceReport] {
        await triggerReportGeneration(workspaceID: workspaceID)

        // Try stable FLYR-PRO schema first, then richer schema if available.
        let selectCandidates = [
            "id, scope, period, period_start, period_end, metrics, deltas, created_at, subject_user_id, workspace_id",
            "id, scope, period_type, period_start, period_end, metrics, deltas, created_at, subject_user_id, workspace_id",
            "id, scope, period_type, period_start, period_end, metrics, deltas, llm_summary, recommendations, generated_at, created_at, subject_user_id, workspace_id",
            "id, scope, period, period_start, period_end, metrics, deltas, llm_summary, recommendations, generated_at, created_at, subject_user_id, workspace_id"
        ]

        let rows = try await fetchRows(
            selectCandidates: selectCandidates,
            userID: userID,
            workspaceID: workspaceID
        )

        var latestByPeriod: [IndividualReportPeriod: IndividualPerformanceReport] = [:]

        for row in rows {
            guard let period = IndividualReportPeriod(rawValue: row.periodType.lowercased()) else { continue }
            guard latestByPeriod[period] == nil else { continue }
            latestByPeriod[period] = row.toDomain()
        }

        return IndividualReportPeriod.displayOrder.compactMap { latestByPeriod[$0] }
    }

    private func triggerReportGeneration(workspaceID: UUID?) async {
        var params: [String: AnyCodable] = [
            "p_force": AnyCodable(false)
        ]

        if let workspaceID {
            params["p_workspace_id"] = AnyCodable(workspaceID.uuidString)
        }

        do {
            _ = try await client
                .rpc("generate_my_performance_reports", params: params)
                .execute()
        } catch {
            // Best effort: report rows may already exist or RPC may not be deployed yet.
        }
    }

    private func fetchRows(
        selectCandidates: [String],
        userID: UUID,
        workspaceID: UUID?
    ) async throws -> [ReportRow] {
        var lastError: Error?

        for columns in selectCandidates {
            do {
                let base = client
                    .from("reports")
                    .select(columns)
                    .eq("scope", value: "member")
                    .eq("subject_user_id", value: userID)

                let scoped = workspaceID.map { base.eq("workspace_id", value: $0) } ?? base

                let rows: [ReportRow] = try await scoped
                    .order("period_end", ascending: false)
                    .limit(24)
                    .execute()
                    .value

                return rows
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "PerformanceReportsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown reports query error"])
    }

    func hasUnreadIndividualReportNotification(userID: UUID) async -> Bool {
        do {
            let rows: [UnreadNotificationRow] = try await client
                .from("notifications")
                .select("id")
                .eq("user_id", value: userID)
                .eq("type", value: "report_ready")
                .eq("is_read", value: false)
                .limit(1)
                .execute()
                .value

            return !rows.isEmpty
        } catch {
            do {
                let rows: [UnreadNotificationRow] = try await client
                    .from("notifications")
                    .select("id")
                    .eq("user_id", value: userID)
                    .eq("type", value: "report_ready")
                    .is("read_at", value: nil)
                    .limit(1)
                    .execute()
                    .value

                return !rows.isEmpty
            } catch {
                // Notifications table may not exist in some environments.
                return false
            }
        }
    }

    func markIndividualReportNotificationsRead(userID: UUID) async {
        do {
            try await client
                .from("notifications")
                .update(["is_read": AnyCodable(true)])
                .eq("user_id", value: userID)
                .eq("type", value: "report_ready")
                .eq("is_read", value: false)
                .execute()
        } catch {
            do {
                try await client
                    .from("notifications")
                    .update(["read_at": AnyCodable(Date())])
                    .eq("user_id", value: userID)
                    .eq("type", value: "report_ready")
                    .is("read_at", value: nil)
                    .execute()
            } catch {
                // Best effort only.
            }
        }
    }
}

@MainActor
final class IndividualPerformanceReportViewModel: ObservableObject {
    @Published var reports: [IndividualPerformanceReport] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasUnread = false

    private let service = PerformanceReportsService.shared

    func refreshUnreadIndicator(for userID: UUID) async {
        hasUnread = await service.hasUnreadIndividualReportNotification(userID: userID)
    }

    func loadReports(userID: UUID, workspaceID: UUID?) async {
        isLoading = true
        errorMessage = nil

        do {
            reports = try await service.fetchLatestIndividualReports(userID: userID, workspaceID: workspaceID)
        } catch {
            print("❌ [REPORTS] load failed: \(error.localizedDescription)")
            reports = []
            if Self.isMissingSchemaOrTable(error) {
                // Show empty state instead of blocking error when reports infra isn't deployed yet.
                errorMessage = nil
            } else {
                errorMessage = "Unable to load your report right now. Please try again."
            }
        }

        isLoading = false
    }

    func openAndMarkRead(userID: UUID, workspaceID: UUID?) async {
        await loadReports(userID: userID, workspaceID: workspaceID)
        await service.markIndividualReportNotificationsRead(userID: userID)
        hasUnread = false
    }

    private static func isMissingSchemaOrTable(_ error: Error) -> Bool {
        let msg = error.localizedDescription.lowercased()
        return msg.contains("does not exist")
            || msg.contains("column")
            || msg.contains("relation")
            || msg.contains("schema cache")
            || msg.contains("could not find")
    }
}

private struct ReportRow: Decodable {
    let id: UUID
    let periodType: String
    let periodStart: Date
    let periodEnd: Date
    let metrics: AnyCodable
    let deltas: AnyCodable?
    let llmSummary: String?
    let recommendations: AnyCodable?
    let generatedAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case period
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case metrics
        case deltas
        case llmSummary = "llm_summary"
        case recommendations
        case generatedAt = "generated_at"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        periodType = try container.decodeIfPresent(String.self, forKey: .periodType)
            ?? container.decode(String.self, forKey: .period)
        periodStart = try container.decode(Date.self, forKey: .periodStart)
        periodEnd = try container.decode(Date.self, forKey: .periodEnd)
        metrics = try container.decode(AnyCodable.self, forKey: .metrics)
        deltas = try container.decodeIfPresent(AnyCodable.self, forKey: .deltas)
        llmSummary = try container.decodeIfPresent(String.self, forKey: .llmSummary)
        recommendations = try container.decodeIfPresent(AnyCodable.self, forKey: .recommendations)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    func toDomain() -> IndividualPerformanceReport {
        let metricValues = Self.doubleDictionary(from: metrics)
        let deltaValues = Self.deltaDictionary(from: deltas)

        let preferredOrder = [
            "doors_knocked", "flyers_delivered", "conversations", "leads_created",
            "appointments_set", "time_spent_seconds", "sessions_count",
            "leads", "conversion_rate", "flyers", "qr_codes_scanned", "distance_walked", "xp"
        ]

        let keys = preferredOrder.filter { metricValues[$0] != nil }
            + metricValues.keys.filter { !preferredOrder.contains($0) }.sorted()

        let mapped = keys.compactMap { key -> IndividualPerformanceMetric? in
            guard let value = metricValues[key] else { return nil }
            return IndividualPerformanceMetric(
                key: key,
                value: value,
                delta: deltaValues[key]
            )
        }

        return IndividualPerformanceReport(
            id: id,
            period: IndividualReportPeriod(rawValue: periodType.lowercased()) ?? .weekly,
            periodStart: periodStart,
            periodEnd: periodEnd,
            generatedAt: generatedAt ?? createdAt ?? Date(),
            summary: llmSummary,
            recommendations: Self.stringArray(from: recommendations),
            metrics: mapped
        )
    }

    private static func doubleDictionary(from value: AnyCodable?) -> [String: Double] {
        guard let raw = value?.value else { return [:] }

        var output: [String: Double] = [:]

        if let dict = raw as? [String: Any] {
            for (key, val) in dict {
                if let nested = val as? [String: Any], let abs = asDouble(nested["abs"]) {
                    output[key] = abs
                    continue
                }
                if let parsed = asDouble(val) {
                    output[key] = parsed
                }
            }
            return output
        }

        if let dict = raw as? [String: AnyCodable] {
            for (key, val) in dict {
                if let nested = val.value as? [String: Any], let abs = asDouble(nested["abs"]) {
                    output[key] = abs
                    continue
                }
                if let nested = val.value as? [String: AnyCodable], let abs = asDouble(nested["abs"]?.value) {
                    output[key] = abs
                    continue
                }
                if let parsed = asDouble(val.value) {
                    output[key] = parsed
                }
            }
            return output
        }

        return output
    }

    private static func asDouble(_ value: Any?) -> Double? {
        switch value {
        case let num as Double:
            return num
        case let num as Float:
            return Double(num)
        case let num as Int:
            return Double(num)
        case let num as Int64:
            return Double(num)
        case let num as NSNumber:
            return num.doubleValue
        case let str as String:
            return Double(str)
        case let any as AnyCodable:
            return asDouble(any.value)
        default:
            return nil
        }
    }

    private static func deltaDictionary(from value: AnyCodable?) -> [String: IndividualMetricDelta] {
        guard let raw = value?.value else { return [:] }
        var output: [String: IndividualMetricDelta] = [:]

        if let dict = raw as? [String: Any] {
            for (key, val) in dict {
                if let parsed = parseDelta(val) {
                    output[key] = parsed
                }
            }
            return output
        }

        if let dict = raw as? [String: AnyCodable] {
            for (key, val) in dict {
                if let parsed = parseDelta(val.value) {
                    output[key] = parsed
                }
            }
            return output
        }

        return output
    }

    private static func parseDelta(_ value: Any?) -> IndividualMetricDelta? {
        if let scalar = asDouble(value) {
            return IndividualMetricDelta(abs: scalar, pct: nil, trend: nil)
        }

        if let dict = value as? [String: Any] {
            let absValue = asDouble(dict["abs"] ?? dict["absolute"])
            let pctValue = asDouble(dict["pct"] ?? dict["percent"])
            let trendValue = asTrend(dict["trend"])
            if absValue == nil && pctValue == nil && trendValue == nil {
                return nil
            }
            return IndividualMetricDelta(abs: absValue, pct: pctValue, trend: trendValue)
        }

        if let dict = value as? [String: AnyCodable] {
            let absValue = asDouble(dict["abs"]?.value ?? dict["absolute"]?.value)
            let pctValue = asDouble(dict["pct"]?.value ?? dict["percent"]?.value)
            let trendValue = asTrend(dict["trend"]?.value)
            if absValue == nil && pctValue == nil && trendValue == nil {
                return nil
            }
            return IndividualMetricDelta(abs: absValue, pct: pctValue, trend: trendValue)
        }

        return nil
    }

    private static func asTrend(_ value: Any?) -> IndividualMetricTrend? {
        guard let raw = (value as? String)?.lowercased() else { return nil }
        return IndividualMetricTrend(rawValue: raw)
    }

    private static func stringArray(from value: AnyCodable?) -> [String] {
        guard let raw = value?.value else { return [] }
        if let array = raw as? [String] {
            return array
        }
        if let array = raw as? [Any] {
            return array.compactMap { $0 as? String }
        }
        if let array = raw as? [AnyCodable] {
            return array.compactMap { $0.value as? String }
        }
        return []
    }
}

private struct UnreadNotificationRow: Decodable {
    let id: UUID
}
