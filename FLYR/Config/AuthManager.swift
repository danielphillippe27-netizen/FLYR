import Foundation
import Combine
import Supabase
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    @Published var user: User?
    @Published var errorMessage: String?

    let client = SupabaseManager.shared.client
    private init() {}

    func loadSession() async {
        do { 
            user = try await client.auth.session.user
            print("🔍 Found existing session: \(user?.email ?? "No email")")
        }
        catch { 
            user = nil
            print("🔍 No existing session found: \(error.localizedDescription)")
        }
    }


    func signOut() async {
        do { try await client.auth.signOut() } catch {}
        user = nil
    }
    
    func handleAuthURL(_ url: URL) async {
        do {
            let session = try await client.auth.session(from: url)
            user = session.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Email/Password Authentication
    
    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        user = session.user
    }
    
    func signUp(email: String, password: String) async throws {
        let session = try await client.auth.signUp(email: email, password: password)
        user = session.user
    }
    
    // MARK: - Apple Sign-In
    
    func signInWithApple() async throws {
        let session = try await client.auth.signInWithOAuth(
            provider: .apple,
            redirectTo: URL(string: "flyr://auth-callback")
        )
        
        // Update user state with the new session
        await MainActor.run {
            user = session.user
        }
    }
}
