import Foundation
import Combine
import Supabase

/// Fetches and caches user entitlement from GET /api/billing/entitlement.
/// Layer 1: Also honors local Pro unlock (StoreKit purchase/restore) so TestFlight works without backend.
/// Layer 2: Backend verify + entitlement sync can replace local unlock later.
@MainActor
final class EntitlementsService: ObservableObject {
    private static let localProUnlockedKey = "flyr_local_pro_unlocked"

    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    /// Layer 1: Set when StoreKit purchase or restore succeeds. Persisted so Pro survives app restart.
    @Published private(set) var localProUnlocked: Bool {
        didSet { UserDefaults.standard.set(localProUnlocked, forKey: Self.localProUnlockedKey) }
    }

    private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        localProUnlocked = UserDefaults.standard.bool(forKey: Self.localProUnlockedKey)
    }

    /// True if user has Pro: server entitlement (apple/stripe) OR local unlock from StoreKit (Layer 1).
    var canUsePro: Bool {
        if localProUnlocked { return true }
        guard let e = entitlement else { return false }
        return e.isActive && (e.plan == "pro" || e.plan == "team")
    }

    /// Layer 1: Call after successful StoreKit purchase or restore. Later replace with verify + fetch.
    func setLocalProUnlocked(_ value: Bool) {
        localProUnlocked = value
    }

    /// Fetch entitlement from backend. On 401, sets entitlement to free locally.
    /// Backend must never 404 (create-if-missing free row).
    func fetchEntitlement() async -> Entitlement {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            let url = URL(string: "\(baseURL)/api/billing/entitlement")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                entitlement = .free
                return .free
            }

            if http.statusCode == 401 {
                entitlement = .free
                return .free
            }

            guard (200...299).contains(http.statusCode) else {
                entitlement = .free
                error = "Could not load subscription status."
                return .free
            }

            let value = try decoder.decode(Entitlement.self, from: data)
            entitlement = value
            return value
        } catch {
            entitlement = .free
            self.error = error.localizedDescription
            return .free
        }
    }

    /// Send Apple transaction to backend for verification and entitlement update.
    /// Call after a verified purchase, before transaction.finish().
    func verifyAppleTransaction(transactionId: String, productId: String) async throws {
        let session = try await SupabaseManager.shared.client.auth.session
        let url = URL(string: "\(baseURL)/api/billing/apple/verify")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(AppleVerifyRequest(transactionId: transactionId, productId: productId))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BillingError.network("No connection—try again.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw BillingError.server("Verification failed. Try Restore Purchases.")
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
