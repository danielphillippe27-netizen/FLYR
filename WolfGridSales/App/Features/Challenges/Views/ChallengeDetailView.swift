import SwiftUI

struct ChallengeDetailView: View {
    let user: AppUser

    @StateObject private var viewModel: ChallengeDetailViewModel

    init(challenge: Challenge, user: AppUser) {
        self.user = user
        _viewModel = StateObject(wrappedValue: ChallengeDetailViewModel(challenge: challenge))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                progressCard
                membersCard
                leaderboardCard
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(viewModel.challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.challenge.id) {
            await viewModel.load(for: user.id)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.challenge.title)
                        .font(.flyrTitle2Bold)
                        .foregroundStyle(Color.text)

                    Text(viewModel.challenge.description?.isEmpty == false
                         ? viewModel.challenge.description!
                         : "Track who is ahead, who joined, and how much room is left on the clock.")
                        .font(.flyrBody)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(viewModel.challenge.status.rawValue.capitalized)
                    .font(.flyrCaption.weight(.bold))
                    .foregroundStyle(viewModel.challenge.status == .completed ? Color.success : Color.flyrPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(
                                viewModel.challenge.status == .completed
                                    ? Color.success.opacity(0.12)
                                    : Color.flyrPrimary.opacity(0.12)
                            )
                    )
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    summaryPill(text: viewModel.challenge.visibilityLabel, icon: viewModel.challenge.visibility == .privateInvite ? "lock.fill" : "globe")
                    summaryPill(text: "\(viewModel.challenge.goalCount) \(viewModel.challenge.metricLabel)", icon: "scope")
                }

                HStack(spacing: 10) {
                    summaryPill(text: "\(viewModel.rosterCount) members", icon: "person.3.fill")
                    summaryPill(text: timeRemainingLabel, icon: "calendar")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.warning)
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Progress")
                    .font(.flyrHeadline)
                    .foregroundStyle(Color.text)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(progressHeadline)
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.text)
                    Spacer()
                    Text("\(viewModel.displayedProgress)/\(viewModel.challenge.goalCount)")
                        .font(.flyrCaption.weight(.bold))
                        .foregroundStyle(Color.muted)
                        .monospacedDigit()
                }

                ProgressView(value: viewModel.displayedProgressRatio)
                    .tint(viewModel.challenge.status == .completed ? .success : .flyrPrimary)

                Text(progressSubheadline)
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                statCard(title: "Leader", value: leaderValue, subtitle: leaderSubtitle)
                statCard(title: "Your Rank", value: userRankValue, subtitle: userRankSubtitle)
                statCard(title: "Mode", value: modeLabel, subtitle: "How this race is scored")
                statCard(title: "Window", value: timeRemainingLabel, subtitle: "Time left to finish")
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Members")
                .font(.flyrHeadline)
                .foregroundStyle(Color.text)

            memberRow(
                name: viewModel.hostName,
                subtitle: "Challenge host",
                progress: nil,
                isCurrentUser: viewModel.challenge.creatorId == user.id,
                badgeText: "Host"
            )

            if viewModel.participants.isEmpty {
                Text("No one has joined yet. Once challengers join, their progress will show up here.")
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.participants) { participant in
                        memberRow(
                            name: viewModel.displayName(for: participant),
                            subtitle: participant.acceptedAt == nil ? "Invited member" : "Joined \(participant.joinedAt.formatted(date: .abbreviated, time: .omitted))",
                            progress: participant.progressCount,
                            isCurrentUser: participant.userID == user.id,
                            badgeText: participant.userID == viewModel.challenge.creatorId ? "Host" : nil
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Leaderboard")
                .font(.flyrHeadline)
                .foregroundStyle(Color.text)

            if viewModel.leaderboardEntries.isEmpty {
                Text("Waiting for the first score to land.")
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(viewModel.leaderboardEntries.enumerated()), id: \.element.id) { index, participant in
                        leaderboardRow(participant: participant, rank: index + 1)
                    }
                }
            }
        }
        .padding(20)
        .background(cardBackground)
    }

    private func summaryPill(text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.flyrCaption)
        .foregroundStyle(Color.text)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.bg)
        )
    }

    private func statCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.flyrCaption.weight(.bold))
                .foregroundStyle(Color.muted)
            Text(value)
                .font(.flyrSubheadline.weight(.semibold))
                .foregroundStyle(Color.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.flyrCaption)
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.bg)
        )
    }

    private func memberRow(
        name: String,
        subtitle: String,
        progress: Int?,
        isCurrentUser: Bool,
        badgeText: String?
    ) -> some View {
        HStack(spacing: 12) {
            ProfileAvatarView(avatarUrl: nil, name: name, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.text)
                        .lineLimit(1)

                    if isCurrentUser {
                        tag("You", tint: .white, background: Color.flyrPrimary)
                    }

                    if let badgeText {
                        tag(badgeText, tint: Color.text, background: Color.bg)
                    }
                }

                Text(subtitle)
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }

            Spacer()

            if let progress {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(progress)")
                        .font(.flyrHeadline.weight(.bold))
                        .foregroundStyle(Color.flyrPrimary)
                        .monospacedDigit()
                    Text(viewModel.challenge.metricLabel)
                        .font(.flyrCaption)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.bg)
        )
    }

    private func leaderboardRow(participant: ChallengeParticipant, rank: Int) -> some View {
        HStack(spacing: 12) {
            Group {
                if rank == 1 {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color.yellow)
                } else {
                    Text("#\(rank)")
                        .foregroundStyle(Color.muted)
                        .monospacedDigit()
                }
            }
            .font(.flyrFootnote.weight(.bold))
            .frame(width: 30)

            ProfileAvatarView(avatarUrl: nil, name: viewModel.displayName(for: participant), size: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewModel.displayName(for: participant))
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.text)
                    if participant.userID == user.id {
                        tag("You", tint: .white, background: Color.flyrPrimary)
                    }
                }

                Text(rank == 1 ? "Currently leading" : "Ranked #\(rank)")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(participant.progressCount)")
                    .font(.flyrHeadline.weight(.bold))
                    .foregroundStyle(Color.flyrPrimary)
                    .monospacedDigit()
                Text(viewModel.challenge.metricLabel)
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(rank == 1 ? Color.flyrPrimary.opacity(0.08) : Color.bg)
        )
    }

    private func tag(_ text: String, tint: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
    }

    private var progressHeadline: String {
        if viewModel.currentParticipant != nil {
            return "Your progress"
        }
        if viewModel.challenge.hasParticipants {
            return "Leaderboard pace"
        }
        return "Waiting for the first joiner"
    }

    private var progressSubheadline: String {
        if let currentParticipant = viewModel.currentParticipant {
            if let rank = viewModel.rank(for: currentParticipant.userID) {
                return rank == 1
                    ? "You’re in first right now."
                    : "You’re currently ranked #\(rank)."
            }
            return "Your progress updates after new activity syncs."
        }

        if let leader = viewModel.leader {
            return "\(viewModel.displayName(for: leader)) is setting the pace at \(leader.progressCount)."
        }

        return "Open the invite or send it again so someone can join this challenge."
    }

    private var leaderValue: String {
        guard let leader = viewModel.leader else { return "None yet" }
        return "\(leader.progressCount)"
    }

    private var leaderSubtitle: String {
        guard let leader = viewModel.leader else { return "No member progress yet" }
        return viewModel.displayName(for: leader)
    }

    private var userRankValue: String {
        guard let rank = viewModel.rank(for: user.id) else {
            return viewModel.challenge.creatorId == user.id ? "Host" : "Not joined"
        }
        return "#\(rank)"
    }

    private var userRankSubtitle: String {
        if viewModel.rank(for: user.id) != nil {
            return "Based on current challenge progress"
        }
        return viewModel.challenge.creatorId == user.id
            ? "You created this challenge"
            : "Join or refresh to enter the board"
    }

    private var modeLabel: String {
        switch viewModel.challenge.scoringMode {
        case .reachGoal:
            return "First to goal"
        case .mostInTimeframe:
            return "Most by deadline"
        }
    }

    private var timeRemainingLabel: String {
        guard let expiresAt = viewModel.challenge.expiresAt else {
            if let hours = viewModel.challenge.timeLimitHours {
                let days = max(hours / 24, 1)
                return days == 1 ? "1 day" : "\(days) days"
            }
            return "No limit"
        }

        let calendar = Calendar.current
        let days = max(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: Date()),
                to: calendar.startOfDay(for: expiresAt)
            ).day ?? 0,
            0
        )
        return days == 0 ? "Ends today" : "\(days)d left"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.border.opacity(0.35), lineWidth: 1)
            )
    }
}

