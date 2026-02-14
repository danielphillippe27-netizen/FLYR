import Foundation
import GoogleSignIn

/// Provides a current ID token for backend auth (Apple or Google).
/// Used so the transcription backend can verify the user without shared secrets.
protocol IdentityTokenProvider {
    /// Returns a Bearer token string (e.g. Apple or Google ID token). Throws if not signed in or token unavailable/expired.
    func currentIdToken() async throws -> String
}

/// Uses Keychain (Apple token) and GIDSignIn (Google token) to supply the active ID token.
final class KeychainIdentityTokenProvider: IdentityTokenProvider {
    func currentIdToken() async throws -> String {
        guard let provider = KeychainAuthStorage.loadAuthProvider() else {
            throw TranscriptionError.notSignedIn
        }
        switch provider {
        case .apple:
            guard let token = KeychainAuthStorage.loadAppleIdToken(), !token.isEmpty else {
                throw TranscriptionError.idTokenUnavailable
            }
            return token
        case .google:
            let token: String? = await withCheckedContinuation { cont in
                GIDSignIn.sharedInstance.currentUser?.refreshTokensIfNeeded { user, _ in
                    cont.resume(returning: user?.idToken?.tokenString)
                }
            }
            guard let token = token, !token.isEmpty else {
                throw TranscriptionError.idTokenUnavailable
            }
            return token
        }
    }
}
