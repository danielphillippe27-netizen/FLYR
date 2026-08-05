import Foundation
import Combine
import Supabase

/// Fetches and caches user entitlement from GET /api/billing/entitlement.
/// Web/Stripe workspace billing is the source of truth for paid access.
@MainActor
final class EntitlementsService: ObservableObject {
    /// Shipping builds should enforce billing. Keep false unless intentionally running an internal unlock build.
    static let forceUnlockAllAccess = false

    private static let localProUnlockedKey = "flyr_local_pro_unlocked"

    /// Shared instance for UIKit (e.g. BuildingPopupView) to read canUsePro. Set by app root.
    static weak var sharedInstance: EntitlementsService?

    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var databaseProUnlocked = false

    /// Deprecated legacy StoreKit unlock flag. Kept for binary compatibility, but ignored for access.
    @Published private(set) var localProUnlocked: Bool {
        didSet { UserDefaults.standard.set(localProUnlocked, forKey: Self.localProUnlockedKey) }
    }

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "WOLFGRID_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://wolfgrid.app"
    }

    /// Use www when host is apex to avoid redirect stripping Authorization.
    private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "wolfgrid.app" else {
            return baseURL
        }
        return "https://wolfgrid.app"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        UserDefaults.standard.set(false, forKey: Self.localProUnlockedKey)
        localProUnlocked = false
        EntitlementsService.sharedInstance = self
    }

    /// True if user has paid Pro/Team access from backend workspace billing or entitlement state.
    var canUsePro: Bool {
        if Self.forceUnlockAllAccess { return true }
        if databaseProUnlocked { return true }
        guard let e = entitlement else { return false }
        guard e.isActive else { return false }
        let plan = e.plan.lowercased()
        guard plan == "pro" || plan == "team" else { return false }
        if let periodEnd = e.currentPeriodEnd {
            return periodEnd > Date()
        }
        return true
    }

    /// Deprecated: native StoreKit no longer grants access. Web billing is authoritative.
    func setLocalProUnlocked(_ value: Bool) {
        localProUnlocked = false
    }

    /// Fetch entitlement from backend. On 401, sets entitlement to free locally.
    /// Backend must never 404 (create-if-missing free row).
    func fetchEntitlement() async -> Entitlement {
        isLoading = true
        error = nil
        defer { isLoading = false }

        var fetchedEntitlement: Entitlement = .free

        do {
            let url = URL(string: "\(requestBaseURL)/api/billing/entitlement")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8

            let (data, http) = try await dataForAuthorizedRequest(request)

            if http.statusCode == 401 {
                fetchedEntitlement = .free
                entitlement = fetchedEntitlement
                databaseProUnlocked = await resolveWorkspaceAccessFromAPI()
                return fetchedEntitlement
            }

            guard (200...299).contains(http.statusCode) else {
                fetchedEntitlement = .free
                entitlement = fetchedEntitlement
                error = "Could not load subscription status."
                databaseProUnlocked = await resolveWorkspaceAccessFromAPI()
                return fetchedEntitlement
            }

            let value = try decoder.decode(Entitlement.self, from: data)
            fetchedEntitlement = value
            entitlement = fetchedEntitlement
            databaseProUnlocked = await resolveWorkspaceAccessFromAPI()
            return fetchedEntitlement
        } catch {
            fetchedEntitlement = .free
            entitlement = fetchedEntitlement
            self.error = error.localizedDescription
            databaseProUnlocked = await resolveWorkspaceAccessFromAPI()
            return fetchedEntitlement
        }
    }

    /// Workspace is the billing source of truth. Ask backend access state and cache workspace context.
    private func resolveWorkspaceAccessFromAPI() async -> Bool {
        do {
            let state = try await AccessAPI.shared.getState()
            WorkspaceContext.shared.update(from: state)
            #if DEBUG
            print(
                "🔐 [Entitlements] workspace access from /api/access/state -> \(state.hasAccess) " +
                "userId=\(state.userId ?? "nil") workspaceId=\(state.workspaceId ?? "nil") " +
                "role=\(state.role ?? "nil") reason=\(state.reason ?? "nil") " +
                "dashboardMode=\(state.dashboardMode ?? "nil") " +
                "salespersonId=\(state.salespersonId ?? "nil") " +
                "canUseSalespersonDashboard=\(state.canUseSalespersonDashboard)"
            )
            #endif
            return paidAccess(from: state)
        } catch {
            #if DEBUG
            print("⚠️ [Entitlements] access state lookup failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    private func paidAccess(from state: AccessStateResponse) -> Bool {
        if state.isFounder || state.isAmbassador { return true }
        let plan = state.plan?.lowercased() ?? ""
        return plan == "pro" || plan == "team" || plan == "ambassador"
    }

    /// Send Apple transaction to backend for verification and entitlement update.
    /// Call after a verified purchase, before transaction.finish().
    func verifyAppleTransaction(
        transactionId: String,
        productId: String
    ) async throws {
        let url = URL(string: "\(requestBaseURL)/api/billing/apple/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AppleVerifyRequest(
                transactionId: transactionId,
                productId: productId
            )
        )

        let (_, http) = try await dataForAuthorizedRequest(request)
        guard (200...299).contains(http.statusCode) else {
            throw BillingError.server("Verification failed. Try Restore Purchases.")
        }
    }

    /// Uses access token from current session and retries once with refreshSession() on 401.
    private func dataForAuthorizedRequest(
        _ request: URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        var authedRequest = request
        let session = try await SupabaseManager.shared.client.auth.session
        authedRequest.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: authedRequest)
        guard let http = response as? HTTPURLResponse else {
            throw BillingError.network("No connection—try again.")
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
                throw BillingError.network("No connection—try again.")
            }
            return (retryData, retryHTTP)
        } catch {
            return (data, http)
        }
    }
}

enum BillingError: LocalizedError {
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .network(let msg), .server(let msg): return msg
        }
    }
}
