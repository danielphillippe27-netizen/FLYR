import Foundation
import Combine
import StoreKit

/// StoreKit 2: load products, purchase (verify before finish), restore, and listen for Transaction.updates.
@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    enum ProductId {
        static let monthly = "com.danielphillippe.flyr.pro.monthly"
        static let annual = "com.danielphillippe.flyr.pro.annual"
        /// Hidden legacy annual SKU kept for restore/entitlement sync only.
        static let legacyYearly = "com.danielphillippe.flyr.pro.yearly"
        /// Product IDs actively sold in the paywall.
        static var storefront: [String] { [monthly, annual] }
        /// Product IDs accepted for restore and entitlement sync.
        static var restorable: [String] { [monthly, annual, legacyYearly] }
    }

    @Published private(set) var products: [Product] = []
    /// Products by id for quick lookup in PaywallView.
    @Published private(set) var productsById: [String: Product] = [:]
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    /// Set from app root after EntitlementsService is created so verify + refresh can run.
    weak var entitlementsService: EntitlementsService?

    private var lastVerifiedTransactionIds: Set<UInt64> = []
    private let debounceInterval: TimeInterval = 60
    private var lastDebounceClear = Date()

    private init() {
        Task { await listenForTransactionUpdates() }
    }

    func loadProducts() async {
        do {
            let list = try await Product.products(for: Set(ProductId.storefront))
            products = list.sorted { $0.price < $1.price }
            productsById = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
            #if DEBUG
            let ids = products.map(\.id).joined(separator: ", ")
            print("🧾 [StoreKit] loaded \(products.count) products: \(ids)")
            if products.isEmpty {
                print("⚠️ [StoreKit] No App Store products returned for ids: \(ProductId.storefront.joined(separator: ", "))")
            }
            #endif
        } catch {
            #if DEBUG
            print("❌ [StoreKit] loadProducts failed: \(error)")
            #endif
        }
    }

    func product(forId id: String) -> Product? { productsById[id] }

    /// Purchase: finish transaction, set local Pro unlock (Layer 1), then optionally verify + fetch (Layer 2).
    /// Returns true only when a verified transaction completes.
    func purchase(_ product: Product) async throws -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            throw mapStoreKitError(error)
        }
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                entitlementsService?.setLocalProUnlocked(true)
                // Layer 2: verify + fetch in background (non-blocking)
                if let entitlements = entitlementsService {
                    Task {
                        do {
                            try await entitlements.verifyAppleTransaction(
                                transactionId: String(transaction.id),
                                productId: product.id
                            )
                        } catch {
                            #if DEBUG
                            print("⚠️ [StoreKit] Apple verify failed after purchase: \(error.localizedDescription)")
                            #endif
                        }
                        _ = await entitlements.fetchEntitlement()
                    }
                }
                return true
            case .unverified:
                throw BillingError.server("Purchase could not be verified.")
            }
        case .userCancelled:
            return false
        case .pending:
            throw BillingError.server("Purchase is pending approval.")
        @unknown default:
            throw BillingError.server("Purchase failed.")
        }
    }

    /// Restore: sync, set local Pro unlock if we find current entitlements (Layer 1), optionally verify (Layer 2).
    func restorePurchases() async throws {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
        } catch {
            throw mapStoreKitError(error)
        }
        var latest: (transaction: Transaction, productId: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductId.restorable.contains(transaction.productID) else { continue }
            guard Self.isActiveSubscription(transaction) else { continue }
            if latest == nil || transaction.purchaseDate > latest!.transaction.purchaseDate {
                latest = (transaction, transaction.productID)
            }
        }
        entitlementsService?.setLocalProUnlocked(latest != nil)
        if let (transaction, productId) = latest, let entitlements = entitlementsService {
            Task {
                do {
                    try await entitlements.verifyAppleTransaction(
                        transactionId: String(transaction.id),
                        productId: productId
                    )
                } catch {
                    #if DEBUG
                    print("⚠️ [StoreKit] Apple verify failed during restore: \(error.localizedDescription)")
                    #endif
                }
                _ = await entitlements.fetchEntitlement()
            }
        }
    }

    /// Layer 1: On launch, set local Pro unlock if StoreKit reports an active subscription.
    func refreshLocalProFromCurrentEntitlements() async {
        var hasActiveSubscription = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductId.restorable.contains(transaction.productID) else { continue }
            guard Self.isActiveSubscription(transaction) else { continue }
            hasActiveSubscription = true
            break
        }
        entitlementsService?.setLocalProUnlocked(hasActiveSubscription)
    }

    /// Listen for transaction updates (e.g. renewals). Verify first, then finish. Debounce by transaction id.
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard ProductId.restorable.contains(transaction.productID) else {
                await transaction.finish()
                continue
            }
            // Debounce
            if lastVerifiedTransactionIds.contains(transaction.id) {
                await transaction.finish()
                continue
            }
            if Date().timeIntervalSince(lastDebounceClear) > debounceInterval {
                lastVerifiedTransactionIds.removeAll()
                lastDebounceClear = Date()
            }
            guard entitlementsService != nil else {
                await transaction.finish()
                continue
            }
            await transaction.finish()
            await refreshLocalProFromCurrentEntitlements()
            lastVerifiedTransactionIds.insert(transaction.id)
            Task {
                do {
                    try await entitlementsService?.verifyAppleTransaction(
                        transactionId: String(transaction.id),
                        productId: transaction.productID
                    )
                } catch {
                    #if DEBUG
                    print("⚠️ [StoreKit] Apple verify failed from transaction updates: \(error.localizedDescription)")
                    #endif
                }
                _ = await entitlementsService?.fetchEntitlement()
            }
        }
    }

    private static func isActiveSubscription(_ transaction: Transaction) -> Bool {
        if transaction.revocationDate != nil {
            return false
        }
        if let expirationDate = transaction.expirationDate {
            return expirationDate > Date()
        }
        return true
    }

    private func mapStoreKitError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == "ASDErrorDomain", nsError.code == 509 {
            return BillingError.server(
                "No active App Store Sandbox account. Open Settings > Developer > Sandbox Account and sign in."
            )
        }
        if nsError.domain == "ASDErrorDomain", nsError.code == 530 {
            return BillingError.server(
                "Sandbox authentication failed. Sign out/in Sandbox Account or create a new Sandbox tester."
            )
        }
        if nsError.domain == "AMSErrorDomain", nsError.code == 100 || nsError.code == 2 {
            return BillingError.server(
                "Sandbox account authentication failed. Re-login Sandbox Account in Settings."
            )
        }
        return error
    }
}
