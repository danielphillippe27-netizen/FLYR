import Foundation
import Combine
import StoreKit

/// StoreKit 2: load products, purchase (verify before finish), restore, and listen for Transaction.updates.
@MainActor
final class StoreKitManager: ObservableObject {
    static let shared = StoreKitManager()

    enum ProductId {
        static let monthly = "com.danielphillippe.flyr.pro.monthly"
        static let yearly = "com.danielphillippe.flyr.pro.yearly"
        static let annual = "com.danielphillippe.flyr.pro.annual"
        /// All known subscription product IDs (yearly and annual both supported for backward compatibility).
        static var all: [String] { [monthly, yearly, annual] }
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
            let list = try await Product.products(for: Set(ProductId.all))
            products = list.sorted { $0.price < $1.price }
            productsById = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            #if DEBUG
            print("❌ [StoreKit] loadProducts failed: \(error)")
            #endif
        }
    }

    func product(forId id: String) -> Product? { productsById[id] }

    /// Purchase: finish transaction, set local Pro unlock (Layer 1), then optionally verify + fetch (Layer 2).
    func purchase(_ product: Product) async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                entitlementsService?.setLocalProUnlocked(true)
                // Layer 2: verify + fetch in background (non-blocking)
                if let entitlements = entitlementsService {
                    Task {
                        try? await entitlements.verifyAppleTransaction(
                            transactionId: String(transaction.id),
                            productId: product.id
                        )
                        await entitlements.fetchEntitlement()
                    }
                }
            case .unverified:
                throw BillingError.server("Purchase could not be verified.")
            }
        case .userCancelled:
            return
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

        try await AppStore.sync()
        var latest: (transaction: Transaction, productId: String)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductId.all.contains(transaction.productID) else { continue }
            entitlementsService?.setLocalProUnlocked(true)
            if latest == nil || transaction.purchaseDate > latest!.transaction.purchaseDate {
                latest = (transaction, transaction.productID)
            }
        }
        if let (transaction, productId) = latest, let entitlements = entitlementsService {
            Task {
                try? await entitlements.verifyAppleTransaction(
                    transactionId: String(transaction.id),
                    productId: productId
                )
                await entitlements.fetchEntitlement()
            }
        }
    }

    /// Layer 1: On launch, set local Pro unlock if StoreKit reports an active subscription.
    func refreshLocalProFromCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ProductId.all.contains(transaction.productID) else { continue }
            entitlementsService?.setLocalProUnlocked(true)
            return
        }
    }

    /// Listen for transaction updates (e.g. renewals). Verify first, then finish. Debounce by transaction id.
    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            guard ProductId.all.contains(transaction.productID) else {
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
            guard let entitlements = entitlementsService else {
                await transaction.finish()
                continue
            }
            await transaction.finish()
            await MainActor.run {
                entitlementsService?.setLocalProUnlocked(true)
            }
            lastVerifiedTransactionIds.insert(transaction.id)
            Task {
                try? await entitlementsService?.verifyAppleTransaction(
                    transactionId: String(transaction.id),
                    productId: transaction.productID
                )
                await entitlementsService?.fetchEntitlement()
            }
        }
    }
}
