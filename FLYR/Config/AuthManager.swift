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
    @Published private(set) var hasPasswordRecoveryRestoreSession = false

    private let client = SupabaseManager.shared.client
    private var passwordRecoveryRestoreSession: (accessToken: String, refreshToken: String)?
    private var passwordRecoveryRestoreUser: AppUser?
    private var isUsingPasswordRecoverySession = false
    
    private struct ProfileSnapshot: Decodable {
        let fullName: String?
        let avatarURL: String?
        
        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case avatarURL = "avatar_url"
        }
    }

    private init() {}
    
    private func metadataString(_ metadata: [String: AnyJSON], key: String) -> String? {
        guard let value = metadata[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
    
    private func metadataDisplayName(_ metadata: [String: AnyJSON]) -> String? {
        metadataString(metadata, key: "full_name") ?? metadataString(metadata, key: "name")
    }
    
    private func metadataAvatarURL(_ metadata: [String: AnyJSON]) -> URL? {
        guard let raw = metadataString(metadata, key: "avatar_url") else { return nil }
        return URL(string: raw)
    }

    // MARK: - Session (Keychain + Supabase)

    /// Restore session from Keychain and set on Supabase client. Call on app launch.
    func loadSession() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            user = nil
            #if DEBUG
            print("🔍 DEBUG: Skipping Keychain session restore on Simulator")
            #endif
            return
        }
        #endif

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
            let session = try await client.auth.setSession(accessToken: pair.accessToken, refreshToken: pair.refreshToken)
            let cachedUser = KeychainAuthStorage.loadAppUser()
            let restoredUser = restoredAppUser(from: session.user, cachedUser: cachedUser)
            user = restoredUser
            KeychainAuthStorage.saveAppUser(restoredUser)
            await refreshAppUserFromProfile(userId: session.user.id, fallback: restoredUser)
            #if DEBUG
            print("🔍 auth_session_restored user_id=\(session.user.id.uuidString) email=\(restoredUser.email)")
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
        WorkspaceContext.shared.clear()
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

        guard let windowScene = UIApplication.shared.connectedScenes
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
            displayName: metadataDisplayName(session.user.userMetadata)
                ?? googleUser.profile?.name,
            photoURL: metadataAvatarURL(session.user.userMetadata)
                ?? googleUser.profile?.imageURL(withDimension: 96)
        )

        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
        KeychainAuthStorage.saveAuthProvider(.google)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }

    // MARK: - Apple Sign-In

    /// Presents Sign in with Apple, exchanges ID token for Supabase session, persists to Keychain.
    func signInWithApple() async throws {
        let rawNonce = randomNonceString()
        let hashedNonce = sha256(rawNonce)

        guard let windowScene = UIApplication.shared.connectedScenes
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

        var displayName: String? = metadataDisplayName(session.user.userMetadata)
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

        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
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
        
        var displayName: String? = metadataDisplayName(session.user.userMetadata)
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
        
        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
        KeychainAuthStorage.saveAuthProvider(.apple)
        KeychainAuthStorage.saveAppleIdToken(idToken)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }

    // MARK: - Email / Password Sign-In (e.g. App Store review account)

    /// Sign in with email and password via Supabase Auth. Persists session to Keychain like Apple/Google.
    /// TODO: If sign-in fails with provider disabled or invalid credentials, enable Email provider in
    /// Supabase Dashboard → Authentication → Providers → Email.
    func signInWithEmail(email: String, password: String) async throws {
        let session: Session
        do {
            session = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw error
        }

        let displayName = metadataDisplayName(session.user.userMetadata)

        let appUser = AppUser(
            id: session.user.id,
            email: session.user.email ?? "",
            displayName: displayName,
            photoURL: metadataAvatarURL(session.user.userMetadata)
        )

        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
        KeychainAuthStorage.saveAuthProvider(.email)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }

    /// Sign up with email and password via Supabase Auth. Persists session to Keychain when returned (e.g. when email confirmation is disabled).
    func signUpWithEmail(email: String, password: String) async throws {
        let response = try await client.auth.signUp(email: email, password: password)
        guard let session = response.session else {
            // Email confirmation required; no session yet.
            throw AuthError.emailConfirmationRequired
        }
        let displayName = metadataDisplayName(session.user.userMetadata)
        let appUser = AppUser(
            id: session.user.id,
            email: session.user.email ?? "",
            displayName: displayName,
            photoURL: metadataAvatarURL(session.user.userMetadata)
        )
        KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
        KeychainAuthStorage.saveAuthProvider(.email)
        KeychainAuthStorage.saveAppUser(appUser)
        user = appUser
    }

    func sendPasswordResetEmail(email: String) async throws {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw AuthError.invalidPasswordRecoveryEmail
        }
        try await client.auth.resetPasswordForEmail(
            trimmedEmail,
            redirectTo: Config.passwordRecoveryRedirectURL
        )
    }

    func activatePasswordRecovery(from url: URL) async throws -> String? {
        if let deepLinkError = passwordRecoveryErrorMessage(from: url) {
            throw AuthError.passwordRecoveryLinkInvalid(message: deepLinkError)
        }

        capturePasswordRecoveryRestoreStateIfNeeded()

        do {
            if let code = authCallbackValue(named: "code", in: url) {
                let session = try await client.auth.exchangeCodeForSession(authCode: code)
                applyPasswordRecoverySession(session)
                return session.user.email
            }

            if let accessToken = authCallbackValue(named: "access_token", in: url),
               let refreshToken = authCallbackValue(named: "refresh_token", in: url) {
                let session = try await client.auth.setSession(
                    accessToken: accessToken,
                    refreshToken: refreshToken
                )
                applyPasswordRecoverySession(session)
                return session.user.email
            }

            if let tokenHash = authCallbackValue(named: "token_hash", in: url),
               let recoveryType = passwordRecoveryOTPType(from: url) {
                let response = try await client.auth.verifyOTP(
                    tokenHash: tokenHash,
                    type: recoveryType
                )
                if case let .session(session) = response {
                    applyPasswordRecoverySession(session)
                    return session.user.email
                }
            }

            if authCallbackValue(named: "type", in: url)?.lowercased() == "recovery" {
                let session = try await client.auth.session(from: url)
                applyPasswordRecoverySession(session)
                return session.user.email
            }
        } catch {
            throw AuthError.passwordRecoveryLinkInvalid(message: error.localizedDescription)
        }

        throw AuthError.passwordRecoveryLinkInvalid(
            message: "This reset link is missing recovery details. Request a new email and try again."
        )
    }

    func updatePasswordFromRecovery(newPassword: String) async throws {
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            throw AuthError.invalidNewPassword
        }
        do {
            try await client.auth.update(user: UserAttributes(password: trimmedPassword))
        } catch {
            throw AuthError.passwordUpdateFailed(message: error.localizedDescription)
        }
    }

    func finishPasswordRecoveryFlow() async {
        guard isUsingPasswordRecoverySession else { return }

        do {
            try await client.auth.signOut()
        } catch {
            #if DEBUG
            print("⚠️ Password recovery sign out failed: \(error.localizedDescription)")
            #endif
        }

        if let restoreSession = passwordRecoveryRestoreSession {
            do {
                let session = try await client.auth.setSession(
                    accessToken: restoreSession.accessToken,
                    refreshToken: restoreSession.refreshToken
                )
                let restoredUser = restoredAppUser(from: session.user, cachedUser: passwordRecoveryRestoreUser)
                user = restoredUser
                KeychainAuthStorage.saveAppUser(restoredUser)
                await refreshAppUserFromProfile(userId: session.user.id, fallback: restoredUser)
            } catch {
                user = nil
                KeychainAuthStorage.clearAll()
                #if DEBUG
                print("⚠️ Failed to restore pre-recovery session: \(error.localizedDescription)")
                #endif
            }
        } else {
            user = nil
        }

        passwordRecoveryRestoreSession = nil
        passwordRecoveryRestoreUser = nil
        hasPasswordRecoveryRestoreSession = false
        isUsingPasswordRecoverySession = false
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
    
    private func restoredAppUser(from authUser: User, cachedUser: AppUser?) -> AppUser {
        let matchingCachedUser = cachedUser?.id == authUser.id ? cachedUser : nil
        let email = authUser.email ?? matchingCachedUser?.email ?? ""
        let displayName = metadataDisplayName(authUser.userMetadata) ?? matchingCachedUser?.displayName
        let photoURL = metadataAvatarURL(authUser.userMetadata) ?? matchingCachedUser?.photoURL

        return AppUser(
            id: authUser.id,
            email: email,
            displayName: displayName,
            photoURL: photoURL
        )
    }
    
    private func refreshAppUserFromProfile(userId: UUID, fallback: AppUser) async {
        do {
            let profile: ProfileSnapshot = try await client
                .from("profiles")
                .select("full_name,avatar_url")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            let profileName = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAvatarURL = profile.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let avatarURL = (trimmedAvatarURL?.isEmpty == false)
                ? URL(string: trimmedAvatarURL!)
                : nil

            let hydratedUser = AppUser(
                id: fallback.id,
                email: fallback.email,
                displayName: (profileName?.isEmpty == false) ? profileName : fallback.displayName,
                photoURL: avatarURL ?? fallback.photoURL
            )

            user = hydratedUser
            KeychainAuthStorage.saveAppUser(hydratedUser)
            #if DEBUG
            print("🔍 auth_profile_hydrated user_id=\(userId.uuidString)")
            #endif
        } catch let error as PostgrestError {
            if error.code != "PGRST116" {
                #if DEBUG
                print("⚠️ auth_profile_hydration_failed user_id=\(userId.uuidString) error=\(error)")
                #endif
            }
        } catch {
            #if DEBUG
            print("⚠️ auth_profile_hydration_failed user_id=\(userId.uuidString) error=\(error.localizedDescription)")
            #endif
        }
    }

    private func capturePasswordRecoveryRestoreStateIfNeeded() {
        guard !isUsingPasswordRecoverySession else { return }
        passwordRecoveryRestoreSession = KeychainAuthStorage.loadSession()
        passwordRecoveryRestoreUser = KeychainAuthStorage.loadAppUser()
        hasPasswordRecoveryRestoreSession = passwordRecoveryRestoreSession != nil
    }

    private func applyPasswordRecoverySession(_ session: Session) {
        let recoveryUser = restoredAppUser(from: session.user, cachedUser: nil)
        user = recoveryUser
        isUsingPasswordRecoverySession = true
    }

    private func authCallbackValue(named name: String, in url: URL) -> String? {
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value,
           !value.isEmpty {
            return value
        }

        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
              !fragment.isEmpty else {
            return nil
        }

        let pairs = fragment.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1) }
        for pair in pairs where pair.count == 2 {
            if String(pair[0]).removingPercentEncoding == name {
                let rawValue = String(pair[1])
                return rawValue.removingPercentEncoding ?? rawValue
            }
        }
        return nil
    }

    private func passwordRecoveryOTPType(from url: URL) -> EmailOTPType? {
        guard let rawType = authCallbackValue(named: "type", in: url)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawType.isEmpty else {
            return .recovery
        }

        return EmailOTPType(rawValue: rawType)
    }

    private func passwordRecoveryErrorMessage(from url: URL) -> String? {
        let description = authCallbackValue(named: "error_description", in: url)
        let message = authCallbackValue(named: "error", in: url)
        let resolved = description ?? message
        guard let resolved,
              !resolved.isEmpty else {
            return nil
        }
        return resolved.replacingOccurrences(of: "+", with: " ")
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
    case emailConfirmationRequired
    case invalidPasswordRecoveryEmail
    case passwordRecoveryLinkInvalid(message: String)
    case invalidNewPassword
    case passwordUpdateFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidPasswordRecoveryEmail:
            return "Enter the email address tied to your FLYR account."
        case .passwordRecoveryLinkInvalid(let message):
            return message
        case .invalidNewPassword:
            return "Enter a new password before submitting."
        case .passwordUpdateFailed(let message):
            return message.isEmpty ? "We couldn't update your password. Try requesting a new link." : message
        case .emailConfirmationRequired:
            return "Check your email to confirm your account."
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
