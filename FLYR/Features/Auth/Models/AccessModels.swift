import Foundation

// MARK: - Access state (GET /api/access/state)

struct AccessStateResponse: Codable {
    let userId: String?
    let role: String?
    let workspaceName: String?
    let workspaceId: String?
    /// When API omits this (e.g. returns workspace + subscription payload), treat as true if we have a workspace.
    let hasAccess: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case role, reason
        case userId = "user_id"
        case userIdCamel = "userId"
        case workspaceName = "name"
        case workspaceNameCamel = "workspaceName"
        case workspaceId = "workspace_id"
        case workspaceIdCamel = "workspaceId"
        case hasAccess = "has_access"
        case hasAccessCamel = "hasAccess"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
            ?? c.decodeIfPresent(String.self, forKey: .userIdCamel)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
            ?? c.decodeIfPresent(String.self, forKey: .workspaceNameCamel)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? c.decodeIfPresent(String.self, forKey: .workspaceIdCamel)
        hasAccess = try c.decodeIfPresent(Bool.self, forKey: .hasAccess)
            ?? c.decodeIfPresent(Bool.self, forKey: .hasAccessCamel)
            ?? true
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(userId, forKey: .userId)
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
    var useCase: OnboardingUseCase?
    var inviteEmails: [String]?
    var brokerage: String?
    var brokerageId: String?

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, workspaceName, industry, useCase
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
    let alreadyAccepted: Bool?
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
