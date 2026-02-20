import SwiftUI
import UIKit
import AuthenticationServices

struct SignUpView: View {
    var onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared
    @State private var isSigningUp = false
    @State private var isEmailSigningUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var emailSignUpError: String?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: SignUpToastType = .success

    enum SignUpToastType {
        case success, error
    }

    private var isLightBackground: Bool { colorScheme == .light }
    private var buttonBackground: Color { isLightBackground ? .black : Color.white }
    private var buttonForeground: Color { isLightBackground ? .white : .black }
    private var progressTint: Color { isLightBackground ? .white : .black }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 40)

                        Text("Create account")
                            .font(.system(size: 28, weight: .bold))
                            .frame(maxWidth: .infinity)

                        Button {
                            Task { await signUpWithGoogle() }
                        } label: {
                            HStack(spacing: 12) {
                                if isSigningUp {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: progressTint))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 22))
                                    Text("Sign up with Google")
                                        .font(.system(size: 17, weight: .medium))
                                }
                            }
                            .foregroundColor(buttonForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(buttonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isSigningUp)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                        SignInWithAppleButton(
                            .signUp,
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: { result in
                                Task { await handleAppleSignInResult(result) }
                            }
                        )
                        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(isSigningUp)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)

                        VStack(spacing: 12) {
                            Text("or sign up with email")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                            TextField("Email", text: $email)
                                .padding(.horizontal, 32)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: email) { _, _ in emailSignUpError = nil }
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: password) { _, _ in emailSignUpError = nil }
                                .padding(.horizontal, 32)
                            Button {
                                Task { await signUpWithEmail() }
                            } label: {
                                HStack(spacing: 12) {
                                    if isEmailSigningUp {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: progressTint))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Create account")
                                            .font(.system(size: 17, weight: .medium))
                                    }
                                }
                                .foregroundColor(buttonForeground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(buttonBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(isEmailSigningUp || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                            .padding(.horizontal, 32)
                            .padding(.top, 4)
                            if let error = emailSignUpError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 32)
                            }
                        }
                        .padding(.top, 24)

                        Button {
                            onDismiss()
                        } label: {
                            Text("Already have an account? Sign in")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 16)

                        Spacer()
                            .frame(height: 40)
                    }
                }

                if showToast {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: toastType == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(toastType == .success ? .green : .red)
                            Text(toastMessage)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 50)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
            }
        }
    }

    private func signUpWithGoogle() async {
        isSigningUp = true
        do {
            try await auth.signInWithGoogle()
            await MainActor.run {
                routeState.setRouteToOnboardingFromSignUp()
                displayToast(message: "Account created successfully", type: .success)
                onDismiss()
            }
        } catch {
            await MainActor.run {
                let msg = error.localizedDescription
                displayToast(message: msg.isEmpty ? "Sign-up failed. Try again." : msg, type: .error)
            }
        }
        isSigningUp = false
    }

    private func signUpWithEmail() async {
        isEmailSigningUp = true
        emailSignUpError = nil
        do {
            try await auth.signUpWithEmail(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            await MainActor.run {
                routeState.setRouteToOnboardingFromSignUp()
                displayToast(message: "Account created successfully", type: .success)
                onDismiss()
            }
        } catch {
            await MainActor.run {
                emailSignUpError = error.localizedDescription
            }
        }
        isEmailSigningUp = false
    }

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningUp = true
        switch result {
        case .success(let authorization):
            do {
                try await auth.handleAppleSignInAuthorization(authorization)
                await MainActor.run {
                    routeState.setRouteToOnboardingFromSignUp()
                    displayToast(message: "Account created successfully", type: .success)
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    let msg = error.localizedDescription
                    displayToast(message: msg.isEmpty ? "Sign-up failed. Try again." : msg, type: .error)
                }
            }
        case .failure(let error):
            await MainActor.run {
                displayToast(message: error.localizedDescription, type: .error)
            }
        }
        isSigningUp = false
    }

    private func displayToast(message: String, type: SignUpToastType) {
        toastMessage = message
        toastType = type
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showToast = false }
        }
    }
}
