import Foundation
import Supabase

@MainActor
final class RoutePlansAPI {
    static let shared = RoutePlansAPI()

    private let client = SupabaseManager.shared.client

    private init() {}

    func resolveWorkspaceId(preferred workspaceId: UUID?) async -> UUID? {
        if let workspaceId {
            print("🏢 [WORKSPACE] Using preferred workspace: \(workspaceId)")
            return workspaceId
        }
        if let existing = WorkspaceContext.shared.workspaceId {
            print("🏢 [WORKSPACE] Using cached workspace: \(existing)")
            return existing
        }

        // 1) Try access state (backend source of truth for current workspace context).
        do {
            let state = try await AccessAPI.shared.getState()
            print("🏢 [WORKSPACE] Access state workspaceId: \(state.workspaceId ?? "nil")")
            if let workspaceIdString = state.workspaceId,
               let parsedWorkspaceId = UUID(uuidString: workspaceIdString) {
                WorkspaceContext.shared.update(
                    workspaceId: parsedWorkspaceId,
                    name: state.workspaceName,
                    role: state.role
                )
                return parsedWorkspaceId
            }
        } catch {
            print("⚠️ [WORKSPACE] Access state failed: \(error)")
        }

        // 2) Try helper RPC when available.
        do {
            let session = try await client.auth.session
            let params: [String: AnyCodable] = [
                "p_user_id": AnyCodable(session.user.id.uuidString)
            ]
            let response = try await client
                .rpc("primary_workspace_id", params: params)
                .execute()
            print("🏢 [WORKSPACE] RPC response: \(String(data: response.data, encoding: .utf8) ?? "nil")")
            if let resolvedWorkspaceId = Self.extractWorkspaceId(from: response.data) {
                WorkspaceContext.shared.update(
                    workspaceId: resolvedWorkspaceId,
                    name: WorkspaceContext.shared.workspaceName,
                    role: WorkspaceContext.shared.role
                )
                return resolvedWorkspaceId
            }
        } catch {
            print("⚠️ [WORKSPACE] RPC failed: \(error)")
            // Continue to DB fallbacks — do NOT return nil here.
        }

        // 3) Fallback to direct table lookup: owned workspace first.
        do {
            let session = try await client.auth.session
            let ownedResponse = try await client
                .from("workspaces")
                .select("id")
                .eq("owner_id", value: session.user.id.uuidString)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
            print("🏢 [WORKSPACE] Owned workspaces response: \(String(data: ownedResponse.data, encoding: .utf8) ?? "nil")")

            if let ownedId = Self.extractWorkspaceId(from: ownedResponse.data) {
                WorkspaceContext.shared.update(
                    workspaceId: ownedId,
                    name: WorkspaceContext.shared.workspaceName,
                    role: WorkspaceContext.shared.role
                )
                return ownedId
            }

            // 4) Fallback to first membership.
            let memberResponse = try await client
                .from("workspace_members")
                .select("workspace_id")
                .eq("user_id", value: session.user.id.uuidString)
                .order("created_at", ascending: true)
                .limit(1)
                .execute()
            print("🏢 [WORKSPACE] Workspace members response: \(String(data: memberResponse.data, encoding: .utf8) ?? "nil")")

            if let memberWorkspaceId = Self.extractWorkspaceId(from: memberResponse.data) {
                WorkspaceContext.shared.update(
                    workspaceId: memberWorkspaceId,
                    name: WorkspaceContext.shared.workspaceName,
                    role: WorkspaceContext.shared.role
                )
                return memberWorkspaceId
            }
        } catch {
            print("⚠️ [WORKSPACE] DB lookup failed: \(error)")
        }

        print("❌ [WORKSPACE] All resolution strategies failed — no workspace found")
        return nil
    }

    func fetchMyAssignedRoutes(workspaceId: UUID?) async throws -> [RouteAssignmentSummary] {
        guard let workspaceId else { return [] }

        let params: [String: AnyCodable] = [
            "p_workspace_id": AnyCodable(workspaceId.uuidString)
        ]
        let response = try await client
            .rpc("get_my_assigned_routes", params: params)
            .execute()

        let rows = try RouteJSON.rows(from: response.data)
        return rows
            .compactMap(RouteAssignmentSummary.init(_:))
            .sorted { lhs, rhs in
                let lhsDate = lhs.updatedAt ?? .distantPast
                let rhsDate = rhs.updatedAt ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    func fetchRoutePlanDetail(routePlanId: UUID) async throws -> RoutePlanDetail {
        let params: [String: AnyCodable] = [
            "p_route_plan_id": AnyCodable(routePlanId.uuidString)
        ]
        let response = try await client
            .rpc("get_route_plan_detail", params: params)
            .execute()

        let rows = try RouteJSON.rows(from: response.data)
        if let detail = rows.compactMap(RoutePlanDetail.init(_:)).first {
            return detail
        }
        throw RoutePlansAPIError.emptyResponse
    }

    /// Returns the current user's primary (universal) workspace ID: uses existing context first, then access state, then RPC/DB. Use for campaign creation so new campaigns save to the user's canonical workspace.
    func primaryWorkspaceIdForCurrentUser() async -> UUID? {
        await resolveWorkspaceId(preferred: nil)
    }
}

private extension RoutePlansAPI {
    static func extractWorkspaceId(from data: Data) -> UUID? {
        // 1) Try standard JSON (object, array, or string value).
        if let object = try? JSONSerialization.jsonObject(with: data),
           let uuid = extractWorkspaceId(from: object) {
            return uuid
        }
        // 2) PostgREST RPC scalar often returns raw quoted string; parse as UTF-8 and strip quotes.
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if let raw = raw, let uuid = UUID(uuidString: raw) {
            return uuid
        }
        return nil
    }

    static func extractWorkspaceId(from object: Any) -> UUID? {
        if let string = object as? String {
            return UUID(uuidString: string)
        }

        if let dictionary = object as? [String: Any] {
            let candidates = [
                dictionary["primary_workspace_id"],
                dictionary["workspace_id"],
                dictionary["workspaceId"],
                dictionary["id"]
            ]
            for candidate in candidates {
                if let candidateString = candidate as? String,
                   let parsed = UUID(uuidString: candidateString) {
                    return parsed
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for element in array {
                if let parsed = extractWorkspaceId(from: element) {
                    return parsed
                }
            }
        }

        return nil
    }
}

enum RoutePlansAPIError: LocalizedError {
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "No route data was returned."
        }
    }
}
