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

struct InviteValidateResponse: Decodable {
    let valid: Bool
    let workspaceName: String?
    let campaignId: String?
    let campaignTitle: String?
    let sessionId: String?
    let accessScope: String?
    let email: String?
    let role: String?

    enum CodingKeys: String, CodingKey {
        case valid, email, role
        case workspaceName = "workspace_name"
        case workspaceNameCamel = "workspaceName"
        case campaignId = "campaign_id"
        case campaignIdCamel = "campaignId"
        case campaignTitle = "campaign_title"
        case campaignTitleCamel = "campaignTitle"
        case sessionId = "session_id"
        case sessionIdCamel = "sessionId"
        case accessScope = "access_scope"
        case accessScopeCamel = "accessScope"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        valid = try c.decode(Bool.self, forKey: .valid)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
            ?? c.decodeIfPresent(String.self, forKey: .workspaceNameCamel)
        campaignId = try c.decodeIfPresent(String.self, forKey: .campaignId)
            ?? c.decodeIfPresent(String.self, forKey: .campaignIdCamel)
        campaignTitle = try c.decodeIfPresent(String.self, forKey: .campaignTitle)
            ?? c.decodeIfPresent(String.self, forKey: .campaignTitleCamel)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
            ?? c.decodeIfPresent(String.self, forKey: .sessionIdCamel)
        accessScope = try c.decodeIfPresent(String.self, forKey: .accessScope)
            ?? c.decodeIfPresent(String.self, forKey: .accessScopeCamel)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        role = try c.decodeIfPresent(String.self, forKey: .role)
    }
}

// MARK: - Invites accept (POST /api/invites/accept)

struct InviteAcceptRequest: Codable {
    let token: String
}

struct InviteAcceptResponse: Decodable {
    let success: Bool
    let workspaceId: String
    let campaignId: String?
    let sessionId: String?
    let accessScope: String?
    let redirect: String
    let alreadyAccepted: Bool?

    enum CodingKeys: String, CodingKey {
        case success, redirect
        case workspaceId = "workspace_id"
        case workspaceIdCamel = "workspaceId"
        case campaignId = "campaign_id"
        case campaignIdCamel = "campaignId"
        case sessionId = "session_id"
        case sessionIdCamel = "sessionId"
        case accessScope = "access_scope"
        case accessScopeCamel = "accessScope"
        case alreadyAccepted = "already_accepted"
        case alreadyAcceptedCamel = "alreadyAccepted"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? c.decode(String.self, forKey: .workspaceIdCamel)
        campaignId = try c.decodeIfPresent(String.self, forKey: .campaignId)
            ?? c.decodeIfPresent(String.self, forKey: .campaignIdCamel)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
            ?? c.decodeIfPresent(String.self, forKey: .sessionIdCamel)
        accessScope = try c.decodeIfPresent(String.self, forKey: .accessScope)
            ?? c.decodeIfPresent(String.self, forKey: .accessScopeCamel)
        redirect = try c.decode(String.self, forKey: .redirect)
        alreadyAccepted = try c.decodeIfPresent(Bool.self, forKey: .alreadyAccepted)
            ?? c.decodeIfPresent(Bool.self, forKey: .alreadyAcceptedCamel)
    }
}

// MARK: - Invites create (POST /api/invites/create)

struct InviteCreateRequest: Codable {
    let campaignId: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case campaignId = "campaignId"
        case sessionId = "sessionId"
    }
}

struct InviteCreateResponse: Decodable {
    let success: Bool
    let inviteURL: String
    let shareMessage: String
    let workspaceId: String?
    let workspaceName: String?
    let campaignId: String?
    let campaignTitle: String?
    let sessionId: String?
    let role: String?
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case success, role
        case inviteURL = "invite_url"
        case shareMessage = "share_message"
        case workspaceId = "workspace_id"
        case workspaceName = "workspace_name"
        case campaignId = "campaign_id"
        case campaignTitle = "campaign_title"
        case sessionId = "session_id"
        case expiresAt = "expires_at"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case inviteURL
        case inviteUrl
        case shareMessage
        case workspaceId
        case workspaceName
        case campaignId
        case campaignTitle
        case sessionId
        case expiresAt
        case success
        case role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alternateContainer = try decoder.container(keyedBy: AlternateCodingKeys.self)

        success = try container.decodeIfPresent(Bool.self, forKey: .success)
            ?? alternateContainer.decode(Bool.self, forKey: .success)
        inviteURL = try container.decodeIfPresent(String.self, forKey: .inviteURL)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .inviteURL)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .inviteUrl)
            ?? ""
        shareMessage = try container.decodeIfPresent(String.self, forKey: .shareMessage)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .shareMessage)
            ?? inviteURL
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .workspaceId)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .workspaceName)
        campaignId = try container.decodeIfPresent(String.self, forKey: .campaignId)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .campaignId)
        campaignTitle = try container.decodeIfPresent(String.self, forKey: .campaignTitle)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .campaignTitle)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .sessionId)
        role = try container.decodeIfPresent(String.self, forKey: .role)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .role)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? alternateContainer.decodeIfPresent(Date.self, forKey: .expiresAt)

        guard !inviteURL.isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.inviteURL,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing invite URL in invite create response."
                )
            )
        }
    }
}

// MARK: - Live session codes

struct LiveSessionCodeCreateResponse: Decodable {
    let success: Bool
    let code: String
    let expiresAt: Date?
    let workspaceId: String?
    let campaignId: String?
    let campaignTitle: String?
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case success, code
        case expiresAt = "expires_at"
        case workspaceId = "workspace_id"
        case campaignId = "campaign_id"
        case campaignTitle = "campaign_title"
        case sessionId = "session_id"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case success
        case code
        case expiresAt
        case workspaceId
        case campaignId
        case campaignTitle
        case sessionId
    }

    init(
        success: Bool,
        code: String,
        expiresAt: Date?,
        workspaceId: String?,
        campaignId: String?,
        campaignTitle: String?,
        sessionId: String?
    ) {
        self.success = success
        self.code = code
        self.expiresAt = expiresAt
        self.workspaceId = workspaceId
        self.campaignId = campaignId
        self.campaignTitle = campaignTitle
        self.sessionId = sessionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let alternateContainer = try decoder.container(keyedBy: AlternateCodingKeys.self)

        success = try container.decodeIfPresent(Bool.self, forKey: .success)
            ?? alternateContainer.decode(Bool.self, forKey: .success)
        code = try container.decodeIfPresent(String.self, forKey: .code)
            ?? alternateContainer.decode(String.self, forKey: .code)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? alternateContainer.decodeIfPresent(Date.self, forKey: .expiresAt)
        workspaceId = try container.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .workspaceId)
        campaignId = try container.decodeIfPresent(String.self, forKey: .campaignId)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .campaignId)
        campaignTitle = try container.decodeIfPresent(String.self, forKey: .campaignTitle)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .campaignTitle)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? alternateContainer.decodeIfPresent(String.self, forKey: .sessionId)
    }
}

struct LiveSessionCodeJoinResponse: Decodable {
    let success: Bool
    let workspaceId: String?
    let campaignId: String?
    let campaignTitle: String?
    let sessionId: String?
    let accessScope: String?
    let redirect: String

    enum CodingKeys: String, CodingKey {
        case success, redirect
        case workspaceId = "workspace_id"
        case workspaceIdCamel = "workspaceId"
        case campaignId = "campaign_id"
        case campaignIdCamel = "campaignId"
        case campaignTitle = "campaign_title"
        case campaignTitleCamel = "campaignTitle"
        case sessionId = "session_id"
        case sessionIdCamel = "sessionId"
        case accessScope = "access_scope"
        case accessScopeCamel = "accessScope"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        success = try c.decode(Bool.self, forKey: .success)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
            ?? c.decodeIfPresent(String.self, forKey: .workspaceIdCamel)
        campaignId = try c.decodeIfPresent(String.self, forKey: .campaignId)
            ?? c.decodeIfPresent(String.self, forKey: .campaignIdCamel)
        campaignTitle = try c.decodeIfPresent(String.self, forKey: .campaignTitle)
            ?? c.decodeIfPresent(String.self, forKey: .campaignTitleCamel)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
            ?? c.decodeIfPresent(String.self, forKey: .sessionIdCamel)
        accessScope = try c.decodeIfPresent(String.self, forKey: .accessScope)
            ?? c.decodeIfPresent(String.self, forKey: .accessScopeCamel)
        redirect = try c.decode(String.self, forKey: .redirect)
    }
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
