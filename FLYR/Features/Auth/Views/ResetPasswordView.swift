import SwiftUI

struct ResetPasswordView: View {
    @EnvironmentObject private var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var resendEmail = ""
    @State private var isResending = false
    @State private var resendMessage: String?
    @State private var resendError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        switch routeState.passwordResetState {
                        case .idle, .awaitingLink:
                            loadingState
                        case .ready(let email):
                            resetForm(email: email)
                        case .invalid(let message):
                            invalidState(message: message)
                        case .success(let message):
                            successState(message: message)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Reset Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await leaveRecoveryFlow() }
                    }
                }
            }
            .onAppear {
                if resendEmail.isEmpty {
                    resendEmail = routeState.passwordResetEmailHint
                }
            }
            .onChange(of: routeState.passwordResetEmailHint) { _, newValue in
                if !newValue.isEmpty {
                    resendEmail = newValue
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FLYR")
                .font(.flyrCaption)
                .foregroundColor(.flyrPrimary)
                .tracking(1.6)

            Text("Choose a new password")
                .font(.flyrTitle2Bold)
                .foregroundColor(.text)

            Text("Use the secure recovery link from your email to finish resetting your password.")
                .font(.flyrBody)
                .foregroundColor(.muted)
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView()
                .tint(.flyrPrimary)

            Text("Validating your reset link...")
                .font(.flyrHeadline)
                .foregroundColor(.text)

            Text("This usually takes just a moment.")
                .font(.flyrSubheadline)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func resetForm(email: String?) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let email, !email.isEmpty {
                PasswordRecoveryNoticeCard(
                    title: "Resetting \(email)",
                    message: "Enter the new password you want to use for this FLYR account.",
                    accent: .info,
                    systemImage: "person.crop.circle.badge.key.fill"
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("New password")
                    .font(.flyrSubheadline)
                    .foregroundColor(.muted)

                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: newPassword) { _, _ in submitError = nil }

                Text("Confirm password")
                    .font(.flyrSubheadline)
                    .foregroundColor(.muted)

                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: confirmPassword) { _, _ in submitError = nil }
            }

            if let submitError {
                PasswordRecoveryNoticeCard(
                    title: "Couldn't reset password",
                    message: submitError,
                    accent: .error,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            Button {
                Task { await submitPasswordReset() }
            } label: {
                HStack {
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save new password")
                            .font(.flyrHeadline)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .frame(height: 52)
                .background(canSubmitNewPassword ? Color.flyrPrimary : Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canSubmitNewPassword || isSubmitting)
        }
    }

    private func invalidState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            PasswordRecoveryNoticeCard(
                title: "This reset link isn't usable anymore",
                message: message,
                accent: .error,
                systemImage: "xmark.octagon.fill"
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("Request a new reset email")
                    .font(.flyrHeadline)
                    .foregroundColor(.text)

                TextField("name@company.com", text: $resendEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: resendEmail) { _, _ in
                        resendError = nil
                        resendMessage = nil
                    }
            }

            if let resendMessage {
                PasswordRecoveryNoticeCard(
                    title: "New reset email sent",
                    message: resendMessage,
                    accent: .success,
                    systemImage: "paperplane.fill"
                )
            }

            if let resendError {
                PasswordRecoveryNoticeCard(
                    title: "Couldn't resend email",
                    message: resendError,
                    accent: .error,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            Button {
                Task { await resendPasswordResetEmail() }
            } label: {
                HStack {
                    Spacer()
                    if isResending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send new reset email")
                            .font(.flyrHeadline)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .frame(height: 52)
                .background(canResendEmail ? Color.flyrPrimary : Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!canResendEmail || isResending)

            Button("Back to sign in") {
                Task { await leaveRecoveryFlow() }
            }
            .font(.flyrHeadline)
            .foregroundColor(.flyrPrimary)
        }
    }

    private func successState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            PasswordRecoveryNoticeCard(
                title: "Password updated",
                message: message,
                accent: .success,
                systemImage: "checkmark.circle.fill"
            )

            Button(auth.hasPasswordRecoveryRestoreSession ? "Return to app" : "Return to sign in") {
                Task { await leaveRecoveryFlow() }
            }
            .font(.flyrHeadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.flyrPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var canSubmitNewPassword: Bool {
        !newPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canResendEmail: Bool {
        !resendEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitPasswordReset() async {
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPassword.isEmpty, !trimmedConfirm.isEmpty else {
            submitError = "Enter and confirm your new password."
            return
        }

        guard trimmedPassword == trimmedConfirm else {
            submitError = "Passwords don't match yet."
            return
        }

        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }

        do {
            try await auth.updatePasswordFromRecovery(newPassword: trimmedPassword)
            newPassword = ""
            confirmPassword = ""
            routeState.presentPasswordReset(
                state: .success(message: "Your password has been updated. Use it the next time you sign in to FLYR."),
                emailHint: routeState.passwordResetEmailHint
            )
        } catch {
            submitError = error.localizedDescription
        }
    }

    private func resendPasswordResetEmail() async {
        let trimmedEmail = resendEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        isResending = true
        resendError = nil
        resendMessage = nil
        defer { isResending = false }

        do {
            try await auth.sendPasswordResetEmail(email: trimmedEmail)
            routeState.updatePasswordResetEmailHint(trimmedEmail)
            resendMessage = "If \(trimmedEmail) is registered, a fresh reset email is on its way."
        } catch {
            resendError = error.localizedDescription
        }
    }

    private func leaveRecoveryFlow() async {
        await auth.finishPasswordRecoveryFlow()
        await routeState.completePasswordResetFlow()
    }
}
