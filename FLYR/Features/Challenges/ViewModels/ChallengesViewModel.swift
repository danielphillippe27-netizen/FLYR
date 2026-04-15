import Foundation
import Combine

@MainActor
final class ChallengesViewModel: ObservableObject {
    @Published private(set) var stats: UserStats?
    @Published private(set) var myChallenges: [Challenge] = []
    @Published private(set) var searchChallenges: [Challenge] = []
    @Published private(set) var participantStates: [UUID: ChallengeParticipant] = [:]
    @Published private(set) var rollingLeaderboard: RollingChallengeLeaderboardSnapshot?
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var isMutating = false
    @Published var errorMessage: String?

    private let statsService = StatsService.shared
    private let challengeService = ChallengeService.shared

    var currentStreak: Int {
        stats?.day_streak ?? 0
    }

    var bestStreak: Int {
        stats?.best_streak ?? 0
    }

    var primaryChallenge: Challenge? {
        myChallenges.first(where: \.isThirtyDayChallenge) ?? myChallenges.first
    }

    var thirtyDayChallenge: Challenge? {
        myChallenges.first(where: \.isThirtyDayChallenge)
    }

    var additionalChallenges: [Challenge] {
        myChallenges.filter { !$0.isThirtyDayChallenge }
    }

    var filteredSearchChallenges: [Challenge] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return searchChallenges }

        return searchChallenges.filter { challenge in
            challenge.title.localizedCaseInsensitiveContains(query)
                || (challenge.description?.localizedCaseInsensitiveContains(query) == true)
                || challenge.typeLabel.localizedCaseInsensitiveContains(query)
                || (challenge.creatorName?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    var displayedProgressDays: Int {
        min(max(thirtyDayChallenge?.progressCount ?? currentStreak, 0), Challenge.thirtyDayGoal)
    }

    var progressRatio: Double {
        Double(displayedProgressDays) / Double(Challenge.thirtyDayGoal)
    }

    var canStartNewChallenge: Bool {
        thirtyDayChallenge == nil || thirtyDayChallenge?.status != .active
    }

    var statusTitle: String {
        switch thirtyDayChallenge?.status {
        case .active:
            return "In Progress"
        case .completed:
            return "Completed"
        case .failed:
            return "Needs Restart"
        case .none:
            return "Ready"
        }
    }

    func load(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await reloadData(for: userID)
    }

    func refresh(for userID: UUID) async {
        errorMessage = nil
        await reloadData(for: userID)
    }

    func startChallenge(for userID: UUID, creatorName: String?) async {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            if stats == nil {
                stats = try await statsService.fetchUserStats(userID: userID)
            }

            let created = try await challengeService.createThirtyDayChallenge(
                for: userID,
                currentStreak: currentStreak,
                creatorName: creatorName
            )
            upsertMyChallenge(created)
            HapticManager.success()
        } catch {
            errorMessage = "Couldn’t start the challenge right now."
            HapticManager.error()
            print("❌ [ChallengesViewModel] start failed: \(error)")
        }
    }

    func createChallenge(for user: AppUser, draft: ChallengeDraft) async -> Challenge? {
        guard draft.isValid else {
            errorMessage = "Add a title, goal, and a friend’s phone number (10+ digits) before creating a private challenge."
            return nil
        }

        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            let created = try await challengeService.createChallenge(
                for: user.id,
                creatorName: user.displayName ?? fallbackName(from: user.email),
                draft: draft
            )
            upsertMyChallenge(created)
            if created.visibility == .searchable {
                searchChallenges.removeAll { $0.id == created.id }
                searchChallenges.insert(created, at: 0)
            }
            HapticManager.success()
            return created
        } catch {
            errorMessage = "Couldn’t create that challenge right now."
            HapticManager.error()
            print("❌ [ChallengesViewModel] create failed: \(error)")
            return nil
        }
    }

    func joinSearchableChallenge(_ challenge: Challenge, user: AppUser) async {
        isMutating = true
        errorMessage = nil
        defer { isMutating = false }

        do {
            if stats == nil {
                stats = try await statsService.fetchUserStats(userID: user.id)
            }

            let joined = try await challengeService.joinSearchableChallenge(
                challengeID: challenge.id,
                participantName: user.displayName ?? fallbackName(from: user.email),
                baselineCount: challengeService.currentMetricCount(for: challenge.type, stats: stats)
            )
            searchChallenges.removeAll { $0.id == challenge.id }
            upsertMyChallenge(joined)
            participantStates.merge(
                try await challengeService.fetchParticipantStates(for: user.id, challengeIDs: [joined.id])
            ) { _, new in new }
            HapticManager.success()
        } catch {
            errorMessage = "Couldn’t join that challenge right now."
            HapticManager.error()
            print("❌ [ChallengesViewModel] join failed: \(error)")
        }
    }

    func shareMessage(for challenge: Challenge) -> String {
        challengeService.inviteShareMessage(for: challenge)
    }

    func shareURL(for challenge: Challenge) -> URL? {
        challengeService.inviteURL(for: challenge)
    }

    func participantState(for challengeID: UUID) -> ChallengeParticipant? {
        participantStates[challengeID]
    }

    private func reloadData(for userID: UUID) async {
        do {
            async let statsTask = statsService.fetchUserStats(userID: userID)
            async let myChallengesTask = challengeService.fetchMyChallenges(for: userID)
            async let searchableTask = challengeService.fetchSearchableChallenges(for: userID)
            async let rollingLeaderboardTask = challengeService.fetchFirst30RollingLeaderboard()

            let fetchedStats = try await statsTask
            let fetchedMyChallenges = try await myChallengesTask
            let fetchedSearchable = try await searchableTask
            let fetchedRollingLeaderboard = try await rollingLeaderboardTask

            stats = fetchedStats
            searchChallenges = fetchedSearchable
            rollingLeaderboard = fetchedRollingLeaderboard

            participantStates = try await challengeService.fetchParticipantStates(
                for: userID,
                challengeIDs: fetchedMyChallenges.map(\.id)
            )

            var syncedChallenges: [Challenge] = []
            for challenge in fetchedMyChallenges {
                let participant = participantStates[challenge.id]
                if challenge.status == .active, challenge.isThirtyDayChallenge || participant != nil {
                    let synced = try await challengeService.syncChallenge(
                        challenge,
                        participant: participant,
                        stats: fetchedStats,
                        actingUserID: userID
                    )
                    syncedChallenges.append(synced)
                } else {
                    syncedChallenges.append(challenge)
                }
            }

            participantStates = try await challengeService.fetchParticipantStates(
                for: userID,
                challengeIDs: syncedChallenges.map(\.id)
            )

            myChallenges = syncedChallenges.sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    if lhs.status == .active { return true }
                    if rhs.status == .active { return false }
                }
                return lhs.createdAt > rhs.createdAt
            }
        } catch {
            errorMessage = "Couldn’t load your challenges right now."
            print("❌ [ChallengesViewModel] load failed: \(error)")
        }
    }

    private func upsertMyChallenge(_ challenge: Challenge) {
        if let index = myChallenges.firstIndex(where: { $0.id == challenge.id }) {
            myChallenges[index] = challenge
        } else {
            myChallenges.insert(challenge, at: 0)
        }

        myChallenges.sort { lhs, rhs in
            if lhs.status != rhs.status {
                if lhs.status == .active { return true }
                if rhs.status == .active { return false }
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func fallbackName(from email: String) -> String {
        email.split(separator: "@").first.map(String.init)?.capitalized ?? "Friend"
    }
}
