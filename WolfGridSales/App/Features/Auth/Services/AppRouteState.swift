import Foundation
import SwiftUI
import Combine
import Supabase
import Auth

enum PasswordResetFlowState: Equatable {
    case idle
    case awaitingLink
    case ready(email: String?)
    case invalid(message: String)
    case success(message: String)
}

/// Holds current app route (from access redirect) and pending join token for deep link. Call resolveRoute() after session load and on auth/foreground changes.
@MainActor
final class AppRouteState: ObservableObject {
    @Published private(set) var route: AppRoute = .login
    @Published private(set) var isResolving = false
    /// Set when user opens join URL before auth; cleared after accept or when going to login without join.
    @Published var pendingJoinToken: String?
    @Published var pendingChallengeToken: String?
    @Published private(set) var passwordResetState: PasswordResetFlowState = .idle
    @Published private(set) var passwordResetEmailHint = ""

    /// When true, the next resolveRoute() will keep onboarding and not call the API (avoids overwriting route right after sign-up).
    private var skipNextResolveForOnboarding = false
    private let auth = AuthManager.shared

    var isPasswordResetActive: Bool {
        passwordResetState != .idle
    }

    /// Call after sign-up to show onboarding. The next resolveRoute() (e.g. from auth change) will not overwrite with API.
    func setRouteToOnboardingFromSignUp() {
        route = .onboarding
        skipNextResolveForOnboarding = true
    }

    /// Call after loadSession() and on auth.user change / scenePhase .active. Resolves route via GET /api/access/redirect or pending join.
    func resolveRoute() async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }

        if isPasswordResetActive {
            route = .passwordReset
            return
        }

        if let token = pendingChallengeToken, !token.isEmpty {
            route = .challengeInvite(token: token)
            return
        }

        if let token = pendingJoinToken, !token.isEmpty {
            route = .join(token: token)
            return
        }

        if auth.user == nil {
            route = .login
            skipNextResolveForOnboarding = false
            return
        }

        if skipNextResolveForOnboarding {
            skipNextResolveForOnboarding = false
            route = .onboarding
            return
        }

        do {
            let redirect = try await AccessAPI.shared.getRedirect()
            let state = try? await AccessAPI.shared.getState()
            if let state {
                WorkspaceContext.shared.update(from: state)
            }

            var resolved = mapRedirectToRoute(redirect)
            // If backend says "login" but we're already signed in, infer route from access state.
            if case .login = resolved {
                resolved = fallbackRouteForSignedInUser(state: state)
            }
            resolved = await recoverOnboardingRouteForExistingWorkspace(resolved, state: state)
            route = resolved
            #if DEBUG
            print(
                "🔍 [AppRouteState] getRedirect → \(redirect.redirect) → route: \(route) " +
                "dashboardMode=\(state?.dashboardMode ?? "nil") " +
                "salespersonId=\(state?.salespersonId ?? "nil") " +
                "canUseSalespersonDashboard=\(state?.canUseSalespersonDashboard == true) " +
                "effectiveDashboardMode=\(WorkspaceContext.shared.dashboardMode ?? "nil") " +
                "effectiveCanUseSalespersonDashboard=\(WorkspaceContext.shared.canUseSalespersonDashboard)"
            )
            #endif
        } catch let error as AccessAPIError {
            if case .unauthorized = error {
                #if DEBUG
                print("⚠️ [AppRouteState] getRedirect 401 → using signed-in fallback route")
                #endif
                let fallback = fallbackRouteForSignedInUser(state: nil)
                route = await recoverOnboardingRouteForExistingWorkspace(fallback, state: nil)
            } else {
                #if DEBUG
                print("⚠️ [AppRouteState] getRedirect failed: \(error)")
                #endif
                let fallback = fallbackRouteForSignedInUser(state: nil)
                route = await recoverOnboardingRouteForExistingWorkspace(fallback, state: nil)
            }
        } catch {
            #if DEBUG
            print("⚠️ [AppRouteState] getRedirect failed: \(error)")
            #endif
            let fallback = fallbackRouteForSignedInUser(state: nil)
            route = await recoverOnboardingRouteForExistingWorkspace(fallback, state: nil)
        }
    }

    /// Fallback when redirect returns "login" while an auth session exists.
    /// Prefer server-backed access state and conservative routing when access APIs are unavailable.
    private func fallbackRouteForSignedInUser(state: AccessStateResponse?) -> AppRoute {
        if let state {
            let workspaceId = state.workspaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if workspaceId.isEmpty {
                return .onboarding
            }
            if state.hasAccess {
                return .dashboard
            }
            return .dashboard
        }

        // Offline field use should trust the last known local workspace context instead of
        // bouncing a signed-in user back into onboarding just because access APIs are unreachable.
        if WorkspaceContext.shared.workspaceId != nil {
            return .dashboard
        }
        return .onboarding
    }

    /// If backend redirects to onboarding but this signed-in user already has a workspace,
    /// route into the app instead of forcing onboarding again.
    private func recoverOnboardingRouteForExistingWorkspace(
        _ route: AppRoute,
        state: AccessStateResponse?
    ) async -> AppRoute {
        guard case .onboarding = route else { return route }
        let workspaceFromState = state?.workspaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard workspaceFromState.isEmpty else { return route }

        if WorkspaceContext.shared.workspaceId != nil {
            return fallbackRouteForSignedInUser(state: state)
        }

        if let state, !state.hasAccess {
            return .dashboard
        }

        return route
    }

    /// Map backend redirect response to AppRoute. Path may contain query (e.g. /join?token=..., /subscribe?reason=member-inactive).
    private func mapRedirectToRoute(_ r: AccessRedirectResponse) -> AppRoute {
        switch r.redirect.lowercased() {
        case "login":
            return .login
        case "onboarding":
            return .onboarding
        case "join":
            if let token = tokenFromPath(r.path) {
                return .join(token: token)
            }
            return .login
        case "subscribe":
            return .dashboard
        case "contact-owner":
            return .dashboard
        case "dashboard":
            return .dashboard
        default:
            return .dashboard
        }
    }

    private func tokenFromPath(_ path: String) -> String? {
        guard let queryStart = path.firstIndex(of: "?"), queryStart != path.endIndex else { return nil }
        let query = String(path[path.index(after: queryStart)...])
        let pairs = query.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1) }
        for pair in pairs where pair.count == 2 {
            if String(pair[0]).removingPercentEncoding == "token" {
                return String(pair[1]).removingPercentEncoding
            }
        }
        return nil
    }

    /// Clear pending join token (e.g. user dismissed join or token invalid).
    func clearPendingJoinToken() {
        pendingJoinToken = nil
    }

    func clearPendingChallengeToken() {
        pendingChallengeToken = nil
    }

    func updatePasswordResetEmailHint(_ email: String?) {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            passwordResetEmailHint = trimmed
        }
    }

    func presentPasswordReset(state: PasswordResetFlowState, emailHint: String? = nil) {
        updatePasswordResetEmailHint(emailHint)
        passwordResetState = state
        route = .passwordReset
    }

    func clearPasswordResetFlow() {
        passwordResetState = .idle
        passwordResetEmailHint = ""
    }

    func completePasswordResetFlow() async {
        clearPasswordResetFlow()
        await resolveRoute()
    }

    /// Call after the explicit join flow has already accepted the invite successfully.
    func completePendingJoinAndResolve(workspaceId: String?) async {
        pendingJoinToken = nil
        if let workspaceId,
           let wid = UUID(uuidString: workspaceId) {
            WorkspaceContext.shared.update(workspaceId: wid, name: nil, role: "member")
        }
        await resolveRoute()
    }

    func completePendingChallengeAndResolve() async {
        pendingChallengeToken = nil
        await resolveRoute()
    }

    /// Set route directly (e.g. after onboarding complete -> subscribe).
    func setRoute(_ newRoute: AppRoute) {
        route = newRoute
    }
}
