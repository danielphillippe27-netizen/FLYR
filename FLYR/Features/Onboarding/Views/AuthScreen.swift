import SwiftUI

struct AuthScreen: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var embeddedInFlow: Bool = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var auth = AuthManager.shared

    private var isLightBackground: Bool { colorScheme == .light }
    private var signInButtonBackground: Color { isLightBackground ? .black : Color.white }
    private var signInButtonForeground: Color { isLightBackground ? .white : .black }
    private var signInProgressTint: Color { isLightBackground ? .white : .black }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.flyrPrimary)
                            Text("Create your account")
                                .font(.system(size: 28, weight: .bold))
                            Text("Save your setup and start tracking")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 32)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Profile")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            PrefilledField(icon: "person.fill", label: "Name", value: viewModel.response.fullName)
                        }
                        .padding(.horizontal, 24)

                        VStack(spacing: 16) {
                            Button {
                                Task { await signInWithGoogle() }
                            } label: {
                                HStack(spacing: 12) {
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: signInProgressTint))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "g.circle.fill")
                                            .font(.system(size: 22))
                                        Text("Sign in with Google")
                                            .font(.system(size: 17, weight: .medium))
                                    }
                                }
                                .foregroundColor(signInButtonForeground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(signInButtonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(viewModel.isLoading)
                            .padding(.horizontal, 24)

                            Button {
                                Task { await signInWithApple() }
                            } label: {
                                HStack(spacing: 12) {
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: signInProgressTint))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "apple.logo")
                                            .font(.system(size: 20, weight: .medium))
                                        Text("Sign in with Apple")
                                            .font(.system(size: 17, weight: .medium))
                                    }
                                }
                                .foregroundColor(signInButtonForeground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(signInButtonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(viewModel.isLoading)
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 8)

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red.opacity(0.1))
                                )
                                .padding(.horizontal, 24)
                        }

                        Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if embeddedInFlow {
                        Button("Back") { viewModel.back() }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear { viewModel.errorMessage = nil }
    }

    private func signInWithGoogle() async {
        viewModel.errorMessage = nil
        viewModel.isLoading = true
        defer { viewModel.isLoading = false }
        do {
            try await auth.signInWithGoogle()
            await viewModel.syncOnboardingDataToProfile()
            if viewModel.errorMessage == nil, !embeddedInFlow {
                dismiss()
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func signInWithApple() async {
        viewModel.errorMessage = nil
        viewModel.isLoading = true
        defer { viewModel.isLoading = false }
        do {
            try await auth.signInWithApple()
            await viewModel.syncOnboardingDataToProfile()
            if viewModel.errorMessage == nil, !embeddedInFlow {
                dismiss()
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

struct PrefilledField: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.flyrPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .medium))
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
