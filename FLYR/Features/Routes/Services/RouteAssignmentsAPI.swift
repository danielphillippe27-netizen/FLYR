import Foundation
import Supabase

/// HTTP client for `GET/POST /api/routes/assignments*`. Uses the same base URL and Bearer auth as `AccessAPI`.
@MainActor
final class RouteAssignmentsAPI {
    static let shared = RouteAssignmentsAPI()

    private init() {}

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    // MARK: - Public

    func fetchAssignments(workspaceId: UUID, campaignId: UUID? = nil) async throws -> (assignments: [RouteAssignmentSummary], role: String) {
        var components = URLComponents(string: "\(requestBaseURL)/api/routes/assignments")!
        var items = [URLQueryItem(name: "workspaceId", value: workspaceId.uuidString)]
        if let campaignId {
            items.append(URLQueryItem(name: "campaignId", value: campaignId.uuidString))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw RouteAssignmentsAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await dataForAuthorizedRequest(request)
        try throwIfUnauthorized(http, data: data)

        guard http.statusCode == 200 else {
            throw RouteAssignmentsAPIError.http(http.statusCode, Self.message(from: data))
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RouteAssignmentsAPIError.decoding("Invalid JSON")
        }

        let role = RouteJSON.string(from: obj["role"]) ?? "member"
        let rows = RouteJSON.dictionaryArray(from: obj["assignments"])
        let assignments = rows.compactMap { RouteAssignmentSummary(apiAssignment: $0) }
        return (assignments, role)
    }

    func fetchAssignmentDetail(assignmentId: UUID) async throws -> RouteAssignmentDetailPayload {
        guard let url = URL(string: "\(requestBaseURL)/api/routes/assignments/\(assignmentId.uuidString)") else {
            throw RouteAssignmentsAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await dataForAuthorizedRequest(request)
        try throwIfUnauthorized(http, data: data)

        switch http.statusCode {
        case 200:
            break
        case 404:
            throw RouteAssignmentsAPIError.notFound
        default:
            throw RouteAssignmentsAPIError.http(http.statusCode, Self.message(from: data))
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RouteAssignmentsAPIError.decoding("Invalid JSON")
        }

        return try RouteAssignmentDetailPayload.parse(obj)
    }

    func fetchAssignmentMap(assignmentId: UUID) async throws -> RouteAssignmentMapPayload {
        guard let url = URL(string: "\(requestBaseURL)/api/routes/assignments/\(assignmentId.uuidString)/map") else {
            throw RouteAssignmentsAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await dataForAuthorizedRequest(request)
        try throwIfUnauthorized(http, data: data)

        switch http.statusCode {
        case 200:
            break
        case 404:
            throw RouteAssignmentsAPIError.notFound
        default:
            throw RouteAssignmentsAPIError.http(http.statusCode, Self.message(from: data))
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RouteAssignmentsAPIError.decoding("Invalid JSON")
        }

        return try RouteAssignmentMapPayload.parse(obj)
    }

    func postAssignmentStatus(
        assignmentId: UUID,
        action: RouteAssignmentWorkflowAction,
        declineReason: String?,
        progress: [String: Any]? = nil
    ) async throws {
        guard let url = URL(string: "\(requestBaseURL)/api/routes/assignments/status") else {
            throw RouteAssignmentsAPIError.invalidURL
        }

        var body: [String: Any] = [
            "assignmentId": assignmentId.uuidString,
            "action": action.rawValue
        ]
        if let declineReason, !declineReason.isEmpty {
            body["declineReason"] = declineReason
        }
        if let progress {
            body["progress"] = progress
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await dataForAuthorizedRequest(request)
        try throwIfUnauthorized(http, data: data)

        switch http.statusCode {
        case 200:
            return
        case 403:
            throw RouteAssignmentsAPIError.forbidden(Self.message(from: data))
        case 409:
            throw RouteAssignmentsAPIError.conflict(Self.message(from: data) ?? "Invalid transition.")
        default:
            throw RouteAssignmentsAPIError.http(http.statusCode, Self.message(from: data))
        }
    }

    // MARK: - Auth (mirrors AccessAPI)

    private func dataForAuthorizedRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authedRequest = request
        let session = try await SupabaseManager.shared.client.auth.session
        authedRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authedRequest)
        guard let http = response as? HTTPURLResponse else {
            throw RouteAssignmentsAPIError.network
        }
        guard http.statusCode == 401 else {
            return (data, http)
        }

        do {
            let refreshed = try await SupabaseManager.shared.client.auth.refreshSession()
            KeychainAuthStorage.saveSession(
                accessToken: refreshed.accessToken,
                refreshToken: refreshed.refreshToken
            )
            authedRequest.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: authedRequest)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw RouteAssignmentsAPIError.network
            }
            return (retryData, retryHTTP)
        } catch {
            return (data, http)
        }
    }

    private func throwIfUnauthorized(_ http: HTTPURLResponse, data: Data) throws {
        guard http.statusCode == 401 else { return }
        throw RouteAssignmentsAPIError.unauthorized
    }

    private static func message(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let msg = RouteJSON.string(from: obj["error"]) { return msg }
        if let msg = RouteJSON.string(from: obj["message"]) { return msg }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Detail payload

struct RouteAssignmentDetailPayload: Equatable, Sendable {
    let assignmentId: UUID
    let status: String
    let assignedToUserId: UUID?
    let assignedByUserId: UUID?
    let routePlanId: UUID
    let campaignId: UUID?
    let planNameRaw: String
    let totalStops: Int
    let estMinutes: Int?
    let distanceMeters: Int?
    let dueAt: Date?
    let priority: String?
    let declineReason: String?
    let assigneeDisplayName: String?
    let assignedByDisplayName: String?
    let stops: [RoutePlanStop]
    let workspaceRole: String

    var displayPlanName: String {
        RouteAssignmentSummary.displayName(fromRoutePlanName: planNameRaw)
    }

    var canManageRoutes: Bool {
        let r = workspaceRole.lowercased()
        return r == "owner" || r == "admin"
    }

    static func parse(_ obj: [String: Any]) throws -> RouteAssignmentDetailPayload {
        let assign = RouteJSON.dictionary(from: RouteJSON.value(in: obj, keys: ["assignment"])) ?? obj
        let plan = RouteJSON.dictionary(from: RouteJSON.value(in: obj, keys: ["route_plan", "routePlan"])) ?? [:]

        guard let assignmentId = RouteJSON.uuid(from: RouteJSON.value(in: assign, keys: ["id"])) else {
            throw RouteAssignmentsAPIError.decoding("Missing assignment id")
        }

        let routePlanId =
            RouteJSON.uuid(from: RouteJSON.value(in: assign, keys: ["route_plan_id", "routePlanId"]))
            ?? RouteJSON.uuid(from: RouteJSON.value(in: plan, keys: ["id"]))
        guard let routePlanId else {
            throw RouteAssignmentsAPIError.decoding("Missing route plan id")
        }

        let planNameRaw = RouteJSON.string(from: RouteJSON.value(in: plan, keys: ["name"])) ?? ""

        let assignee = RouteJSON.dictionary(from: RouteJSON.value(in: assign, keys: ["assignee"]))
        let assigner = RouteJSON.dictionary(from: RouteJSON.value(in: assign, keys: ["assigned_by", "assignedBy"]))

        let rawStops = RouteJSON.value(in: obj, keys: ["stops"])
        let stops = RouteJSON.dictionaryArray(from: rawStops)
            .enumerated()
            .map { RoutePlanStop($0.element, index: $0.offset) }
            .sorted { $0.stopOrder < $1.stopOrder }

        let priorityString: String? = {
            if let s = RouteJSON.string(from: RouteJSON.value(in: assign, keys: ["priority"])) { return s }
            if let i = RouteJSON.int(from: RouteJSON.value(in: assign, keys: ["priority"])) { return String(i) }
            return nil
        }()

        return RouteAssignmentDetailPayload(
            assignmentId: assignmentId,
            status: RouteJSON.string(from: RouteJSON.value(in: assign, keys: ["status"])) ?? "assigned",
            assignedToUserId: RouteJSON.uuid(from: RouteJSON.value(in: assign, keys: ["assigned_to_user_id", "assignedToUserId"])),
            assignedByUserId: RouteJSON.uuid(from: RouteJSON.value(in: assign, keys: ["assigned_by_user_id", "assignedByUserId"])),
            routePlanId: routePlanId,
            campaignId: RouteJSON.uuid(from: RouteJSON.value(in: plan, keys: ["campaign_id", "campaignId"])),
            planNameRaw: planNameRaw,
            totalStops: RouteJSON.int(from: RouteJSON.value(in: plan, keys: ["total_stops", "totalStops"])) ?? stops.count,
            estMinutes: RouteJSON.int(from: RouteJSON.value(in: plan, keys: ["est_minutes", "estMinutes"])),
            distanceMeters: RouteJSON.int(from: RouteJSON.value(in: plan, keys: ["distance_meters", "distanceMeters"])),
            dueAt: RouteJSON.date(from: RouteJSON.value(in: assign, keys: ["due_at", "dueAt"])),
            priority: priorityString,
            declineReason: RouteJSON.string(from: RouteJSON.value(in: assign, keys: ["decline_reason", "declineReason"])),
            assigneeDisplayName: RouteJSON.string(from: RouteJSON.value(in: assignee, keys: ["display_name", "displayName"])),
            assignedByDisplayName: RouteJSON.string(from: RouteJSON.value(in: assigner, keys: ["display_name", "displayName"])),
            stops: stops,
            workspaceRole: RouteJSON.string(from: obj["role"]) ?? "member"
        )
    }
}

struct RouteAssignmentMapPayload: Sendable {
    let detail: RouteAssignmentDetailPayload
    let buildings: BuildingFeatureCollection
    let addresses: AddressFeatureCollection
    let roads: RoadFeatureCollection?
    let bbox: [Double]?
    let generatedAt: Date?

    static func parse(_ obj: [String: Any]) throws -> RouteAssignmentMapPayload {
        let detail = try RouteAssignmentDetailPayload.parse(obj)
        let buildings: BuildingFeatureCollection = try decodeCollection(from: obj["buildings"])
        let addresses: AddressFeatureCollection = try decodeCollection(from: obj["addresses"])
        let roads: RoadFeatureCollection? = {
            guard let raw = obj["roads"], !(raw is NSNull) else { return nil }
            return try? decodeCollection(from: raw)
        }()
        let snapshot = RouteJSON.dictionary(from: obj["snapshot"])
        let bbox = (snapshot?["bbox"] as? [Any])?.compactMap { RouteJSON.double(from: $0) }

        return RouteAssignmentMapPayload(
            detail: detail,
            buildings: buildings,
            addresses: addresses,
            roads: roads,
            bbox: bbox?.count == 4 ? bbox : nil,
            generatedAt: RouteJSON.date(from: snapshot?["generated_at"])
        )
    }

    private static func decodeCollection<T: Decodable>(from raw: Any?) throws -> T {
        guard let raw else {
            throw RouteAssignmentsAPIError.decoding("Missing map payload")
        }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw) else {
            throw RouteAssignmentsAPIError.decoding("Invalid map payload")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RouteAssignmentsAPIError.decoding("Failed to decode map payload")
        }
    }
}

enum RouteAssignmentsAPIError: LocalizedError, Equatable {
    case invalidURL
    case network
    case unauthorized
    case notFound
    case forbidden(String?)
    case conflict(String)
    case http(Int, String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .network:
            return "No connection—try again."
        case .unauthorized:
            return "Sign in again to continue."
        case .notFound:
            return "Route not found."
        case .forbidden(let msg):
            return msg ?? "You don’t have access to this action."
        case .conflict(let msg):
            return msg
        case .http(let code, let msg):
            return msg ?? "Request failed (\(code))."
        case .decoding(let msg):
            return msg
        }
    }
}
