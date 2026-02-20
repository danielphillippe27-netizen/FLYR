import Foundation
import SwiftUI
import Combine

/// Holds current app route (from access redirect) and pending join token for deep link. Call resolveRoute() after session load and on auth/foreground changes.
@MainActor
final class AppRouteState: ObservableObject {
    @Published private(set) var route: AppRoute = .login
    @Published private(set) var isResolving = false
    /// Set when user opens join URL before auth; cleared after accept or when going to login without join.
    @Published var pendingJoinToken: String?

    /// When true, the next resolveRoute() will keep onboarding and not call the API (avoids overwriting route right after sign-up).
    private var skipNextResolveForOnboarding = false

    private let auth = AuthManager.shared

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

        // If we have a pending join token (deep link), don't call redirect yet — join flow will call accept then resolve again.
        if let token = pendingJoinToken, !token.isEmpty {
            route = .join(token: token)
            return
        }

        do {
            let redirect = try await AccessAPI.shared.getRedirect()
            var resolved = mapRedirectToRoute(redirect)
            // If backend says "login" but we're already signed in, go to dashboard so existing users enter the app.
            if case .login = resolved {
                resolved = .dashboard
            }
            route = resolved
            #if DEBUG
            print("🔍 [AppRouteState] getRedirect → \(redirect.redirect) → route: \(route)")
            #endif
            let state = try? await AccessAPI.shared.getState()
            if let state = state {
                await WorkspaceContext.shared.update(from: state)
                // If access state didn't include workspace (e.g. legacy response), resolve from DB so campaign creation etc. have a workspace.
                if WorkspaceContext.shared.workspaceId == nil {
                    _ = await RoutePlansAPI.shared.resolveWorkspaceId(preferred: nil)
                }
            }
        } catch let error as AccessAPIError {
            if case .unauthorized = error {
                // Backend returned 401 but we have a session. Go to dashboard so user can enter the app.
                #if DEBUG
                print("⚠️ [AppRouteState] getRedirect 401 → sending to dashboard")
                #endif
                route = .dashboard
            } else {
                #if DEBUG
                print("⚠️ [AppRouteState] getRedirect failed: \(error)")
                #endif
                route = .dashboard
            }
        } catch {
            #if DEBUG
            print("⚠️ [AppRouteState] getRedirect failed: \(error)")
            #endif
            route = .dashboard
        }
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
            return .subscribe(memberInactive: r.path.contains("reason=member-inactive"))
        case "contact-owner":
            return .subscribe(memberInactive: true)
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

    /// Call after user signs in and we have pendingJoinToken: accept invite then resolve. Clears pendingJoinToken.
    func acceptPendingInviteAndResolve() async {
        guard let token = pendingJoinToken, !token.isEmpty else {
            await resolveRoute()
            return
        }
        do {
            let response = try await InviteService.shared.accept(token: token)
            pendingJoinToken = nil
            if let wid = UUID(uuidString: response.workspaceId) {
                await WorkspaceContext.shared.update(workspaceId: wid, name: nil, role: "member")
            }
            await resolveRoute()
        } catch {
            #if DEBUG
            print("⚠️ [AppRouteState] accept invite failed: \(error)")
            #endif
            pendingJoinToken = nil
            await resolveRoute()
        }
    }

    /// Clear pending join token (e.g. user dismissed join or token invalid).
    func clearPendingJoinToken() {
        pendingJoinToken = nil
    }

    /// Set route directly (e.g. after onboarding complete -> subscribe).
    func setRoute(_ newRoute: AppRoute) {
        route = newRoute
    }
}
