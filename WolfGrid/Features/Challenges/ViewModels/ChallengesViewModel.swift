import Foundation
import Combine

@MainActor
final class ChallengesViewModel: ObservableObject {
    @Published private(set) var stats: UserStats?
    @Published private(set) var myChallenges: [Challenge] = []
    @Published private(set) var participantStates: [UUID: ChallengeParticipant] = [:]
    @Published var isLoading = false
    @Published var isMutating = false
    @Published var errorMessage: String?

    private let statsService = StatsService.shared
    private let challengeService = ChallengeService.shared

    var additionalChallenges: [Challenge] {
        myChallenges
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
            HapticManager.success()
            return created
        } catch {
            errorMessage = "Couldn’t create that challenge right now."
            HapticManager.error()
            print("❌ [ChallengesViewModel] create failed: \(error)")
            return nil
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

            let fetchedStats = try await statsTask
            let fetchedMyChallenges = try await myChallengesTask
            let fetchedUserChallenges = fetchedMyChallenges.filter { !$0.isThirtyDayChallenge }

            stats = fetchedStats

            participantStates = try await challengeService.fetchParticipantStates(
                for: userID,
                challengeIDs: fetchedUserChallenges.map(\.id)
            )

            var syncedChallenges: [Challenge] = []
            for challenge in fetchedUserChallenges {
                let participant = participantStates[challenge.id]
                if challenge.status == .active, participant != nil {
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
