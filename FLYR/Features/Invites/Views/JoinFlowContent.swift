import SwiftUI

private enum InviteAuthProvider {
    case google
    case apple
    case email
}

/// Content for join flow: validate, show session/workspace details, then sign-in or join.
struct JoinFlowContent: View {
    let token: String
    @ObservedObject var viewModel: JoinFlowViewModel
    var onAcceptSuccess: (InviteAcceptResponse) -> Void
    var onDismiss: () -> Void
    @EnvironmentObject var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared
    @State private var acceptErrorMessage: String?
    @State private var authErrorMessage: String?
    @State private var activeAuthProvider: InviteAuthProvider?
    @State private var showEmailFields = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.validated == nil {
                ProgressView("Checking invite…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = viewModel.errorMessage {
                joinErrorView(message: err)
            } else if let validation = viewModel.validated {
                joinValidatedView(validation: validation)
            } else {
                Button("Check invite") {
                    Task { await viewModel.validate(token: token) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel.validated == nil && viewModel.errorMessage == nil {
                acceptErrorMessage = nil
                authErrorMessage = nil
                await viewModel.validate(token: token)
            }
        }
    }

    private func joinErrorView(message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .multilineTextAlignment(.center)
                .padding()
            Button("Dismiss") { onDismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func joinValidatedView(validation: InviteValidateResponse) -> some View {
        let inviteEmail = normalizedEmail(validation.email)
        let inviteEmailDisplay = sanitizedEmail(validation.email)
        let userEmail = normalizedEmail(auth.user?.email)
        let userEmailDisplay = sanitizedEmail(auth.user?.email)
        let canAcceptWithCurrentAccount = auth.user != nil
            && (inviteEmail == nil || userEmail == inviteEmail)
        let showsAccountMismatchHint = auth.user != nil && !canAcceptWithCurrentAccount

        return VStack(spacing: 24) {
            Text("You're invited to join")
                .font(.headline)

            if let name = validation.campaignTitle, !name.isEmpty {
                Text(name)
                    .font(.title2)
            } else if let name = validation.workspaceName, !name.isEmpty {
                Text(name)
                    .font(.title2)
            }

            if let workspaceName = validation.workspaceName,
               let campaignTitle = validation.campaignTitle,
               !workspaceName.isEmpty,
               workspaceName != campaignTitle {
                Text(workspaceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(invitePrompt(for: validation))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let acceptErrorMessage {
                Text(acceptErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let authErrorMessage {
                Text(authErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if auth.user == nil {
                authOptions(validation: validation)
            } else if canAcceptWithCurrentAccount {
                Button(joinActionTitle(for: validation)) {
                    Task { await acceptInvite() }
                }
                .disabled(viewModel.isLoading)
                .frame(maxWidth: .infinity)
                .padding()
                .buttonStyle(.borderedProminent)
            } else if showsAccountMismatchHint {
                Text(accountMismatchMessage(currentEmail: userEmailDisplay, inviteEmail: inviteEmailDisplay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Use different account") {
                    Task {
                        authErrorMessage = nil
                        acceptErrorMessage = nil
                        await auth.signOut()
                        await routeState.resolveRoute()
                    }
                }
                .foregroundStyle(.secondary)
            }

            Button("Cancel") { onDismiss() }
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func invitePrompt(for validation: InviteValidateResponse) -> String {
        let hasLiveSession = validation.sessionId != nil

        if let email = sanitizedEmail(validation.email) {
            if hasLiveSession {
                return "Sign in with \(email) to join the live map."
            }
            if let campaignTitle = validation.campaignTitle, !campaignTitle.isEmpty {
                return "Sign in with \(email) to open \(campaignTitle)."
            }
            return "Sign in with \(email) to continue."
        }

        if hasLiveSession, let campaignTitle = validation.campaignTitle, !campaignTitle.isEmpty {
            return "Sign in to open \(campaignTitle) and start live with your team."
        }

        if let campaignTitle = validation.campaignTitle, !campaignTitle.isEmpty {
            return "Sign in to open \(campaignTitle)."
        }

        if let workspaceName = validation.workspaceName, !workspaceName.isEmpty {
            if hasLiveSession {
                return "Sign in to join this live session in \(workspaceName)."
            }
            return "Sign in to join \(workspaceName)."
        }

        return "Sign in to continue."
    }

    private func joinActionTitle(for validation: InviteValidateResponse) -> String {
        if validation.sessionId != nil {
            return "Join live"
        }
        if let campaignTitle = validation.campaignTitle, !campaignTitle.isEmpty {
            return "Open campaign"
        }
        return "Join workspace"
    }

    @ViewBuilder
    private func authOptions(validation: InviteValidateResponse) -> some View {
        VStack(spacing: 12) {
            authButton(
                title: "Continue with Google",
                systemImage: "g.circle.fill",
                provider: .google
            ) {
                Task { await signIn(with: .google, validation: validation) }
            }

            authButton(
                title: "Continue with Apple",
                systemImage: "apple.logo",
                provider: .apple
            ) {
                Task { await signIn(with: .apple, validation: validation) }
            }

            authButton(
                title: showEmailFields ? "Hide Email" : "Continue with Email",
                systemImage: "envelope.fill",
                provider: .email
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showEmailFields.toggle()
                }
                authErrorMessage = nil
                acceptErrorMessage = nil
                if showEmailFields, email.isEmpty, let inviteEmail = sanitizedEmail(validation.email) {
                    email = inviteEmail
                }
            }

            if showEmailFields {
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: email) { _, _ in authErrorMessage = nil }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: password) { _, _ in authErrorMessage = nil }

                    Button {
                        Task { await continueWithEmail(validation: validation) }
                    } label: {
                        HStack(spacing: 10) {
                            if activeAuthProvider == .email {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            Text("Continue")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .disabled(activeAuthProvider != nil || !canContinueWithEmail)
                    .buttonStyle(.borderedProminent)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func authButton(
        title: String,
        systemImage: String,
        provider: InviteAuthProvider,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if activeAuthProvider == provider {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .disabled(activeAuthProvider != nil)
        .buttonStyle(.borderedProminent)
    }

    private var canContinueWithEmail: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    @MainActor
    private func signIn(with provider: InviteAuthProvider, validation: InviteValidateResponse) async {
        activeAuthProvider = provider
        authErrorMessage = nil
        acceptErrorMessage = nil
        defer { activeAuthProvider = nil }

        do {
            switch provider {
            case .google:
                try await auth.signInWithGoogle()
            case .apple:
                try await auth.signInWithApple()
            case .email:
                return
            }

            await handleAuthenticatedUser(validation: validation)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func continueWithEmail(validation: InviteValidateResponse) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }

        activeAuthProvider = .email
        authErrorMessage = nil
        acceptErrorMessage = nil
        defer { activeAuthProvider = nil }

        do {
            try await auth.signInWithEmail(email: trimmedEmail, password: password)
            await finalizeEmailAuth(validation: validation)
        } catch {
            if shouldRetryAsSignUp(error) {
                do {
                    try await auth.signUpWithEmail(email: trimmedEmail, password: password)
                    await finalizeEmailAuth(validation: validation)
                } catch {
                    authErrorMessage = error.localizedDescription
                }
            } else {
                authErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func finalizeEmailAuth(validation: InviteValidateResponse) async {
        email = ""
        password = ""
        showEmailFields = false
        await handleAuthenticatedUser(validation: validation)
    }

    private func shouldRetryAsSignUp(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("invalid")
            || message.contains("credentials")
            || message.contains("invalid login")
    }

    @MainActor
    private func handleAuthenticatedUser(validation: InviteValidateResponse) async {
        let inviteEmail = normalizedEmail(validation.email)
        let userEmail = normalizedEmail(auth.user?.email)

        guard inviteEmail == nil || inviteEmail == userEmail else { return }
        await acceptInvite()
    }

    @MainActor
    private func acceptInvite() async {
        viewModel.isLoading = true
        acceptErrorMessage = nil
        defer { viewModel.isLoading = false }

        do {
            let response = try await viewModel.accept(token: token)
            onAcceptSuccess(response)
        } catch {
            acceptErrorMessage = error.localizedDescription
        }
    }

    private func accountMismatchMessage(currentEmail: String?, inviteEmail: String?) -> String {
        if let currentEmail, let inviteEmail {
            return "You're signed in as \(currentEmail), but this invite was sent to \(inviteEmail). Join will only work with the invited account."
        }

        if let inviteEmail {
            return "This invite was sent to \(inviteEmail). Join will only work with the invited account."
        }

        return "This invite is tied to a different account. Sign out and use the invited email to continue."
    }

    private func normalizedEmail(_ raw: String?) -> String? {
        sanitizedEmail(raw)?.lowercased()
    }

    private func sanitizedEmail(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let cleaned = raw
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned.isEmpty ? nil : cleaned
    }
}
