import SwiftUI
import UIKit
import Lottie

struct SignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var routeState: AppRouteState
    @StateObject private var auth = AuthManager.shared
    @State private var isSigningIn = false
    @State private var isEmailSigningIn = false
    @State private var email = ""
    @State private var password = ""
    @State private var emailSignInError: String?
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .success

    enum ToastType {
        case success, error
    }

    private var isLightBackground: Bool { colorScheme == .light }
    private var signInButtonBackground: Color { isLightBackground ? .black : Color.white }
    private var signInButtonForeground: Color { isLightBackground ? .white : .black }
    private var signInProgressTint: Color { isLightBackground ? .white : .black }

    private var canContinueWithEmail: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 24)

                        VStack(spacing: 8) {
                            LoopingLottieView(name: colorScheme == .light ? "splash_black" : "splash")
                                .frame(width: 340, height: 227)
                                .clipped()
                        }
                        .padding(.top, 16)

                        Button {
                            Task { await signInWithGoogle() }
                        } label: {
                            HStack(spacing: 12) {
                                if isSigningIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: signInProgressTint))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 22))
                                    Text("Continue with Google")
                                        .font(.system(size: 17, weight: .medium))
                                }
                            }
                            .foregroundColor(signInButtonForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(signInButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isSigningIn)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                        Button {
                            Task { await signInWithApple() }
                        } label: {
                            HStack(spacing: 12) {
                                if isSigningIn {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: signInProgressTint))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 22))
                                    Text("Continue with Apple")
                                        .font(.system(size: 17, weight: .medium))
                                }
                            }
                            .foregroundColor(signInButtonForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(signInButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(isSigningIn)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)

                        VStack(spacing: 12) {
                            Text("or continue with email")
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
                                .onChange(of: email) { _, _ in emailSignInError = nil }
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: password) { _, _ in emailSignInError = nil }
                                .padding(.horizontal, 32)
                            Button {
                                Task { await continueWithEmail() }
                            } label: {
                                HStack(spacing: 12) {
                                    if isEmailSigningIn {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: canContinueWithEmail ? .black : Color(.secondaryLabel)))
                                            .scaleEffect(0.8)
                                    } else {
                                        Text("Continue")
                                            .font(.system(size: 17, weight: .medium))
                                    }
                                }
                                .foregroundColor(canContinueWithEmail ? .black : Color(.secondaryLabel))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(canContinueWithEmail ? Color.white : Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .disabled(isEmailSigningIn || !canContinueWithEmail)
                            .padding(.horizontal, 32)
                            .padding(.top, 4)
                            if let error = emailSignInError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 32)
                            }
                        }
                        .padding(.top, 24)

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
        }
    }

    private func signInWithGoogle() async {
        isSigningIn = true
        do {
            try await auth.signInWithGoogle()
            await MainActor.run { displayToast(message: "Signed in successfully", type: .success) }
        } catch {
            await MainActor.run {
                let msg = error.localizedDescription
                displayToast(message: msg.isEmpty ? "Sign-in failed. Try again." : msg, type: .error)
            }
        }
        isSigningIn = false
    }

    private func signInWithApple() async {
        isSigningIn = true
        do {
            try await auth.signInWithApple()
            await MainActor.run { displayToast(message: "Signed in successfully", type: .success) }
        } catch {
            await MainActor.run {
                let msg = error.localizedDescription
                displayToast(message: msg.isEmpty ? "Sign-in failed. Try again." : msg, type: .error)
            }
        }
        isSigningIn = false
    }
    
    /// Try sign-in first; if invalid credentials, try sign-up. New accounts are sent to onboarding.
    private func continueWithEmail() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }
        isEmailSigningIn = true
        emailSignInError = nil
        do {
            try await auth.signInWithEmail(email: trimmedEmail, password: password)
            await MainActor.run {
                displayToast(message: "Signed in successfully", type: .success)
                email = ""
                password = ""
            }
        } catch {
            let msg = error.localizedDescription.lowercased()
            let isInvalidCredentials = msg.contains("invalid") || msg.contains("credentials") || msg.contains("invalid login")
            if isInvalidCredentials {
                do {
                    try await auth.signUpWithEmail(email: trimmedEmail, password: password)
                    await MainActor.run {
                        routeState.setRouteToOnboardingFromSignUp()
                        displayToast(message: "Account created", type: .success)
                        email = ""
                        password = ""
                    }
                } catch let signUpError {
                    await MainActor.run {
                        emailSignInError = signUpError.localizedDescription
                    }
                }
            } else {
                await MainActor.run {
                    emailSignInError = error.localizedDescription
                }
            }
        }
        isEmailSigningIn = false
    }

    private func displayToast(message: String, type: ToastType) {
        toastMessage = message
        toastType = type
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showToast = false }
        }
    }
}

// MARK: - Looping Lottie (auth page)

private struct LoopingLottieView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        let lottie = LottieAnimationView(name: name, bundle: .main)
        lottie.loopMode = .loop
        lottie.contentMode = .scaleAspectFit
        lottie.backgroundBehavior = .pauseAndRestore
        lottie.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(lottie)
        NSLayoutConstraint.activate([
            lottie.topAnchor.constraint(equalTo: container.topAnchor),
            lottie.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lottie.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lottie.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        lottie.play()
        context.coordinator.lottieView = lottie
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.lottieView?.contentMode = .scaleAspectFit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        weak var lottieView: LottieAnimationView?
    }
}
