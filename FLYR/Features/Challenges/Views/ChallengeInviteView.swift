import SwiftUI
import Combine

@MainActor
private final class ChallengeInviteViewModel: ObservableObject {
    @Published var invite: ChallengeInviteDetails?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let challengeService = ChallengeService.shared
    private let statsService = StatsService.shared

    func validate(token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            invite = try await challengeService.validateInvite(token: token)
        } catch {
            invite = nil
            errorMessage = error.localizedDescription
        }
    }

    func accept(token: String, user: AppUser, participantPhoneDigits: String?) async throws -> Challenge {
        isLoading = true
        defer { isLoading = false }
        let stats = try await statsService.fetchUserStats(userID: user.id)
        let baselineCount = challengeService.currentMetricCount(for: invite?.type ?? .doorKnock, stats: stats)
        return try await challengeService.acceptInvite(
            token: token,
            participantName: user.displayName ?? fallbackName(from: user.email),
            participantEmail: user.email,
            participantPhone: participantPhoneDigits,
            baselineCount: baselineCount
        )
    }

    private func fallbackName(from email: String) -> String {
        email.split(separator: "@").first.map(String.init)?.capitalized ?? "Friend"
    }
}

struct ChallengeInviteView: View {
    let token: String

    @EnvironmentObject private var routeState: AppRouteState
    @EnvironmentObject private var uiState: AppUIState
    @StateObject private var auth = AuthManager.shared
    @StateObject private var viewModel = ChallengeInviteViewModel()
    @State private var showSignIn = false
    @State private var acceptancePhone: String = ""

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.invite == nil {
                ProgressView("Loading challenge invite…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                inviteErrorView(message: error)
            } else if let invite = viewModel.invite {
                inviteDetailsView(invite)
            } else {
                Color.clear
                    .task {
                        await viewModel.validate(token: token)
                    }
            }
        }
        .preferredColorScheme(uiState.colorScheme)
        .navigationTitle("Challenge Invite")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: token) {
            if viewModel.invite == nil && viewModel.errorMessage == nil {
                await viewModel.validate(token: token)
            }
        }
    }

    private func inviteErrorView(message: String) -> some View {
        VStack(spacing: 18) {
            Text(message)
                .font(.flyrBody)
                .foregroundStyle(Color.text)
                .multilineTextAlignment(.center)
            Button("Back to app") {
                routeState.clearPendingChallengeToken()
                Task { await routeState.resolveRoute() }
            }
            .primaryButton()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg.ignoresSafeArea())
    }

    private func inviteDetailsView(_ invite: ChallengeInviteDetails) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(invite.title)
                        .font(.flyrTitle)
                        .foregroundStyle(Color.text)

                    Text(invite.description?.isEmpty == false ? invite.description! : "A FLYR challenge is waiting for you.")
                        .font(.flyrBody)
                        .foregroundStyle(Color.muted)

                    HStack(spacing: 10) {
                        invitePill(text: invite.type.title, icon: invite.type.iconName)
                        invitePill(text: "\(invite.goalCount) \(metricLabel(for: invite.type))", icon: "scope")
                        if let timeLimitHours = invite.timeLimitHours {
                            invitePill(text: "\(max(timeLimitHours / 24, 1)) days", icon: "calendar")
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.bgSecondary)
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text(invite.creatorName.map { "\($0) sent this challenge." } ?? "Someone sent this challenge.")
                        .font(.flyrHeadline)
                        .foregroundStyle(Color.text)

                    if let invitedPhone = invite.invitedPhone, !invitedPhone.isEmpty {
                        Text("Enter the phone number this invite was sent to.")
                            .font(.flyrFootnote)
                            .foregroundStyle(Color.muted)
                    } else if let invitedEmail = invite.invitedEmail {
                        Text("This invite is reserved for \(invitedEmail).")
                            .font(.flyrFootnote)
                            .foregroundStyle(Color.muted)
                    }

                    if invite.participantCount > 0 {
                        Text(invite.participantCount == 1 ? "1 person has already joined." : "\(invite.participantCount) people have already joined.")
                            .font(.flyrFootnote)
                            .foregroundStyle(Color.muted)
                    }

                    if invite.alreadyJoined {
                        Text("You’ve already joined this challenge.")
                            .font(.flyrFootnote)
                            .foregroundStyle(Color.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.bgSecondary)
                )

                actionArea(invite)
            }
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
    }

    @ViewBuilder
    private func actionArea(_ invite: ChallengeInviteDetails) -> some View {
        if auth.user == nil {
            Button("Sign In to Join") {
                showSignIn = true
            }
            .primaryButton()
            .fullScreenCover(isPresented: $showSignIn) {
                SignInView()
                    .onChange(of: auth.user?.id) { _, newValue in
                        if newValue != nil {
                            showSignIn = false
                        }
                    }
            }
        } else if invite.alreadyJoined {
            Button("Open FLYR") {
                routeState.clearPendingChallengeToken()
                Task { await routeState.resolveRoute() }
            }
            .primaryButton()
        } else if let user = auth.user {
            let userEmail = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let inviteEmail = invite.invitedEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let invitePhoneDigits = invite.invitedPhone?.challengePhoneDigits
            let typedPhoneDigits = acceptancePhone.challengePhoneDigits
            let needsPhone = invitePhoneDigits.map { !$0.isEmpty } ?? false
            let phoneMatches = !needsPhone || (!typedPhoneDigits.isEmpty && typedPhoneDigits == invitePhoneDigits)
            let emailMatches = inviteEmail == nil || inviteEmail == userEmail
            let canAccept = phoneMatches && emailMatches

            if needsPhone {
                TextField("Your phone number", text: $acceptancePhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.bgSecondary)
                    )
            }

            if canAccept {
                Button {
                    Task {
                        do {
                            let phoneParam = needsPhone ? typedPhoneDigits : nil
                            _ = try await viewModel.accept(token: token, user: user, participantPhoneDigits: phoneParam)
                            routeState.clearPendingChallengeToken()
                            await routeState.resolveRoute()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView().tint(.white)
                        }
                        Text("Join Challenge")
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryButton()
            } else if needsPhone {
                Text("The number must match the one your friend entered when they created this challenge.")
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
            } else {
                Text("You’re signed in as \(user.email). This invite was sent to \(inviteEmail ?? "another account").")
                    .font(.flyrFootnote)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func invitePill(text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.flyrCaption)
        .foregroundStyle(Color.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.bg)
        .clipShape(Capsule())
    }

    private func metricLabel(for type: ChallengeType) -> String {
        switch type {
        case .doorKnock:
            return "doors"
        case .flyerDrop:
            return "flyers"
        case .followUp:
            return "conversations"
        case .leads:
            return "leads"
        case .custom:
            return "progress"
        }
    }
}
