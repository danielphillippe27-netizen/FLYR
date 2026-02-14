import Foundation
import Combine
import Supabase
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var user: AppUser?
    @Published var errorMessage: String?

    private let client = SupabaseManager.shared.client

    private init() {}

    // MARK: - Session (Keychain + Supabase)

    /// Restore session from Keychain and set on Supabase client. Call on app launch.
    func loadSession() async {
        guard let pair = KeychainAuthStorage.loadSession() else {
            user = nil
            #if DEBUG
            print("🔍 No stored session in Keychain")
            #endif
            return
        }
        
        // Avoid calling setSession with incomplete token data.
        guard !pair.accessToken.isEmpty, !pair.refreshToken.isEmpty else {
            KeychainAuthStorage.clearAll()
            user = nil
            #if DEBUG
            print("🔍 Stored session is incomplete; cleared local auth state")
            #endif
            return
        }
        do {
            try await client.auth.setSession(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
            user = KeychainAuthStorage.loadAppUser()
            #if DEBUG
            print("🔍 Restored session: \(user?.email ?? "no email")")
            #endif
        } catch {
            KeychainAuthStorage.clearAll()
            user = nil
            #if DEBUG
            print("🔍 Session restore failed: \(error.localizedDescription)")
            #endif
        }
    }

    func signOut() async {
        KeychainAuthStorage.clearAll()
        do { try await client.auth.signOut() } catch {}
        user = nil
    }

    // MARK: - Google Sign-In

    /// Presents Google Sign-In, exchanges ID token for Supabase session, persists to Keychain.
    func signInWithGoogle() async throws {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String,
              !clientID.isEmpty,
              clientID != "YOUR_GOOGLE_IOS_CLIENT_ID" else {
            throw AuthError.missingGoogleClientID
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            throw AuthError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        let googleUser = result.user

        let idToken: String? = await withCheckedContinuation { cont in
            googleUser.refreshTokensIfNeeded { user, _ in
                cont.resume(returning: user?.idToken?.tokenString)
            }
        }

        guard let idToken = idToken else {
            throw AuthError.noIdToken
        }

        let credentials = OpenIDConnectCredentials(provider: .google, idToken: idToken, nonce: nil)
        let session = try await client.auth.signInWithIdToken(credentials: credentials)

        let appUser = AppUser(
            id: session.user.id,
            email: session.user.email ?? "",
            displayName: (session.user.userMetadata["full_name"] as? String)
                ?? (session.user.userMetadata["name"] as? String)
                ?? googleUser.profile?.name,
            photoURL: (session.user.userMetadata["avatar_url"] as? String).flatMap(URL.init)
                ?? googleUser.profile?.imageURL(withDimension: 96)
        )

        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken ?? "")
        KeychainAuthStorage.saveAuthProvider(.google)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }

    // MARK: - Apple Sign-In

    /// Presents Sign in with Apple, exchanges ID token for Supabase session, persists to Keychain.
    func signInWithApple() async throws {
        let rawNonce = randomNonceString()
        let hashedNonce = sha256(rawNonce)

        guard let windowScene = await UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            throw AuthError.noPresentingViewController
        }

        let (idToken, fullName): (String, PersonNameComponents?) = try await withCheckedThrowingContinuation { cont in
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let delegate = AppleSignInDelegate(window: window) { result in
                cont.resume(with: result)
            }
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
            objc_setAssociatedObject(controller, &AppleSignInDelegate.associatedKey, delegate, .OBJC_ASSOCIATION_RETAIN)
        }

        let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
        let session: Session
        do {
            session = try await client.auth.signInWithIdToken(credentials: credentials)
        } catch {
            throw mapSupabaseAuthError(error)
        }

        var displayName: String? = (session.user.userMetadata["full_name"] as? String)
            ?? (session.user.userMetadata["name"] as? String)
        if displayName == nil, let name = fullName {
            let given = name.givenName ?? ""
            let family = name.familyName ?? ""
            displayName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            if displayName?.isEmpty == true { displayName = nil }
        }

        let appUser = AppUser(
            id: session.user.id,
            email: session.user.email ?? "",
            displayName: displayName,
            photoURL: nil
        )

        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken ?? "")
        KeychainAuthStorage.saveAuthProvider(.apple)
        KeychainAuthStorage.saveAppleIdToken(idToken)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }
    
    /// Handle Sign in with Apple authorization from SignInWithAppleButton
    func handleAppleSignInAuthorization(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.noIdToken
        }
        
        let credentials = OpenIDConnectCredentials(provider: .apple, idToken: idToken)
        let session: Session
        do {
            session = try await client.auth.signInWithIdToken(credentials: credentials)
        } catch {
            throw mapSupabaseAuthError(error)
        }
        
        var displayName: String? = (session.user.userMetadata["full_name"] as? String)
            ?? (session.user.userMetadata["name"] as? String)
        if displayName == nil, let name = credential.fullName {
            let given = name.givenName ?? ""
            let family = name.familyName ?? ""
            displayName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            if displayName?.isEmpty == true { displayName = nil }
        }
        
        let appUser = AppUser(
            id: session.user.id,
            email: session.user.email ?? "",
            displayName: displayName,
            photoURL: nil
        )
        
        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken ?? "")
        KeychainAuthStorage.saveAuthProvider(.apple)
        KeychainAuthStorage.saveAppleIdToken(idToken)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func mapSupabaseAuthError(_ error: Error) -> Error {
        let message = error.localizedDescription.lowercased()
        if message.contains("audience") || message.contains("id token") {
            return AuthError.invalidAppleAudience
        }
        return error
    }
}

// MARK: - Apple Sign-In Delegate

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static var associatedKey: UInt8 = 0

    private let window: UIWindow
    private let continuation: (Result<(String, PersonNameComponents?), Error>) -> Void

    init(window: UIWindow, continuation: @escaping (Result<(String, PersonNameComponents?), Error>) -> Void) {
        self.window = window
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            continuation(.failure(AuthError.noIdToken))
            return
        }
        continuation(.success((idToken, credential.fullName)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            continuation(.failure(AuthError.appleSignInCancelled))
        } else if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError", nsError.code == 1000 {
            continuation(.failure(AuthError.appleSignInNotConfigured))
        } else {
            continuation(.failure(error))
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        window
    }
}

enum AuthError: LocalizedError {
    case missingGoogleClientID
    case noPresentingViewController
    case googleSignInCancelled
    case appleSignInCancelled
    case appleSignInNotConfigured
    case invalidAppleAudience
    case noIdToken

    var errorDescription: String? {
        switch self {
        case .missingGoogleClientID:
            return "Google Sign-In is not configured. Add GOOGLE_CLIENT_ID to Info.plist."
        case .noPresentingViewController:
            return "Could not present sign-in."
        case .googleSignInCancelled:
            return "Sign-in was cancelled."
        case .appleSignInCancelled:
            return "Sign in with Apple was cancelled."
        case .appleSignInNotConfigured:
            return "Sign in with Apple is not enabled. Add the capability in Xcode: Signing & Capabilities → + Capability → Sign in with Apple."
        case .invalidAppleAudience:
            return "Apple Sign-In is misconfigured: ID token audience does not match. In Supabase Apple provider, set the iOS Bundle ID to com.danielphillippe.FLYR."
        case .noIdToken:
            return "Could not get ID token."
        }
    }
}
