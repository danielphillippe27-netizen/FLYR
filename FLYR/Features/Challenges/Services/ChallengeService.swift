import Foundation
import Supabase
import UIKit

actor ChallengeService {
    static let shared = ChallengeService()

    private struct RollingLeaderboardParams: Encodable {
        let challengeSlug: String
        let window: String
        let limit: Int

        enum CodingKeys: String, CodingKey {
            case challengeSlug = "p_challenge_slug"
            case window = "p_window"
            case limit = "p_limit"
        }
    }

    private struct RollingParticipantCountParams: Encodable {
        let challengeSlug: String

        enum CodingKeys: String, CodingKey {
            case challengeSlug = "p_challenge_slug"
        }
    }

    private struct EvaluateBadgesRequest: Encodable {
        let userID: String
        let challengeID: String?
        let sessionID: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case challengeID = "challenge_id"
            case sessionID = "session_id"
        }
    }

    private struct ChallengeInsertPayload: Encodable {
        let creatorId: UUID
        let creatorName: String?
        let invitedEmail: String?
        let invitedPhone: String?
        let inviteToken: String?
        let baselineCount: Int
        let visibility: String
        let scoringMode: String
        let coverImagePath: String?
        let type: String
        let title: String
        let description: String
        let goalCount: Int
        let progressCount: Int
        let timeLimitHours: Int
        let status: String
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case creatorId = "creator_id"
            case creatorName = "creator_name"
            case invitedEmail = "invited_email"
            case invitedPhone = "invited_phone"
            case inviteToken = "invite_token"
            case baselineCount = "baseline_count"
            case visibility
            case scoringMode = "scoring_mode"
            case coverImagePath = "cover_image_path"
            case type
            case title
            case description
            case goalCount = "goal_count"
            case progressCount = "progress_count"
            case timeLimitHours = "time_limit_hours"
            case status
            case expiresAt = "expires_at"
        }
    }

    private struct ValidateInviteParams: Encodable {
        let token: String

        enum CodingKeys: String, CodingKey {
            case token = "p_token"
        }
    }

    private struct AcceptInviteParams: Encodable {
        let token: String
        let participantName: String?
        let participantEmail: String?
        let participantPhone: String?
        let baselineCount: Int

        enum CodingKeys: String, CodingKey {
            case token = "p_token"
            case participantName = "p_participant_name"
            case participantEmail = "p_participant_email"
            case participantPhone = "p_participant_phone"
            case baselineCount = "p_baseline_count"
        }
    }

    private struct JoinSearchableParams: Encodable {
        let challengeID: UUID
        let participantName: String?
        let baselineCount: Int

        enum CodingKeys: String, CodingKey {
            case challengeID = "p_challenge_id"
            case participantName = "p_participant_name"
            case baselineCount = "p_baseline_count"
        }
    }

    private struct SyncChallengeProgressParams: Encodable {
        let challengeID: UUID
        let progressCount: Int

        enum CodingKeys: String, CodingKey {
            case challengeID = "p_challenge_id"
            case progressCount = "p_progress_count"
        }
    }

    private var client: SupabaseClient {
        SupabaseManager.shared.client
    }

    private init() {}

    func fetchFirst30RollingLeaderboard(limit: Int = 50) async throws -> RollingChallengeLeaderboardSnapshot? {
        struct ActiveRollingChallengeRow: Decodable {
            let id: UUID
            let title: String
        }

        let challengeRows: [ActiveRollingChallengeRow] = try await client
            .from("challenge_templates")
            .select("id,title")
            .eq("slug", value: "first-30-days")
            .eq("scope", value: "global")
            .eq("type", value: "rolling_onboarding")
            .eq("status", value: "active")
            .limit(1)
            .execute()
            .value

        guard let challenge = challengeRows.first else {
            return nil
        }

        let participantCountResponse = try await client
            .rpc(
                "count_challenge_rolling_participants",
                params: RollingParticipantCountParams(challengeSlug: "first-30-days")
            )
            .execute()

        let participantCount = Self.decodeScalarInt(from: participantCountResponse.data) ?? 0

        let leaderboardResponse = try await client
            .rpc(
                "get_challenge_rolling_leaderboard",
                params: RollingLeaderboardParams(
                    challengeSlug: "first-30-days",
                    window: "challenge_window",
                    limit: limit
                )
            )
            .execute()

        let entries = try Self.decodeRollingLeaderboardEntries(from: leaderboardResponse.data)

        return RollingChallengeLeaderboardSnapshot(
            challengeID: challenge.id,
            challengeTitle: challenge.title,
            participantCount: max(participantCount, entries.count),
            entries: entries
        )
    }

    func evaluateBadges(for userID: UUID, challengeID: UUID? = nil, sessionID: UUID? = nil) async {
        do {
            let session = try await client.auth.session
            let supabaseURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
            guard let url = URL(string: "\(supabaseURL)/functions/v1/evaluate-badges") else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.httpBody = try JSONEncoder().encode(
                EvaluateBadgesRequest(
                    userID: userID.uuidString,
                    challengeID: challengeID?.uuidString,
                    sessionID: sessionID?.uuidString
                )
            )

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return
            }
        } catch {
            print("⚠️ [ChallengeService] Badge evaluation failed: \(error)")
        }
    }

    func fetchShareCardImage(
        userID: UUID,
        sessionID: UUID,
        challengeID: UUID? = nil
    ) async throws -> UIImage {
        guard var components = URLComponents(string: "\(requestBaseURL)/api/share-card") else {
            throw ChallengeRemoteAssetError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "user_id", value: userID.uuidString),
            URLQueryItem(name: "session_id", value: sessionID.uuidString),
            URLQueryItem(name: "challenge_id", value: challengeID?.uuidString)
        ].filter { $0.value?.isEmpty == false }

        guard let url = components.url else {
            throw ChallengeRemoteAssetError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ChallengeRemoteAssetError.requestFailed
        }
        guard let image = UIImage(data: data) else {
            throw ChallengeRemoteAssetError.invalidImage
        }
        return image
    }

    func warmShareCard(userID: UUID, sessionID: UUID, challengeID: UUID? = nil) async {
        do {
            _ = try await fetchShareCardImage(userID: userID, sessionID: sessionID, challengeID: challengeID)
        } catch {
            print("⚠️ [ChallengeService] Share card warmup failed: \(error)")
        }
    }

    func fetchLatestThirtyDayChallenge(for userID: UUID) async throws -> Challenge? {
        let response = try await client
            .from("challenges")
            .select()
            .eq("creator_id", value: userID)
            .eq("title", value: Challenge.thirtyDayTitle)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()

        let decoded = try JSONDecoder.supabaseDates.decode([Challenge].self, from: response.data)
        return decoded.first
    }

    func fetchChallenge(id: UUID) async throws -> Challenge? {
        try await fetchChallenges(ids: [id]).first
    }

    func fetchMyChallenges(for userID: UUID) async throws -> [Challenge] {
        async let createdTask = fetchChallenges(column: "creator_id", matching: userID)
        async let joinedMembershipsTask = fetchParticipantRows(for: userID)

        var combined: [UUID: Challenge] = [:]
        for challenge in try await createdTask {
            combined[challenge.id] = challenge
        }

        let joinedMemberships = try await joinedMembershipsTask
        let joinedChallengeIDs = joinedMemberships.map(\.challengeID)
        if !joinedChallengeIDs.isEmpty {
            for challenge in try await fetchChallenges(ids: joinedChallengeIDs) {
                combined[challenge.id] = challenge
            }
        }

        return combined.values.sorted { lhs, rhs in
            if lhs.status != rhs.status {
                if lhs.status == .active { return true }
                if rhs.status == .active { return false }
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// Active `searchable` challenges. Includes the current user's published challenges so they can confirm discovery;
    /// still omits challenges the user already joined as a participant when they are not the creator.
    func fetchSearchableChallenges(for userID: UUID) async throws -> [Challenge] {
        async let joinedMembershipsTask = fetchParticipantRows(for: userID)
        let response = try await client
            .from("challenges")
            .select()
            .eq("visibility", value: ChallengeVisibility.searchable.rawValue)
            .eq("status", value: ChallengeStatus.active.rawValue)
            .order("created_at", ascending: false)
            .execute()

        let joinedMemberships = try await joinedMembershipsTask
        let joinedChallengeIDs = Set(joinedMemberships.map(\.challengeID))
        return try JSONDecoder.supabaseDates.decode([Challenge].self, from: response.data)
            .filter { challenge in
                challenge.creatorId == userID || !joinedChallengeIDs.contains(challenge.id)
            }
    }

    func fetchParticipantStates(
        for userID: UUID,
        challengeIDs: [UUID]
    ) async throws -> [UUID: ChallengeParticipant] {
        guard !challengeIDs.isEmpty else { return [:] }

        let response = try await client
            .from("challenge_participants")
            .select()
            .eq("user_id", value: userID)
            .in("challenge_id", values: challengeIDs.map(\.uuidString))
            .execute()

        let rows = try JSONDecoder.supabaseDates.decode([ChallengeParticipant].self, from: response.data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.challengeID, $0) })
    }

    func fetchParticipants(for challengeID: UUID) async throws -> [ChallengeParticipant] {
        let response = try await client
            .from("challenge_participants")
            .select()
            .eq("challenge_id", value: challengeID)
            .order("joined_at", ascending: true)
            .execute()

        return try JSONDecoder.supabaseDates.decode([ChallengeParticipant].self, from: response.data)
    }

    func createThirtyDayChallenge(for userID: UUID, currentStreak: Int, creatorName: String?) async throws -> Challenge {
        let payload = ChallengeInsertPayload(
            creatorId: userID,
            creatorName: creatorName,
            invitedEmail: nil,
            invitedPhone: nil,
            inviteToken: nil,
            baselineCount: 0,
            visibility: ChallengeVisibility.privateInvite.rawValue,
            scoringMode: ChallengeScoringMode.reachGoal.rawValue,
            coverImagePath: nil,
            type: ChallengeType.custom.rawValue,
            title: Challenge.thirtyDayTitle,
            description: Challenge.thirtyDayDescription,
            goalCount: Challenge.thirtyDayGoal,
            progressCount: min(max(currentStreak, 0), Challenge.thirtyDayGoal),
            timeLimitHours: Challenge.thirtyDayTimeLimitHours,
            status: currentStreak >= Challenge.thirtyDayGoal
                ? ChallengeStatus.completed.rawValue
                : ChallengeStatus.active.rawValue,
            expiresAt: Calendar.current.date(byAdding: .day, value: Challenge.thirtyDayGoal, to: Date())
                ?? Date().addingTimeInterval(TimeInterval(Challenge.thirtyDayTimeLimitHours * 3600))
        )

        let response = try await client
            .from("challenges")
            .insert(payload)
            .select()
            .single()
            .execute()

        var created = try JSONDecoder.supabaseDates.decode(Challenge.self, from: response.data)
        if created.status == .completed && created.completedAt == nil {
            created = try await syncChallenge(
                created,
                participant: nil,
                stats: nil,
                actingUserID: userID,
                currentStreak: currentStreak
            )
        }
        return created
    }

    func createChallenge(
        for userID: UUID,
        creatorName: String?,
        draft: ChallengeDraft
    ) async throws -> Challenge {
        let coverPath: String?
        if let jpeg = draft.coverImageData {
            coverPath = try await uploadChallengeCover(userID: userID, data: jpeg)
        } else {
            coverPath = nil
        }

        let payload = ChallengeInsertPayload(
            creatorId: userID,
            creatorName: creatorName,
            invitedEmail: nil,
            invitedPhone: draft.visibility == .privateInvite ? draft.normalizedInvitePhoneDigits : nil,
            inviteToken: generateInviteToken(),
            baselineCount: 0,
            visibility: draft.visibility.rawValue,
            scoringMode: draft.scoringMode.rawValue,
            coverImagePath: coverPath,
            type: draft.type.rawValue,
            title: draft.normalizedTitle,
            description: draft.normalizedDescription ?? "",
            goalCount: max(draft.goalCount, 1),
            progressCount: 0,
            timeLimitHours: max(draft.durationDays, 1) * 24,
            status: ChallengeStatus.active.rawValue,
            expiresAt: nil
        )

        let response = try await client
            .from("challenges")
            .insert(payload)
            .select()
            .single()
            .execute()

        return try JSONDecoder.supabaseDates.decode(Challenge.self, from: response.data)
    }

    func validateInvite(token: String) async throws -> ChallengeInviteDetails {
        let response = try await client
            .rpc("validate_challenge_invite", params: ValidateInviteParams(token: token))
            .execute()

        let rows = try JSONDecoder.supabaseDates.decode([ChallengeInviteDetails].self, from: response.data)
        guard let invite = rows.first else {
            throw ChallengeInviteError.invalidInvite
        }
        return invite
    }

    func acceptInvite(
        token: String,
        participantName: String?,
        participantEmail: String?,
        participantPhone: String?,
        baselineCount: Int
    ) async throws -> Challenge {
        let response = try await client
            .rpc(
                "accept_challenge_invite",
                params: AcceptInviteParams(
                    token: token,
                    participantName: participantName,
                    participantEmail: participantEmail,
                    participantPhone: participantPhone,
                    baselineCount: baselineCount
                )
            )
            .execute()

        return try JSONDecoder.supabaseDates.decode(Challenge.self, from: response.data)
    }

    func joinSearchableChallenge(
        challengeID: UUID,
        participantName: String?,
        baselineCount: Int
    ) async throws -> Challenge {
        let response = try await client
            .rpc(
                "join_searchable_challenge",
                params: JoinSearchableParams(
                    challengeID: challengeID,
                    participantName: participantName,
                    baselineCount: baselineCount
                )
            )
            .execute()

        return try JSONDecoder.supabaseDates.decode(Challenge.self, from: response.data)
    }

    func syncChallenge(
        _ challenge: Challenge,
        participant: ChallengeParticipant?,
        stats: UserStats?,
        actingUserID: UUID,
        currentStreak: Int? = nil
    ) async throws -> Challenge {
        guard challenge.isThirtyDayChallenge || participant != nil else { return challenge }

        let normalizedProgress = progress(
            for: challenge,
            participant: participant,
            stats: stats,
            currentStreak: currentStreak
        )
        let response = try await client
            .rpc(
                "sync_challenge_progress",
                params: SyncChallengeProgressParams(
                    challengeID: challenge.id,
                    progressCount: normalizedProgress
                )
            )
            .execute()

        return try JSONDecoder.supabaseDates.decode(Challenge.self, from: response.data)
    }

    nonisolated func currentMetricCount(for type: ChallengeType, stats: UserStats?) -> Int {
        guard let stats else { return 0 }
        switch type {
        case .doorKnock:
            return stats.doors_knocked
        case .flyerDrop:
            return stats.flyers
        case .followUp:
            return stats.conversations
        case .leads:
            return stats.leads_created
        case .custom:
            return stats.day_streak
        }
    }

    nonisolated func inviteShareMessage(for challenge: Challenge) -> String {
        let acceptLink = inviteURL(for: challenge)?.absoluteString ?? "https://flyrpro.app/challenges"
        let sender = challenge.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderLine = (sender?.isEmpty == false)
            ? "\(sender!) opened a FLYR challenge."
            : "A new FLYR challenge is open."
        let durationLine: String
        if let timeLimitHours = challenge.timeLimitHours {
            let days = max(timeLimitHours / 24, 1)
            durationLine = days == 1 ? "1 day" : "\(days) days"
        } else {
            durationLine = "open invite"
        }

        return [
            senderLine,
            "\(challenge.title)",
            "\(challenge.goalCount) \(challenge.metricLabel) • \(durationLine)",
            "Join in FLYR: \(acceptLink)"
        ].joined(separator: "\n")
    }

    nonisolated func inviteURL(for challenge: Challenge) -> URL? {
        guard let token = challenge.inviteToken, !token.isEmpty else { return nil }
        var components = URLComponents(string: "https://flyrpro.app/challenges/join")
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    nonisolated private var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "FLYR_PRO_API_URL") as? String)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "https://flyrpro.app"
    }

    nonisolated private var requestBaseURL: String {
        guard let components = URLComponents(string: baseURL), components.host == "flyrpro.app" else {
            return baseURL
        }
        return "https://www.flyrpro.app"
    }

    private func fetchChallenges(column: String, matching userID: UUID) async throws -> [Challenge] {
        let response = try await client
            .from("challenges")
            .select()
            .eq(column, value: userID)
            .order("created_at", ascending: false)
            .execute()

        return try JSONDecoder.supabaseDates.decode([Challenge].self, from: response.data)
    }

    private func fetchChallenges(ids: [UUID]) async throws -> [Challenge] {
        guard !ids.isEmpty else { return [] }

        let response = try await client
            .from("challenges")
            .select()
            .in("id", values: ids.map(\.uuidString))
            .order("created_at", ascending: false)
            .execute()

        return try JSONDecoder.supabaseDates.decode([Challenge].self, from: response.data)
    }

    private func fetchParticipantRows(for userID: UUID) async throws -> [ChallengeParticipant] {
        let response = try await client
            .from("challenge_participants")
            .select()
            .eq("user_id", value: userID)
            .execute()

        return try JSONDecoder.supabaseDates.decode([ChallengeParticipant].self, from: response.data)
    }

    private func progress(
        for challenge: Challenge,
        participant: ChallengeParticipant?,
        stats: UserStats?,
        currentStreak: Int?
    ) -> Int {
        let baselineCount = participant?.baselineCount ?? challenge.baselineCount
        let fallbackProgress = participant?.progressCount ?? challenge.progressCount

        switch challenge.type {
        case .custom where challenge.isThirtyDayChallenge:
            let streak = currentStreak ?? stats?.day_streak ?? fallbackProgress
            return min(max(streak, 0), challenge.goalCount)
        case .doorKnock:
            return max((stats?.doors_knocked ?? fallbackProgress) - baselineCount, 0)
        case .flyerDrop:
            return max((stats?.flyers ?? fallbackProgress) - baselineCount, 0)
        case .followUp:
            return max((stats?.conversations ?? fallbackProgress) - baselineCount, 0)
        case .leads:
            return max((stats?.leads_created ?? fallbackProgress) - baselineCount, 0)
        case .custom:
            return max((currentStreak ?? stats?.day_streak ?? fallbackProgress) - baselineCount, 0)
        }
    }

    private func uploadChallengeCover(userID: UUID, data: Data) async throws -> String {
        let path = "\(userID.uuidString.lowercased())/challenge_\(UUID().uuidString.lowercased()).jpg"
        _ = try await client.storage
            .from("profile_images")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        return path
    }

    private func generateInviteToken() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func decodeScalarInt(from data: Data) -> Int? {
        if let intValue = try? JSONDecoder().decode(Int.self, from: data) {
            return intValue
        }
        if let stringValue = String(data: data, encoding: .utf8) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(trimmed)
        }
        return nil
    }

    private static func decodeRollingLeaderboardEntries(from data: Data) throws -> [RollingChallengeLeaderboardEntry] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { row in
            let userID = stringValue(from: row["user_id"])
            let displayName = stringValue(from: row["display_name"]) ?? "Member"
            let rank = intValue(from: row["rank"])
            let score = intValue(from: row["score"])

            guard let userID, let rank, let score else {
                return nil
            }

            let activeBadges = (row["active_badges"] as? [Any] ?? [])
                .compactMap { stringValue(from: $0) }
                .compactMap(ChallengeBadgeID.init(rawValue:))

            let latestSessionID = stringValue(from: row["latest_session_id"]).flatMap(UUID.init(uuidString:))

            return RollingChallengeLeaderboardEntry(
                id: userID,
                userID: userID,
                displayName: displayName,
                score: score,
                rank: rank,
                activeBadges: activeBadges,
                currentStreak: intValue(from: row["current_streak"]) ?? 0,
                accountabilityPosted: boolValue(from: row["accountability_posted"]) ?? false,
                latestSessionID: latestSessionID
            )
        }
    }

    private static func stringValue(from raw: Any?) -> String? {
        switch raw {
        case let value as String:
            return value
        case let value as CustomStringConvertible:
            return value.description
        default:
            return nil
        }
    }

    private static func intValue(from raw: Any?) -> Int? {
        switch raw {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value)
        default:
            return nil
        }
    }

    private static func boolValue(from raw: Any?) -> Bool? {
        switch raw {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return Bool(value)
        default:
            return nil
        }
    }
}

enum ChallengeInviteError: LocalizedError {
    case invalidInvite

    var errorDescription: String? {
        switch self {
        case .invalidInvite:
            return "This challenge invite is invalid or expired."
        }
    }
}

enum ChallengeRemoteAssetError: LocalizedError {
    case invalidURL
    case requestFailed
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid challenge asset URL."
        case .requestFailed:
            return "Couldn’t load the challenge asset."
        case .invalidImage:
            return "The challenge asset response was not a valid image."
        }
    }
}
