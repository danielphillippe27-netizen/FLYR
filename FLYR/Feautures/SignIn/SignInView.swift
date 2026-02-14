import SwiftUI
import UIKit
import AuthenticationServices
import Lottie

struct SignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var auth = AuthManager.shared
    @State private var isSigningIn = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .success

    enum ToastType {
        case success, error
    }

    /// On white/light background use black buttons with white text for contrast.
    private var isLightBackground: Bool { colorScheme == .light }
    private var signInButtonBackground: Color { isLightBackground ? .black : Color.white }
    private var signInButtonForeground: Color { isLightBackground ? .white : .black }
    private var signInProgressTint: Color { isLightBackground ? .white : .black }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 60)

                        VStack(spacing: 8) {
                            LoopingLottieView(name: "splash")
                                .frame(width: 180, height: 120)
                                .clipped()
                        }
                        .padding(.top, 40)

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
                        .disabled(isSigningIn)
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                        // Official Sign in with Apple Button
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: { result in
                                Task {
                                    await handleAppleSignInResult(result)
                                }
                            }
                        )
                        .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .disabled(isSigningIn)
                        .padding(.horizontal, 32)
                        .padding(.top, 12)

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
    
    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        switch result {
        case .success(let authorization):
            do {
                try await auth.handleAppleSignInAuthorization(authorization)
                await MainActor.run { displayToast(message: "Signed in successfully", type: .success) }
            } catch {
                await MainActor.run {
                    let msg = error.localizedDescription
                    displayToast(message: msg.isEmpty ? "Sign-in failed. Try again." : msg, type: .error)
                }
            }
        case .failure(let error):
            await MainActor.run {
                displayToast(message: error.localizedDescription, type: .error)
            }
        }
        isSigningIn = false
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
