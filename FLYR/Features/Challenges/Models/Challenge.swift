import Foundation

enum ChallengeType: String, Codable, CaseIterable {
    case doorKnock = "door_knock"
    case flyerDrop = "flyer_drop"
    case followUp = "follow_up"
    case leads
    case custom

    var title: String {
        switch self {
        case .doorKnock:
            return "Doors"
        case .flyerDrop:
            return "Flyers"
        case .followUp:
            return "Conversations"
        case .leads:
            return "Leads"
        case .custom:
            return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .doorKnock:
            return "door.left.hand.closed"
        case .flyerDrop:
            return "paperplane.fill"
        case .followUp:
            return "bubble.left.and.bubble.right.fill"
        case .leads:
            return "person.crop.circle.badge.plus"
        case .custom:
            return "flag.fill"
        }
    }

    /// Types shown when creating a user-defined challenge (not the 30-day system challenge).
    static var userSelectableCases: [ChallengeType] {
        [.doorKnock, .followUp, .leads]
    }
}

enum ChallengeStatus: String, Codable {
    case active
    case completed
    case failed
}

enum ChallengeVisibility: String, Codable, CaseIterable {
    case privateInvite = "private"
    case searchable

    var title: String {
        switch self {
        case .privateInvite:
            return "Private"
        case .searchable:
            return "Public"
        }
    }

    var subtitle: String {
        switch self {
        case .privateInvite:
            return "Send it directly to a friend by phone."
        case .searchable:
            return "Let people in the app find it and join in."
        }
    }
}

/// How the challenge is scored when time runs out or the goal is reached.
enum ChallengeScoringMode: String, Codable, CaseIterable {
    case reachGoal = "reach_goal"
    case mostInTimeframe = "most_in_timeframe"

    var title: String {
        switch self {
        case .reachGoal:
            return "Reach the goal"
        case .mostInTimeframe:
            return "Most in timeframe"
        }
    }

    var subtitle: String {
        switch self {
        case .reachGoal:
            return "Finish when someone hits the target count (e.g. 100 doors)."
        case .mostInTimeframe:
            return "Whoever has the highest count when time is up wins."
        }
    }
}

enum ChallengeBadgeID: String, Codable, CaseIterable {
    case streak
    case topWeek = "top_week"
    case mostActive24h = "most_active_24h"
    case milestone10 = "milestone_10"
    case milestone25 = "milestone_25"
    case milestone50 = "milestone_50"

    var emoji: String {
        switch self {
        case .streak:
            return "🔥"
        case .topWeek:
            return "👑"
        case .mostActive24h:
            return "⚡"
        case .milestone10:
            return "🎯"
        case .milestone25:
            return "🏠"
        case .milestone50:
            return "🚀"
        }
    }
}

extension String {
    /// Digits-only phone for comparison and storage (min meaningful length enforced at validation).
    var challengePhoneDigits: String {
        filter(\.isNumber)
    }
}

struct Challenge: Codable, Identifiable, Hashable {
    static let thirtyDayTitle = "30 Day Challenge"
    static let thirtyDayDescription = "Knock for 30 straight days. This challenge uses your current knocking streak as progress."
    static let thirtyDayGoal = 30
    static let thirtyDayTimeLimitHours = 24 * 30

    let id: UUID
    let creatorId: UUID
    let participantId: UUID?
    let creatorName: String?
    let participantName: String?
    let invitedEmail: String?
    let invitedPhone: String?
    let inviteToken: String?
    let baselineCount: Int
    let type: ChallengeType
    let title: String
    let description: String?
    let goalCount: Int
    let progressCount: Int
    let participantCount: Int
    let timeLimitHours: Int?
    let visibility: ChallengeVisibility
    let scoringMode: ChallengeScoringMode
    let coverImagePath: String?
    let status: ChallengeStatus
    let createdAt: Date
    let expiresAt: Date?
    let completedAt: Date?
    let acceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case creatorId = "creator_id"
        case participantId = "participant_id"
        case creatorName = "creator_name"
        case participantName = "participant_name"
        case invitedEmail = "invited_email"
        case invitedPhone = "invited_phone"
        case inviteToken = "invite_token"
        case baselineCount = "baseline_count"
        case type
        case title
        case description
        case goalCount = "goal_count"
        case progressCount = "progress_count"
        case participantCount = "participant_count"
        case timeLimitHours = "time_limit_hours"
        case visibility
        case scoringMode = "scoring_mode"
        case coverImagePath = "cover_image_path"
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case completedAt = "completed_at"
        case acceptedAt = "accepted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        creatorId = try container.decode(UUID.self, forKey: .creatorId)
        participantId = try container.decodeIfPresent(UUID.self, forKey: .participantId)
        creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
        participantName = try container.decodeIfPresent(String.self, forKey: .participantName)
        invitedEmail = try container.decodeIfPresent(String.self, forKey: .invitedEmail)
        invitedPhone = try container.decodeIfPresent(String.self, forKey: .invitedPhone)
        inviteToken = try container.decodeIfPresent(String.self, forKey: .inviteToken)
        baselineCount = try container.decodeIfPresent(Int.self, forKey: .baselineCount) ?? 0
        type = try container.decode(ChallengeType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        goalCount = try container.decode(Int.self, forKey: .goalCount)
        progressCount = try container.decode(Int.self, forKey: .progressCount)
        participantCount = try container.decodeIfPresent(Int.self, forKey: .participantCount)
            ?? (participantId == nil ? 0 : 1)
        timeLimitHours = try container.decodeIfPresent(Int.self, forKey: .timeLimitHours)
        visibility = try container.decodeIfPresent(ChallengeVisibility.self, forKey: .visibility) ?? .privateInvite
        scoringMode = try container.decodeIfPresent(ChallengeScoringMode.self, forKey: .scoringMode) ?? .reachGoal
        coverImagePath = try container.decodeIfPresent(String.self, forKey: .coverImagePath)
        status = try container.decode(ChallengeStatus.self, forKey: .status)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt)
    }
}

struct ChallengeParticipant: Codable, Identifiable {
    let id: UUID
    let challengeID: UUID
    let userID: UUID
    let participantName: String?
    let baselineCount: Int
    let progressCount: Int
    let joinedAt: Date
    let acceptedAt: Date?
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case userID = "user_id"
        case participantName = "participant_name"
        case baselineCount = "baseline_count"
        case progressCount = "progress_count"
        case joinedAt = "joined_at"
        case acceptedAt = "accepted_at"
        case completedAt = "completed_at"
    }
}

struct ChallengeDraft {
    var title: String = ""
    var description: String = ""
    var type: ChallengeType = .doorKnock
    var scoringMode: ChallengeScoringMode = .reachGoal
    var goalCount: Int = 100
    var durationDays: Int = 7
    var visibility: ChallengeVisibility = .privateInvite
    var invitePhone: String = ""
    var coverImageData: Data?

    var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDescription: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedInvitePhoneDigits: String? {
        let digits = invitePhone.challengePhoneDigits
        guard digits.count >= 10 else { return nil }
        return digits
    }

    var isValid: Bool {
        guard !normalizedTitle.isEmpty, goalCount > 0, durationDays > 0 else { return false }
        if visibility == .privateInvite {
            return normalizedInvitePhoneDigits != nil
        }
        return true
    }
}

struct ChallengeInviteDetails: Codable {
    let valid: Bool
    let challengeID: UUID
    let title: String
    let description: String?
    let creatorName: String?
    let invitedEmail: String?
    let invitedPhone: String?
    let visibility: ChallengeVisibility
    let type: ChallengeType
    let goalCount: Int
    let timeLimitHours: Int?
    let scoringMode: ChallengeScoringMode?
    let coverImagePath: String?
    let expiresAt: Date?
    let participantCount: Int
    let alreadyJoined: Bool

    enum CodingKeys: String, CodingKey {
        case valid
        case challengeID = "challenge_id"
        case title
        case description
        case creatorName = "creator_name"
        case invitedEmail = "invited_email"
        case invitedPhone = "invited_phone"
        case visibility
        case type
        case goalCount = "goal_count"
        case timeLimitHours = "time_limit_hours"
        case scoringMode = "scoring_mode"
        case coverImagePath = "cover_image_path"
        case expiresAt = "expires_at"
        case participantCount = "participant_count"
        case alreadyJoined = "already_joined"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        valid = try container.decode(Bool.self, forKey: .valid)
        challengeID = try container.decode(UUID.self, forKey: .challengeID)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        creatorName = try container.decodeIfPresent(String.self, forKey: .creatorName)
        invitedEmail = try container.decodeIfPresent(String.self, forKey: .invitedEmail)
        invitedPhone = try container.decodeIfPresent(String.self, forKey: .invitedPhone)
        visibility = try container.decode(ChallengeVisibility.self, forKey: .visibility)
        type = try container.decode(ChallengeType.self, forKey: .type)
        goalCount = try container.decode(Int.self, forKey: .goalCount)
        timeLimitHours = try container.decodeIfPresent(Int.self, forKey: .timeLimitHours)
        scoringMode = try container.decodeIfPresent(ChallengeScoringMode.self, forKey: .scoringMode)
        coverImagePath = try container.decodeIfPresent(String.self, forKey: .coverImagePath)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        participantCount = try container.decodeIfPresent(Int.self, forKey: .participantCount) ?? 0
        alreadyJoined = try container.decode(Bool.self, forKey: .alreadyJoined)
    }
}

struct RollingChallengeLeaderboardEntry: Identifiable, Equatable {
    let id: String
    let userID: String
    let displayName: String
    let score: Int
    let rank: Int
    let activeBadges: [ChallengeBadgeID]
    let currentStreak: Int
    let accountabilityPosted: Bool
    let latestSessionID: UUID?

    var badgesInlineText: String {
        activeBadges.map(\.emoji).joined(separator: " ")
    }
}

struct RollingChallengeLeaderboardSnapshot: Equatable {
    let challengeID: UUID
    let challengeTitle: String
    let participantCount: Int
    let entries: [RollingChallengeLeaderboardEntry]
}

extension Challenge {
    var normalizedProgress: Double {
        guard goalCount > 0 else { return 0 }
        return min(max(Double(progressCount) / Double(goalCount), 0), 1)
    }

    /// Progress bar total so the bar can grow past 100% in “most in timeframe” mode.
    var progressBarTotal: Int {
        switch scoringMode {
        case .mostInTimeframe:
            return max(goalCount, progressCount, 1)
        case .reachGoal:
            return max(goalCount, 1)
        }
    }

    var normalizedProgressForBar: Double {
        min(max(Double(progressCount) / Double(progressBarTotal), 0), 1)
    }

    var isThirtyDayChallenge: Bool {
        title == Self.thirtyDayTitle && goalCount == Self.thirtyDayGoal
    }

    var hasParticipants: Bool {
        participantCount > 0
    }

    var metricLabel: String {
        switch type {
        case .doorKnock:
            return "doors knocked"
        case .flyerDrop:
            return "flyers dropped"
        case .followUp:
            return "conversations"
        case .leads:
            return "leads"
        case .custom:
            return isThirtyDayChallenge ? "streak days" : "progress"
        }
    }

    var typeLabel: String {
        isThirtyDayChallenge ? "Streak" : type.title
    }

    var visibilityLabel: String {
        switch visibility {
        case .privateInvite:
            return "Private"
        case .searchable:
            return "Public"
        }
    }

    func isCreated(by userID: UUID) -> Bool {
        creatorId == userID
    }

    func isJoined(by userID: UUID) -> Bool {
        participantId == userID
    }
}
