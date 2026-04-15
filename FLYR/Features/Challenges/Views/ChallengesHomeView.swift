import SwiftUI
import PhotosUI
import Supabase
import UIKit
import LinkPresentation

private enum ChallengeBoardTab: String, CaseIterable {
    case mine = "My Challenges"
    case search = "Search Challenges"
}

struct ChallengesHomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = ChallengesViewModel()
    @StateObject private var auth = AuthManager.shared
    @State private var selectedTab: ChallengeBoardTab = .mine
    @State private var showCreateSheet = false
    @State private var shareStatusMessage: String?
    @State private var selectedChallenge: Challenge?

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()

            if let user = auth.user {
                ScrollView {
                    VStack(spacing: 18) {
                        tabPicker

                        switch selectedTab {
                        case .mine:
                            myChallengesContent(user: user)
                        case .search:
                            searchChallengesContent(user: user)
                        }

                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(errorMessage)
                        }

                        if let shareStatusMessage {
                            infoBanner(shareStatusMessage)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .refreshable {
                    await viewModel.refresh(for: user.id)
                    HapticManager.rigid()
                }
                .task(id: user.id) {
                    await viewModel.load(for: user.id)
                }
            } else {
                signedOutState
                    .padding(24)
            }
        }
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.bg, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbar {
            if auth.user != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 34, height: 34)
                            .background(Color.flyrPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Create challenge")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            if let user = auth.user {
                ChallengeCreateSheet(
                    user: user,
                    isSaving: viewModel.isMutating,
                    onCreate: { draft in
                        let created = await viewModel.createChallenge(for: user, draft: draft)
                        if created != nil {
                            showCreateSheet = false
                        }
                        if let created, created.inviteToken?.isEmpty == false {
                            let items = ChallengeShareComposer.activityItems(
                                for: created,
                                message: viewModel.shareMessage(for: created),
                                url: viewModel.shareURL(for: created)
                            )
                            DispatchQueue.main.async {
                                if !ShareCardGenerator.presentActivityShare(activityItems: items) {
                                    showShareStatus(ShareCardGenerator.shareSheetUnavailableUserMessage)
                                }
                            }
                        }
                    }
                )
            }
        }
        .navigationDestination(item: $selectedChallenge) { challenge in
            if let user = auth.user {
                ChallengeDetailView(challenge: challenge, user: user)
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 10) {
            ForEach(ChallengeBoardTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    HapticManager.light()
                } label: {
                    Text(tab.rawValue)
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selectedTab == tab ? Color.flyrPrimary : Color.bgSecondary)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.bgSecondary)
        )
    }

    @ViewBuilder
    private func myChallengesContent(user: AppUser) -> some View {
        heroCard(user: user)
        if let rolling = viewModel.rollingLeaderboard {
            challengeLeaderboardCard(rolling, currentUserID: user.id)
        }
        privateChallengesCard(user: user)
        actionCard(user: user)
    }

    @ViewBuilder
    private func searchChallengesContent(user: AppUser) -> some View {
        searchHeader

        if viewModel.filteredSearchChallenges.isEmpty {
            emptySearchState
        } else {
            VStack(spacing: 14) {
                ForEach(viewModel.filteredSearchChallenges) { challenge in
                    searchableChallengeCard(challenge, user: user) {
                        selectedChallenge = challenge
                    }
                }
            }
        }
    }

    private func heroCard(user: AppUser) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return ZStack(alignment: .topLeading) {
            cardShape
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.96, green: 0.27, blue: 0.18), Color(red: 0.59, green: 0.09, blue: 0.10)]
                            : [Color(red: 1.0, green: 0.53, blue: 0.31), Color(red: 0.93, green: 0.24, blue: 0.19)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16))
                .frame(width: 180, height: 180)
                .offset(x: 170, y: -40)

            Circle()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.14 : 0.08))
                .frame(width: 120, height: 120)
                .offset(x: -40, y: 140)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("30 Day Challenge")
                            .font(.flyrTitle)
                            .foregroundStyle(Color.white)

                        Text("Keep your streak alive, track the habit, and give yourself one challenge that never slips.")
                            .font(.flyrSubheadline)
                            .foregroundStyle(Color.white.opacity(0.86))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 16)

                    heroStatusBadge(user: user)
                }

                HStack(spacing: 18) {
                    ProgressRing(progress: viewModel.progressRatio, size: 112, strokeWidth: 10) {
                        VStack(spacing: 2) {
                            Text("\(viewModel.displayedProgressDays)")
                                .font(.flyrTitle2Bold)
                                .foregroundStyle(Color.white)
                                .monospacedDigit()
                            Text("/ 30")
                                .font(.flyrCaption)
                                .foregroundStyle(Color.white.opacity(0.78))
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        heroMetric(title: "Current streak", value: "\(viewModel.currentStreak) days", icon: "flame.fill")
                        heroMetric(title: "Best streak", value: "\(viewModel.bestStreak) days", icon: "trophy.fill")
                        heroMetric(title: "Time left", value: remainingDaysLabel, icon: "calendar")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 260)
        .clipShape(cardShape)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 24, x: 0, y: 10)
    }

    private func privateChallengesCard(user: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Challenge Board")
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)
                    Text("Track the challenges you created and the group challenges you’ve joined.")
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
            }

            if viewModel.additionalChallenges.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.flyrPrimary)
                    Text("No private challenges yet")
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.text)
                    Text("Tap the + button to create a private friend challenge or publish one into Search Challenges.")
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 14) {
                    ForEach(viewModel.additionalChallenges) { challenge in
                        challengeCard(challenge, user: user) {
                            selectedChallenge = challenge
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.border.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func heroStatusBadge(user: AppUser) -> some View {
        let badgeLabel = (viewModel.thirtyDayChallenge == nil ? "START" : viewModel.statusTitle.uppercased())

        if viewModel.thirtyDayChallenge == nil {
            Button {
                Task {
                    await viewModel.startChallenge(
                        for: user.id,
                        creatorName: user.displayName ?? fallbackName(from: user.email)
                    )
                }
            } label: {
                Text(badgeLabel)
                    .font(.flyrCaption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.18))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isMutating)
        } else {
            Text(badgeLabel)
                .font(.flyrCaption.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.18))
                .clipShape(Capsule())
        }
    }

    private func actionCard(user: AppUser) -> some View {
        Button {
            showCreateSheet = true
        } label: {
            Text("Start a New Challenge")
                .font(.flyrSubheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.flyrPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.border.opacity(0.35), lineWidth: 1)
        )
    }

    private func challengeLeaderboardCard(_ leaderboard: RollingChallengeLeaderboardSnapshot, currentUserID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("First 30 Days Leaderboard")
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)
                    Text("\(leaderboard.participantCount) reps in the live window")
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                Text("LIVE")
                    .font(.flyrCaption.weight(.bold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 10) {
                ForEach(Array(leaderboard.entries.prefix(10))) { entry in
                    ChallengeLeaderboardInlineRow(
                        entry: entry,
                        isCurrentUser: normalizeUserID(entry.userID) == currentUserID.uuidString.lowercased()
                    )
                }
            }

            if leaderboard.entries.count > 10 {
                Text("Showing the top 10 for now.")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.border.opacity(0.35), lineWidth: 1)
        )
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search Challenges")
                .font(.flyrHeadline)
                .foregroundStyle(Color.text)

            Text("Browse public challenges to join — including ones you published — or search by title or creator.")
                .font(.flyrFootnote)
                .foregroundStyle(Color.muted)

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.textTertiary)
                TextField("Search by title, type, or creator", text: $viewModel.searchText)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.border.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.flyrPrimary)
            Text("No searchable challenges yet")
                .font(.flyrHeadline)
                .foregroundStyle(Color.text)
            Text("Create one with the + button. It’ll show up here for you and for others to find and join.")
                .font(.flyrFootnote)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.border.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func challengeInfoPillsRow(challenge: Challenge, timeLimitDays: Int?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                infoPill(text: challenge.visibilityLabel, icon: challenge.visibility == .privateInvite ? "lock.fill" : "globe")
                infoPill(
                    text: challenge.participantCount == 1 ? "1 joined" : "\(challenge.participantCount) joined",
                    icon: "person.2.fill"
                )
                infoPill(text: "\(challenge.goalCount) \(challenge.metricLabel)", icon: "scope")
                if let timeLimitDays {
                    infoPill(text: "\(timeLimitDays) days", icon: "calendar")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                infoPill(text: challenge.visibilityLabel, icon: challenge.visibility == .privateInvite ? "lock.fill" : "globe")
                infoPill(
                    text: challenge.participantCount == 1 ? "1 joined" : "\(challenge.participantCount) joined",
                    icon: "person.2.fill"
                )
                infoPill(text: "\(challenge.goalCount) \(challenge.metricLabel)", icon: "scope")
                if let timeLimitDays {
                    infoPill(text: "\(timeLimitDays) days", icon: "calendar")
                }
            }
        }
    }

    @ViewBuilder
    private func searchableChallengePillsRow(challenge: Challenge) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                infoPill(text: challenge.typeLabel, icon: challenge.type.iconName)
                infoPill(
                    text: challenge.participantCount == 1 ? "1 joined" : "\(challenge.participantCount) joined",
                    icon: "person.2.fill"
                )
                infoPill(text: "\(challenge.goalCount) \(challenge.metricLabel)", icon: "chart.bar.fill")
                if let timeLimitHours = challenge.timeLimitHours {
                    infoPill(text: "\(max(timeLimitHours / 24, 1)) days", icon: "clock.fill")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                infoPill(text: challenge.typeLabel, icon: challenge.type.iconName)
                infoPill(
                    text: challenge.participantCount == 1 ? "1 joined" : "\(challenge.participantCount) joined",
                    icon: "person.2.fill"
                )
                infoPill(text: "\(challenge.goalCount) \(challenge.metricLabel)", icon: "chart.bar.fill")
                if let timeLimitHours = challenge.timeLimitHours {
                    infoPill(text: "\(max(timeLimitHours / 24, 1)) days", icon: "clock.fill")
                }
            }
        }
    }

    private func challengeCard(_ challenge: Challenge, user: AppUser, onOpen: @escaping () -> Void) -> some View {
        let isCreator = challenge.isCreated(by: user.id)
        let isPendingInvite = !challenge.hasParticipants
        let canShare = isCreator && challenge.inviteToken != nil
        let participant = viewModel.participantState(for: challenge.id)
        let displayedProgress = displayedProgress(for: challenge, participant: participant)
        let displayedProgressRatio = displayedProgressRatio(for: challenge, participant: participant)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 8) {
                    ChallengeCoverThumbView(storagePath: challenge.coverImagePath)
                    ZStack {
                        Circle()
                            .fill(Color.flyrPrimary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: challenge.type.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.flyrPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)
                    Text(challenge.description?.isEmpty == false ? challenge.description! : challenge.metricLabel.capitalized)
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                statusCapsule(for: challenge)
            }

            challengeInfoPillsRow(
                challenge: challenge,
                timeLimitDays: challenge.timeLimitHours.map { max($0 / 24, 1) }
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(challengeHeadline(challenge, participant: participant, isCreator: isCreator))
                        .font(.flyrSubheadline.weight(.semibold))
                        .foregroundStyle(Color.text)
                    Spacer()
                    Text("\(displayedProgress)/\(challenge.goalCount)")
                        .font(.flyrCaption.weight(.semibold))
                        .foregroundStyle(Color.muted)
                        .monospacedDigit()
                }

                ProgressView(value: displayedProgressRatio)
                    .tint(challenge.status == .completed ? .success : .flyrPrimary)

                Text(challengeSubheadline(challenge, participant: participant, isCreator: isCreator))
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
            }

            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Text("Open Challenge")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.flyrSubheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.flyrPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            if canShare {
                HStack(spacing: 12) {
                    Button {
                        copyChallengeLink(challenge)
                    } label: {
                        Label("Link", systemImage: "link")
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.accent, lineWidth: 2)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { @MainActor in
                            await shareToInstagram(challenge)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image("InstagramLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.accent, lineWidth: 2)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share to Instagram")

                    Button {
                        Task { @MainActor in
                            presentShareOptions(for: challenge)
                        }
                    } label: {
                        Label(isPendingInvite ? "More" : "Share Again", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.accent, lineWidth: 2)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.bg)
        )
    }

    private func searchableChallengeCard(
        _ challenge: Challenge,
        user: AppUser,
        onOpenHostChallenge: @escaping () -> Void
    ) -> some View {
        let isHost = challenge.isCreated(by: user.id)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(challenge.title)
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)
                    Text("Created by \(challenge.creatorName ?? "Someone in FLYR")")
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                statusCapsule(for: challenge)
            }

            Text(challenge.description?.isEmpty == false ? challenge.description! : "A public \(challenge.typeLabel.lowercased()) challenge anyone can join.")
                .font(.flyrBody)
                .foregroundStyle(Color.text)
                .fixedSize(horizontal: false, vertical: true)

            searchableChallengePillsRow(challenge: challenge)

            if isHost {
                Text("You’re the host. Others can discover this challenge here; you can’t join your own challenge as a participant.")
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenHostChallenge) {
                    Text("Open challenge")
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .secondaryButton()
            } else {
                Button {
                    Task {
                        await viewModel.joinSearchableChallenge(challenge, user: user)
                    }
                } label: {
                    HStack {
                        if viewModel.isMutating {
                            ProgressView().tint(.white)
                        }
                        Text("Join Challenge")
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryButton()
                .disabled(viewModel.isMutating)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.border.opacity(0.35), lineWidth: 1)
        )
    }

    private func statusCapsule(for challenge: Challenge) -> some View {
        Text(challenge.status.rawValue.capitalized)
            .font(.flyrCaption.weight(.bold))
            .foregroundStyle(challenge.status == .completed ? Color.success : Color.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(challenge.status == .completed ? Color.success.opacity(0.12) : Color.bgSecondary)
            )
    }

    private func heroMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.flyrCaption)
                    .foregroundStyle(Color.white.opacity(0.72))
                Text(value)
                    .font(.flyrSubheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
            }
        }
    }

    private func infoPill(text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.flyrCaption)
        .foregroundStyle(Color.text)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.bgSecondary)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.warning)
            Text(message)
                .font(.flyrFootnote)
                .foregroundStyle(Color.text)
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.warning.opacity(colorScheme == .dark ? 0.16 : 0.12))
        )
    }

    private func infoBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane.circle.fill")
                .foregroundStyle(Color.info)
            Text(message)
                .font(.flyrFootnote)
                .foregroundStyle(Color.text)
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.info.opacity(colorScheme == .dark ? 0.16 : 0.12))
        )
    }

    @MainActor
    private func shareToInstagram(_ challenge: Challenge) async {
        let image = ChallengeShareComposer.instagramStoryImage(for: challenge)
        let url = viewModel.shareURL(for: challenge)
        let didOpenInstagram = ShareCardGenerator.shareToInstagramStoriesAsBackground(image, contentURL: url)

        if didOpenInstagram {
            showShareStatus("Instagram Story opened.")
            return
        }

        if let url {
            UIPasteboard.general.string = url.absoluteString
        }
        showShareStatus("Instagram Stories isn't available on this device right now. Your invite link was copied.")
    }

    @MainActor
    private func presentShareOptions(for challenge: Challenge) {
        let items = ChallengeShareComposer.activityItems(
            for: challenge,
            message: viewModel.shareMessage(for: challenge),
            url: viewModel.shareURL(for: challenge)
        )

        if !ShareCardGenerator.presentActivityShare(activityItems: items) {
            showShareStatus(ShareCardGenerator.shareSheetUnavailableUserMessage)
        }
    }

    private func copyChallengeLink(_ challenge: Challenge) {
        guard let url = viewModel.shareURL(for: challenge) else {
            showShareStatus("This challenge doesn’t have a share link yet.")
            return
        }
        UIPasteboard.general.string = url.absoluteString
        showShareStatus("Challenge link copied.")
    }

    private func showShareStatus(_ message: String) {
        shareStatusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if shareStatusMessage == message {
                shareStatusMessage = nil
            }
        }
    }

    private var signedOutState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color.muted)
            Text("Sign in to start, share, and search challenges.")
                .font(.flyrHeadline)
                .foregroundStyle(Color.text)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remainingDaysLabel: String {
        guard let challenge = viewModel.thirtyDayChallenge,
              let expiresAt = challenge.expiresAt else {
            return "30 days"
        }

        let daysRemaining = max(
            Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: Date()),
                to: Calendar.current.startOfDay(for: expiresAt)
            ).day ?? 0,
            0
        )

        return challenge.status == .completed ? "Done" : "\(daysRemaining)d left"
    }

    private var actionBody: String {
        switch viewModel.thirtyDayChallenge?.status {
        case .active:
            return "Progress syncs from your current day streak. Pull to refresh after a session or send out a private friend challenge with the + button."
        case .completed:
            return "You can start another round or use the + button to challenge someone else privately."
        case .failed:
            return "A restart creates a new 30-day run without deleting the previous one."
        case .none:
            return "Start your own 30 day streak or create a private challenge for a friend from the + button."
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.thirtyDayChallenge?.status {
        case .completed:
            return "Start Another Round"
        case .failed:
            return "Restart Challenge"
        case .none, .active:
            return "Start 30 Day Challenge"
        }
    }

    private func challengeHeadline(
        _ challenge: Challenge,
        participant: ChallengeParticipant?,
        isCreator: Bool
    ) -> String {
        if !challenge.hasParticipants {
            return isCreator
                ? "Waiting for the first joiner"
                : "Ready for you"
        }

        if participant != nil {
            return challenge.participantCount == 1
                ? "You’re in"
                : "You’re in with \(challenge.participantCount) people"
        }

        if isCreator {
            return challenge.participantCount == 1
                ? (challenge.participantName.map { "\($0) joined" } ?? "1 person joined")
                : "\(challenge.participantCount) people joined"
        }

        return challenge.creatorName.map { "Join \($0)’s challenge" } ?? "Challenge joined"
    }

    private func challengeSubheadline(
        _ challenge: Challenge,
        participant: ChallengeParticipant?,
        isCreator: Bool
    ) -> String {
        if !challenge.hasParticipants {
            if challenge.visibility == .privateInvite {
                if let phone = challenge.invitedPhone, !phone.isEmpty {
                    return "Invite link is locked to that phone number until the first person joins."
                }
                if let email = challenge.invitedEmail {
                    return "Invite link is locked to \(email) until the first person joins."
                }
            }
            return "Anyone with the invite or in Search Challenges can join this one."
        }

        if challenge.status == .completed {
            if let leader = challenge.participantName, challenge.participantCount > 1 {
                return "\(leader) finished on top with \(challenge.progressCount)."
            }
            return "Challenge complete."
        }

        if let participant {
            let leaderLine: String
            if challenge.participantCount > 1,
               let leaderName = challenge.participantName,
               leaderName != participant.participantName {
                leaderLine = " Leader: \(leaderName) at \(challenge.progressCount)."
            } else {
                leaderLine = ""
            }

            if let expiresAt = challenge.expiresAt {
                return "You’re at \(participant.progressCount). Ends \(expiresAt.formatted(date: .abbreviated, time: .omitted)).\(leaderLine)"
            }

            return "You’re at \(participant.progressCount).\(leaderLine)"
        }

        if isCreator, challenge.participantCount > 1, let leader = challenge.participantName {
            return "\(leader) is leading at \(challenge.progressCount)."
        }

        if let expiresAt = challenge.expiresAt {
            return "Ends \(expiresAt.formatted(date: .abbreviated, time: .omitted))."
        }

        return isCreator ? "Waiting for the latest progress sync." : "Your progress will sync on refresh."
    }

    private func fallbackName(from email: String) -> String {
        email.split(separator: "@").first.map(String.init)?.capitalized ?? "Friend"
    }

    private func normalizeUserID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func displayedProgress(for challenge: Challenge, participant: ChallengeParticipant?) -> Int {
        guard let participant, !challenge.isThirtyDayChallenge else {
            return challenge.progressCount
        }
        return participant.progressCount
    }

    private func displayedProgressRatio(for challenge: Challenge, participant: ChallengeParticipant?) -> Double {
        let progress = displayedProgress(for: challenge, participant: participant)
        let total: Int
        switch challenge.scoringMode {
        case .mostInTimeframe:
            total = max(challenge.goalCount, progress, 1)
        case .reachGoal:
            total = max(challenge.goalCount, 1)
        }
        return min(max(Double(progress) / Double(total), 0), 1)
    }
}

private struct ChallengeLeaderboardInlineRow: View {
    let entry: RollingChallengeLeaderboardEntry
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            rankView

            VStack(alignment: .leading, spacing: 6) {
                Text(nameLine)
                    .font(.flyrSubheadline.weight(.semibold))
                    .foregroundStyle(Color.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if entry.currentStreak >= 2 {
                        pill("🔥 \(entry.currentStreak)", tint: Color.orange, background: Color.orange.opacity(0.14))
                    }
                    if entry.accountabilityPosted {
                        pill("📤 Posted", tint: Color.green, background: Color.green.opacity(0.14))
                    }
                }
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(entry.score)")
                    .font(.flyrHeadline.weight(.bold))
                    .foregroundStyle(Color.flyrPrimary)
                    .monospacedDigit()
                Text("homes")
                    .font(.flyrCaption)
                    .foregroundStyle(Color.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isCurrentUser ? Color.flyrPrimary.opacity(0.08) : Color.bg)
        )
    }

    private var nameLine: String {
        ([entry.displayName] + entry.activeBadges.map(\.emoji) + (isCurrentUser ? ["You"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @ViewBuilder
    private var rankView: some View {
        if entry.rank == 1 {
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.yellow)
                .frame(width: 30, height: 30)
        } else {
            Text("#\(entry.rank)")
                .font(.flyrFootnote.weight(.bold))
                .foregroundStyle(Color.muted)
                .monospacedDigit()
                .frame(width: 30)
        }
    }

    private func pill(_ text: String, tint: Color, background: Color) -> some View {
        Text(text)
            .font(.flyrCaption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(Capsule())
    }
}

private struct ChallengeCoverThumbView: View {
    let storagePath: String?
    @State private var signedURL: URL?

    var body: some View {
        Group {
            if let signedURL {
                AsyncImage(url: signedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                    case .empty:
                        Color.bgSecondary
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Color.clear
                    .frame(width: 48, height: 48)
            }
        }
        .task(id: storagePath) {
            guard let storagePath, !storagePath.isEmpty else {
                signedURL = nil
                return
            }
            do {
                signedURL = try await SupabaseManager.shared.client.storage
                    .from("profile_images")
                    .createSignedURL(path: storagePath, expiresIn: 60 * 60 * 24)
            } catch {
                signedURL = nil
            }
        }
    }
}

private struct ChallengeCreateSheet: View {
    let user: AppUser
    let isSaving: Bool
    let onCreate: (ChallengeDraft) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ChallengeDraft()
    @State private var coverImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let coverImage {
                                Image(uiImage: coverImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                VStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 22, weight: .semibold))
                                    Text("Add cover")
                                        .font(.flyrCaption)
                                }
                                .foregroundStyle(Color.muted)
                            }
                        }
                        .frame(width: 88, height: 88)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                                Label("Choose Photo", systemImage: "photo")
                            }
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    showCameraPicker = true
                                } label: {
                                    Label("Take Photo", systemImage: "camera")
                                }
                            }
                            if coverImage != nil {
                                Button("Remove Photo", role: .destructive) {
                                    coverImage = nil
                                    photoPickerItem = nil
                                }
                                .font(.flyrSubheadline)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Cover (optional)")
                }

                Section("Challenge") {
                    TextField("Title", text: $draft.title)
                    TextField("Description", text: $draft.description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    Picker("Type", selection: $draft.type) {
                        ForEach(ChallengeType.userSelectableCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Picker("Mode", selection: $draft.scoringMode) {
                        ForEach(ChallengeScoringMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(draft.scoringMode.subtitle)
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)
                    Stepper("Goal: \(draft.goalCount)", value: $draft.goalCount, in: 1...5000, step: 5)
                    Stepper("Duration: \(draft.durationDays) days", value: $draft.durationDays, in: 1...60)
                }

                Section("Visibility") {
                    Picker("Audience", selection: $draft.visibility) {
                        ForEach(ChallengeVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.title).tag(visibility)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(draft.visibility.subtitle)
                        .font(.flyrFootnote)
                        .foregroundStyle(Color.muted)

                    if draft.visibility == .privateInvite {
                        TextField("Friend’s phone number", text: $draft.invitePhone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }
                }

                Section {
                    Button {
                        Task {
                            var outgoing = draft
                            outgoing.coverImageData = coverImage?.jpegData(compressionQuality: 0.85)
                            await onCreate(outgoing)
                        }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            }
                            Text(draft.visibility == .privateInvite ? "Create and Send" : "Create Challenge")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSaving || !draft.isValid)
                } footer: {
                    Text("Challenges from \(user.displayName ?? user.email) can be shared by link right after creation.")
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            coverImage = image
                        }
                    }
                }
            }
            .sheet(isPresented: $showCameraPicker) {
                ImagePicker(sourceType: .camera) { image in
                    coverImage = image
                }
            }
        }
    }
}

private final class ChallengeShareTextSource: NSObject, UIActivityItemSource {
    private let message: String
    private let title: String
    private let url: URL?
    private let previewImage: UIImage

    init(message: String, title: String, url: URL?, previewImage: UIImage) {
        self.message = message
        self.title = title
        self.url = url
        self.previewImage = previewImage
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        metadata.url = url
        let provider = NSItemProvider(object: previewImage)
        metadata.iconProvider = provider
        metadata.imageProvider = provider
        return metadata
    }
}

private enum ChallengeShareComposer {
    @MainActor
    static func activityItems(for challenge: Challenge, message: String, url: URL?) -> [Any] {
        let image = renderCard(for: challenge)
        let textSource = ChallengeShareTextSource(
            message: message,
            title: "\(challenge.title) • FLYR Challenge",
            url: url,
            previewImage: image
        )
        return [image, textSource]
    }

    @MainActor
    private static func renderCard(for challenge: Challenge) -> UIImage {
        let size = CGSize(width: 1200, height: 1500)
        let card = ChallengeInviteShareCard(challenge: challenge)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2

        return renderer.uiImage ?? UIImage()
    }

    @MainActor
    static func instagramStoryImage(for challenge: Challenge) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let card = ChallengeInstagramStoryCard(challenge: challenge)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true

        return renderer.uiImage ?? UIImage()
    }
}

private struct ChallengeInviteShareCard: View {
    let challenge: Challenge

    private var metricLine: String {
        "\(challenge.goalCount) \(challenge.metricLabel)"
    }

    private var durationLine: String {
        guard let timeLimitHours = challenge.timeLimitHours else { return "No time limit" }
        let days = max(timeLimitHours / 24, 1)
        return days == 1 ? "1 day showdown" : "\(days) day showdown"
    }

    private var senderLine: String {
        if let creator = challenge.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creator.isEmpty {
            return "\(creator) invited you"
        }
        return "You’ve been invited"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "070707"),
                    Color(hex: "151515"),
                    Color(hex: "1E0D0A")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.flyrPrimary.opacity(0.28))
                .frame(width: 680, height: 680)
                .blur(radius: 70)
                .offset(x: 300, y: -320)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 420, height: 420)
                .blur(radius: 40)
                .offset(x: -340, y: 460)

            RoundedRectangle(cornerRadius: 48, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .padding(30)

            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center) {
                    Text("FLYR CHALLENGE")
                        .font(.flyrCaption.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 88, height: 88)
                        Image(systemName: challenge.type.iconName)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Text(senderLine.uppercased())
                        .font(.flyrCaption.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(challenge.title)
                        .font(.flyrSystem(size: 84, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    Text(challenge.description?.isEmpty == false
                         ? challenge.description!
                         : "Open FLYR, accept the invite, and start tracking the competition.")
                        .font(.flyrSystem(size: 34, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        statPill(title: "Goal", value: metricLine)
                        statPill(title: "Format", value: challenge.typeLabel)
                    }

                    HStack(spacing: 16) {
                        statPill(title: "Window", value: durationLine)
                        statPill(title: "Mode", value: challenge.scoringMode == .reachGoal ? "First to finish" : "Most by the buzzer")
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Join in the iPhone app")
                                .font(.flyrSystem(size: 38, weight: .bold))
                                .foregroundStyle(Color.white)
                            Text("Tap the link in the message to open the invite.")
                                .font(.flyrSystem(size: 28, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .padding(26)
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.flyrPrimary.opacity(0.92))
                    )

                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 10, height: 10)
                        Text("Private invite link included below the card")
                            .font(.flyrSubheadline)
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }
            }
            .padding(56)
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.flyrCaption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.60))
            Text(value)
                .font(.flyrSystem(size: 28, weight: .semibold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ChallengeInstagramStoryCard: View {
    let challenge: Challenge

    private var senderLine: String {
        if let creator = challenge.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !creator.isEmpty {
            return "@\(creator.replacingOccurrences(of: " ", with: "")) challenged you"
        }
        return "You got challenged"
    }

    private var goalLine: String {
        "\(challenge.goalCount) \(challenge.metricLabel)"
    }

    private var durationLine: String {
        guard let hours = challenge.timeLimitHours else { return "No clock" }
        let days = max(hours / 24, 1)
        return days == 1 ? "1 day" : "\(days) days"
    }

    private var modeLine: String {
        switch challenge.scoringMode {
        case .reachGoal:
            return "First one there wins"
        case .mostInTimeframe:
            return "Highest count wins"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "090608"),
                    Color(hex: "22070C"),
                    Color(hex: "FF3347")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 460, height: 460)
                .blur(radius: 20)
                .offset(x: 320, y: -520)

            Circle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 560, height: 560)
                .blur(radius: 30)
                .offset(x: -300, y: 560)

            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image("FLYRLogoWide")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 340, height: 104)
                        Text("CHALLENGE INVITE")
                            .font(.flyrCaption.weight(.bold))
                            .tracking(1.8)
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Spacer()
                }

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Text(senderLine.uppercased())
                        .font(.flyrCaption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text(challenge.title)
                        .font(.flyrSystem(size: 72, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    Text(challenge.description?.isEmpty == false
                         ? challenge.description!
                         : "Accept the challenge in FLYR and post your result.")
                        .font(.flyrSystem(size: 30, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 14) {
                    statRow(leftTitle: "GOAL", leftValue: goalLine, rightTitle: "TYPE", rightValue: challenge.typeLabel)
                    statRow(leftTitle: "WINDOW", leftValue: durationLine, rightTitle: "MODE", rightValue: modeLine)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("ACCEPT THE INVITATION")
                        .font(.flyrCaption.weight(.bold))
                        .tracking(1.3)
                        .foregroundStyle(Color.white.opacity(0.66))

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Tap the link box below")
                                .font(.flyrSystem(size: 22, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.88))

                            Image(systemName: "arrow.down.right")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.88))
                        }
                        .padding(.leading, 8)

                        HStack(spacing: 14) {
                            Image(systemName: "link")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.92))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("accept the invitation")
                                    .font(.flyrSystem(size: 28, weight: .bold))
                                    .foregroundStyle(Color.white)
                                Text("Open in FLYR to join the challenge")
                                    .font(.flyrSystem(size: 20, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.72))
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .padding(22)
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Color.black.opacity(0.28))
                    )
                }
                .padding(.bottom, 74)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 72)
        }
    }

    private func statRow(leftTitle: String, leftValue: String, rightTitle: String, rightValue: String) -> some View {
        HStack(spacing: 14) {
            statBlock(title: leftTitle, value: leftValue)
            statBlock(title: rightTitle, value: rightValue)
        }
    }

    private func statBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.flyrCaption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.62))
            Text(value)
                .font(.flyrSystem(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        ChallengesHomeView()
    }
}
