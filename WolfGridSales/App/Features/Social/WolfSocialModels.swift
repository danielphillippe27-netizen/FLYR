import Foundation

enum WolfSocialPlatform: String, Codable, CaseIterable, Identifiable, Hashable {
    case facebook, instagram, tiktok, youtube, linkedin
    var id: String { rawValue }
    var title: String {
        switch self { case .facebook: "Facebook"; case .instagram: "Instagram"; case .tiktok: "TikTok"; case .youtube: "YouTube"; case .linkedin: "LinkedIn" }
    }
    var systemImage: String {
        switch self { case .facebook: "person.2.fill"; case .instagram: "camera.fill"; case .tiktok: "play.rectangle.fill"; case .youtube: "play.tv.fill"; case .linkedin: "person.crop.square.fill" }
    }
}

struct WolfSocialWorkspace: Codable, Identifiable {
    let id: String
    var name: String
    let slug: String
}

struct WolfSocialConnection: Codable, Identifiable {
    let id: String
    let platform: WolfSocialPlatform
    let externalAccountID: String?
    let accountName: String?
    let accountAvatarURL: String?
    let accountType: String?
    let pageRole: String?
    let status: String
    let lastError: String?
    enum CodingKeys: String, CodingKey { case id, platform, status; case externalAccountID = "external_account_id"; case accountName = "account_name"; case accountAvatarURL = "account_avatar_url"; case accountType = "account_type"; case pageRole = "page_role"; case lastError = "last_error" }
}

struct WolfSocialProviderAvailability: Codable {
    let configured: Bool
    let message: String?
}

struct WolfSocialMediaAsset: Codable, Identifiable, Hashable {
    let id: String
    let originalName: String
    let mimeType: String
    let byteSize: Int64?
    let durationSeconds: Double?
    let previewURL: URL?
    let createdAt: String?
    enum CodingKeys: String, CodingKey { case id; case originalName = "original_name"; case mimeType = "mime_type"; case byteSize = "byte_size"; case durationSeconds = "duration_seconds"; case previewURL = "preview_url"; case createdAt = "created_at" }
}

struct WolfSocialPostTarget: Codable, Identifiable {
    let id: String
    let connectionID: String?
    let platform: WolfSocialPlatform
    let status: String
    let externalURL: String?
    let lastError: String?
    enum CodingKeys: String, CodingKey { case id, platform, status; case connectionID = "connection_id"; case externalURL = "external_url"; case lastError = "last_error" }
}

struct WolfSocialPost: Codable, Identifiable {
    let id: String
    let caption: String
    let title: String?
    let contentType: String
    let status: String
    let scheduledFor: String?
    let createdAt: String?
    let socialPostTargets: [WolfSocialPostTarget]?
    enum CodingKeys: String, CodingKey { case id, caption, title, status; case contentType = "content_type"; case scheduledFor = "scheduled_for"; case createdAt = "created_at"; case socialPostTargets = "social_post_targets" }
}

struct WolfSocialContact: Codable, Identifiable {
    let id: String
    let displayName: String?
    let username: String?
    let salesLeadID: String?
    enum CodingKeys: String, CodingKey { case id, username; case displayName = "display_name"; case salesLeadID = "sales_lead_id" }
}

struct WolfSocialInteraction: Codable, Identifiable {
    let id: String
    let body: String
    let direction: String
    let status: String?
    let occurredAt: String
    let senderName: String?
    enum CodingKeys: String, CodingKey { case id, body, direction, status; case occurredAt = "occurred_at"; case senderName = "sender_name" }
}

struct WolfSocialThread: Codable, Identifiable {
    let id: String
    let platform: WolfSocialPlatform
    let kind: String
    let subject: String?
    let needsReply: Bool
    let socialContacts: WolfSocialContact?
    let socialInteractions: [WolfSocialInteraction]?
    enum CodingKeys: String, CodingKey { case id, platform, kind, subject; case needsReply = "needs_reply"; case socialContacts = "social_contacts"; case socialInteractions = "social_interactions" }
}

struct WolfSocialAnalytics: Codable {
    let periodDays: Int?
    let totals: [String: Double]
    let posts: PostTotals?
    struct PostTotals: Codable { let total: Int; let published: Int; let scheduled: Int; let failed: Int }
}

struct WolfSocialTikTokCreatorInfo: Codable {
    let username: String?
    let nickname: String?
    let avatarURL: String?
    let privacyLevelOptions: [String]
    let commentsDisabled: Bool
    let duetDisabled: Bool
    let stitchDisabled: Bool
    let maxVideoDurationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case username, nickname, privacyLevelOptions, commentsDisabled, duetDisabled, stitchDisabled, maxVideoDurationSeconds
        case avatarURL = "avatarUrl"
    }
}

struct WolfSocialTargetSettings: Codable {
    var privacyLevel: String?
    var allowComments: Bool?
    var allowDuet: Bool?
    var allowStitch: Bool?
    var musicUsageConfirmed: Bool?
    var explicitConsent: Bool?
    var commercialContent: Bool?
    var yourBrand: Bool?
    var brandContent: Bool?
    var aiGeneratedContent: Bool?
    var privacyStatus: String?
    var madeForKids: Bool?
    var visibility: String?
    var disableReshare: Bool?

    init(
        privacyLevel: String? = nil,
        allowComments: Bool? = nil,
        allowDuet: Bool? = nil,
        allowStitch: Bool? = nil,
        musicUsageConfirmed: Bool? = nil,
        explicitConsent: Bool? = nil,
        commercialContent: Bool? = nil,
        yourBrand: Bool? = nil,
        brandContent: Bool? = nil,
        aiGeneratedContent: Bool? = nil,
        privacyStatus: String? = nil,
        madeForKids: Bool? = nil,
        visibility: String? = nil,
        disableReshare: Bool? = nil
    ) {
        self.privacyLevel = privacyLevel
        self.allowComments = allowComments
        self.allowDuet = allowDuet
        self.allowStitch = allowStitch
        self.musicUsageConfirmed = musicUsageConfirmed
        self.explicitConsent = explicitConsent
        self.commercialContent = commercialContent
        self.yourBrand = yourBrand
        self.brandContent = brandContent
        self.aiGeneratedContent = aiGeneratedContent
        self.privacyStatus = privacyStatus
        self.madeForKids = madeForKids
        self.visibility = visibility
        self.disableReshare = disableReshare
    }
}

struct WolfSocialPostTargetRequest: Codable {
    let connectionId: String
    let format: String
    let caption: String
    let title: String?
    let settings: WolfSocialTargetSettings
}

struct WolfSocialPostRequest: Codable {
    let socialWorkspaceId: String
    let assetIds: [String]
    let mode: String
    let scheduledFor: String?
    let timezone: String
    let caption: String
    let title: String?
    let contentType: String
    let targets: [WolfSocialPostTargetRequest]
}

extension Notification.Name {
    static let wolfSocialOAuthCompleted = Notification.Name("wolfSocialOAuthCompleted")
}
