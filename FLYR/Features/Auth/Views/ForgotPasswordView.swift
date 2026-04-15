import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared

    @State private var email: String
    @State private var isSubmitting = false
    @State private var successMessage: String?
    @State private var errorMessage: String?

    init(initialEmail: String = "") {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("FLYR")
                                .font(.flyrCaption)
                                .foregroundColor(.flyrPrimary)
                                .tracking(1.6)

                            Text("Reset your password")
                                .font(.flyrTitle2Bold)
                                .foregroundColor(.text)

                            Text("Enter the email linked to your account and we'll send you a secure reset link.")
                                .font(.flyrBody)
                                .foregroundColor(.muted)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Email")
                                .font(.flyrSubheadline)
                                .foregroundColor(.muted)

                            TextField("name@company.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 52)
                                .background(Color.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .onChange(of: email) { _, _ in
                                    errorMessage = nil
                                }
                        }

                        if let successMessage {
                            PasswordRecoveryNoticeCard(
                                title: "Check your inbox",
                                message: successMessage,
                                accent: .success,
                                systemImage: "paperplane.fill"
                            )
                        }

                        if let errorMessage {
                            PasswordRecoveryNoticeCard(
                                title: "Couldn't send reset email",
                                message: errorMessage,
                                accent: .error,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Send reset email")
                                        .font(.flyrHeadline)
                                }
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .frame(height: 52)
                            .background(canSubmit ? Color.flyrPrimary : Color.bgTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(!canSubmit || isSubmitting)

                        Text("Links open the FLYR app directly so you can choose a new password there.")
                            .font(.flyrFootnote)
                            .foregroundColor(.muted)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Forgot Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil

        defer { isSubmitting = false }

        do {
            try await auth.sendPasswordResetEmail(email: trimmedEmail)
            routeState.updatePasswordResetEmailHint(trimmedEmail)
            successMessage = "If \(trimmedEmail) is registered, you'll receive a password reset email in a moment."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PasswordRecoveryNoticeCard: View {
    let title: String
    let message: String
    let accent: Color
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(accent)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.flyrHeadline)
                    .foregroundColor(.text)

                Text(message)
                    .font(.flyrSubheadline)
                    .foregroundColor(.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(accent.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
