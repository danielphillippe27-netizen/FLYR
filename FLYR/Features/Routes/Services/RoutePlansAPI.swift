import Foundation
import Supabase

@MainActor
final class RoutePlansAPI {
    static let shared = RoutePlansAPI()

    private let client = SupabaseManager.shared.client

    private init() {}

    func resolveWorkspaceId(preferred workspaceId: UUID?) async -> UUID? {
        await resolveWorkspaceId(
            preferred: workspaceId,
            createIfMissing: true,
            allowCachedContext: true
        )
    }

    /// Resolve only an already-existing workspace for the current user.
    /// Does not create a default workspace when missing.
    func existingWorkspaceIdForCurrentUser(preferred workspaceId: UUID? = nil) async -> UUID? {
        await resolveWorkspaceId(
            preferred: workspaceId,
            createIfMissing: false,
            allowCachedContext: false
        )
    }

    private func resolveWorkspaceId(
        preferred workspaceId: UUID?,
        createIfMissing: Bool,
        allowCachedContext: Bool
    ) async -> UUID? {
        if let workspaceId {
            debugLog("🏢 [WORKSPACE] Using preferred workspace: \(workspaceId)")
            return workspaceId
        }
        if allowCachedContext, let existing = WorkspaceContext.shared.workspaceId {
            debugLog("🏢 [WORKSPACE] Using cached workspace: \(existing)")
            return existing
        }

        // 1) Try access state (backend source of truth for current workspace context).
        do {
            let state = try await AccessAPI.shared.getState()
            debugLog("🏢 [WORKSPACE] Access state workspaceId: \(state.workspaceId ?? "nil")")
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
            debugLog("⚠️ [WORKSPACE] Access state failed: \(error)")
        }

        // 2) Try helper RPC when available.
        let session = try? await client.auth.session
        if let session {
            do {
                let rpcWorkspaceId = try await fetchPrimaryWorkspaceIdViaRPC(session: session)
                if let rpcWorkspaceId {
                    WorkspaceContext.shared.update(
                        workspaceId: rpcWorkspaceId,
                        name: WorkspaceContext.shared.workspaceName,
                        role: WorkspaceContext.shared.role
                    )
                    return rpcWorkspaceId
                }
                // RPC succeeded and returned null: user likely has no workspace yet.
                if createIfMissing,
                   let createdWorkspaceId = await createDefaultWorkspaceIfMissing(session: session) {
                    WorkspaceContext.shared.update(
                        workspaceId: createdWorkspaceId,
                        name: WorkspaceContext.shared.workspaceName,
                        role: "owner"
                    )
                    return createdWorkspaceId
                }
            } catch {
                debugLog("⚠️ [WORKSPACE] RPC failed: \(error)")
                // Continue to DB fallbacks for legacy environments where RPC is unavailable.
            }
        }

        // 3) Legacy fallback: direct table lookups when RPC path is unavailable.
        if let session {
            do {
                let memberResponse = try await client
                    .from("workspace_members")
                    .select("workspace_id")
                    .eq("user_id", value: session.user.id.uuidString)
                    .order("created_at", ascending: true)
                    .limit(1)
                    .execute()
                debugLog("🏢 [WORKSPACE] Workspace members resolved from backend")

                if let memberWorkspaceId = Self.extractWorkspaceId(from: memberResponse.data) {
                    WorkspaceContext.shared.update(
                        workspaceId: memberWorkspaceId,
                        name: WorkspaceContext.shared.workspaceName,
                        role: WorkspaceContext.shared.role
                    )
                    return memberWorkspaceId
                }
            } catch {
                debugLog("⚠️ [WORKSPACE] Membership lookup failed: \(error)")
                // If policy recursion blocks reads, we can still try direct create.
                if createIfMissing,
                   isPolicyRecursionError(error),
                   let createdWorkspaceId = await createDefaultWorkspaceIfMissing(session: session) {
                    WorkspaceContext.shared.update(
                        workspaceId: createdWorkspaceId,
                        name: WorkspaceContext.shared.workspaceName,
                        role: "owner"
                    )
                    return createdWorkspaceId
                }
            }
        }

        if createIfMissing {
            debugLog("❌ [WORKSPACE] All resolution strategies failed — no workspace found")
        } else {
            debugLog("ℹ️ [WORKSPACE] No existing workspace found for current user")
        }
        return nil
    }

    private func createDefaultWorkspaceIfMissing(session: Session) async -> UUID? {
        let workspaceName = defaultWorkspaceName(for: session)
        let workspaceValues: [String: AnyCodable] = [
            "name": AnyCodable(workspaceName),
            "owner_id": AnyCodable(session.user.id.uuidString)
        ]

        do {
            // Insert without a select to avoid policy-recursive reads on some environments.
            let insertResponse = try await client
                .from("workspaces")
                .insert(workspaceValues)
                .execute()
            debugLog("🏢 [WORKSPACE] Default workspace insert completed")

            if let insertedId = Self.extractWorkspaceId(from: insertResponse.data) {
                return insertedId
            }

            // Resolve freshly-created workspace via SECURITY DEFINER helper.
            if let resolvedId = try await fetchPrimaryWorkspaceIdViaRPC(session: session) {
                debugLog("🏢 [WORKSPACE] Resolved workspace after create: \(resolvedId)")
                return resolvedId
            }
        } catch {
            debugLog("⚠️ [WORKSPACE] Default workspace creation failed: \(error)")
        }
        return nil
    }

    private func fetchPrimaryWorkspaceIdViaRPC(session: Session) async throws -> UUID? {
        let params: [String: AnyCodable] = [
            "p_user_id": AnyCodable(session.user.id.uuidString)
        ]
        let response = try await client
            .rpc("primary_workspace_id", params: params)
            .execute()
        debugLog("🏢 [WORKSPACE] RPC workspace lookup completed")
        return Self.extractWorkspaceId(from: response.data)
    }

    private func isPolicyRecursionError(_ error: Error) -> Bool {
        if let postgrestError = error as? PostgrestError {
            if postgrestError.code == "42P17" {
                return true
            }
            if postgrestError.message.localizedCaseInsensitiveContains("infinite recursion") {
                return true
            }
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("infinite recursion")
    }

    private func defaultWorkspaceName(for session: Session) -> String {
        let emailPrefix = session.user.email?
            .split(separator: "@")
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let emailPrefix, !emailPrefix.isEmpty {
            return "\(emailPrefix)'s Workspace"
        }
        return "My Workspace"
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

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        print(message())
        #endif
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
