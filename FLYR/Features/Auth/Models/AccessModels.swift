import Foundation

// MARK: - Access state (GET /api/access/state)

struct AccessStateResponse: Codable {
    let role: String?
    let workspaceName: String?
    let workspaceId: String?
    /// When API omits this (e.g. returns workspace + subscription payload), treat as true if we have a workspace.
    let hasAccess: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case role, reason
        case workspaceName = "name"
        // Both possible snake_case and camelCase forms for resilience
        case workspaceId = "workspace_id"
        case hasAccess = "has_access"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        hasAccess = try c.decodeIfPresent(Bool.self, forKey: .hasAccess) ?? true
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(role, forKey: .role)
        try c.encodeIfPresent(workspaceName, forKey: .workspaceName)
        try c.encodeIfPresent(workspaceId, forKey: .workspaceId)
        try c.encode(hasAccess, forKey: .hasAccess)
        try c.encodeIfPresent(reason, forKey: .reason)
    }
}

// MARK: - Access redirect (GET /api/access/redirect)

struct AccessRedirectResponse: Codable {
    let redirect: String
    let path: String
}

// MARK: - Onboarding (POST /api/onboarding/complete)

enum OnboardingUseCase: String, Codable {
    case solo
    case team
}

struct OnboardingCompleteRequest: Codable {
    var firstName: String?
    var lastName: String?
    var workspaceName: String?
    var industry: String?
    var referralCode: String?
    var useCase: OnboardingUseCase?
    var inviteEmails: [String]?
    var brokerage: String?
    var brokerageId: String?

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, workspaceName, industry, referralCode, useCase
        case inviteEmails, brokerage, brokerageId
    }
}

struct OnboardingCompleteResponse: Codable {
    let success: Bool
    let redirect: String?
}

// MARK: - Brokerage search (GET /api/brokerages/search)

struct BrokerageSuggestion: Codable, Identifiable {
    let id: String
    let name: String
}

// MARK: - Invites validate (GET /api/invites/validate) – no auth

struct InviteValidateResponse: Codable {
    let valid: Bool
    let workspaceName: String?
    let email: String
    let role: String
}

// MARK: - Invites accept (POST /api/invites/accept)

struct InviteAcceptRequest: Codable {
    let token: String
}

struct InviteAcceptResponse: Codable {
    let success: Bool
    let workspaceId: String
    let redirect: String
}

// MARK: - Stripe checkout (POST /api/billing/stripe/checkout)

struct StripeCheckoutRequest: Codable {
    let plan: String?
    let currency: String?
    let priceId: String?

    enum CodingKeys: String, CodingKey {
        case plan, currency
        case priceId = "priceId"
    }
}

struct StripeCheckoutResponse: Codable {
    let url: String
}
