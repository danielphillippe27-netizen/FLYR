import Foundation
import Combine

@MainActor
final class ChallengeDetailViewModel: ObservableObject {
    @Published private(set) var challenge: Challenge
    @Published private(set) var participants: [ChallengeParticipant] = []
    @Published private(set) var currentParticipant: ChallengeParticipant?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let challengeService = ChallengeService.shared
    private let statsService = StatsService.shared

    init(challenge: Challenge) {
        self.challenge = challenge
    }

    var hostName: String {
        normalizedName(challenge.creatorName, fallback: "Host")
    }

    var rosterCount: Int {
        let participantUserIDs = Set(participants.map(\.userID))
        return participantUserIDs.contains(challenge.creatorId) ? participants.count : participants.count + 1
    }

    var displayedProgress: Int {
        guard let currentParticipant, !challenge.isThirtyDayChallenge else {
            return challenge.progressCount
        }
        return currentParticipant.progressCount
    }

    var displayedProgressRatio: Double {
        let total: Int
        switch challenge.scoringMode {
        case .mostInTimeframe:
            total = max(challenge.goalCount, displayedProgress, 1)
        case .reachGoal:
            total = max(challenge.goalCount, 1)
        }
        return min(max(Double(displayedProgress) / Double(total), 0), 1)
    }

    var leaderboardEntries: [ChallengeParticipant] {
        participants.sorted { lhs, rhs in
            if lhs.progressCount != rhs.progressCount {
                return lhs.progressCount > rhs.progressCount
            }
            return lhs.joinedAt < rhs.joinedAt
        }
    }

    var leader: ChallengeParticipant? {
        leaderboardEntries.first
    }

    func rank(for userID: UUID) -> Int? {
        leaderboardEntries.firstIndex(where: { $0.userID == userID }).map { $0 + 1 }
    }

    func load(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let fetchedChallenge = try await challengeService.fetchChallenge(id: challenge.id) ?? challenge
            var fetchedParticipants = try await challengeService.fetchParticipants(for: fetchedChallenge.id)
            var fetchedCurrentParticipant = fetchedParticipants.first(where: { $0.userID == userID })
            var hydratedChallenge = fetchedChallenge

            if hydratedChallenge.status == .active,
               hydratedChallenge.isThirtyDayChallenge || fetchedCurrentParticipant != nil {
                let stats = try await statsService.fetchUserStats(userID: userID)
                hydratedChallenge = try await challengeService.syncChallenge(
                    hydratedChallenge,
                    participant: fetchedCurrentParticipant,
                    stats: stats,
                    actingUserID: userID
                )
                fetchedParticipants = try await challengeService.fetchParticipants(for: hydratedChallenge.id)
                fetchedCurrentParticipant = fetchedParticipants.first(where: { $0.userID == userID })
            }

            challenge = hydratedChallenge
            participants = fetchedParticipants
            currentParticipant = fetchedCurrentParticipant
        } catch {
            errorMessage = "Couldn’t load this challenge right now."
            print("❌ [ChallengeDetailViewModel] load failed: \(error)")
        }
    }

    func displayName(for participant: ChallengeParticipant) -> String {
        normalizedName(participant.participantName, fallback: "Member")
    }

    private func normalizedName(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
