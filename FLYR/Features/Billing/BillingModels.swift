import Foundation

// MARK: - Entitlement (GET /api/billing/entitlement response)

/// User's subscription entitlement. Backend returns snake_case; we decode with convertFromSnakeCase.
struct Entitlement: Codable, Equatable {
    let plan: String       // "free" | "pro" | "team"
    let isActive: Bool
    let source: String     // "apple" | "stripe" | "none"
    let currentPeriodEnd: Date?

    enum CodingKeys: String, CodingKey {
        case plan
        case isActive = "is_active"
        case source
        case currentPeriodEnd = "current_period_end"
    }

    /// Default free entitlement when unauthenticated or for local fallback.
    static let free = Entitlement(
        plan: "free",
        isActive: false,
        source: "none",
        currentPeriodEnd: nil
    )
}

// MARK: - Apple verify request (POST /api/billing/apple/verify body)

struct AppleVerifyRequest: Encodable {
    let transactionId: String  // StoreKit 2 Transaction.id (string for JSON)
    let productId: String
}
