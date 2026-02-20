import SwiftUI

/// Full-screen list of user sessions (activities).
struct ActivityView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var sessions: [SessionRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading activity...")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SessionActivityFeed(sessions: sessions, maxItems: sessions.count)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bg)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadSessions()
        }
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        guard let userId = auth.user?.id else {
            errorMessage = "Please sign in to view activity"
            isLoading = false
            return
        }
        errorMessage = nil
        do {
            sessions = try await SessionsAPI.shared.fetchUserSessions(userId: userId, limit: 100)
        } catch {
            errorMessage = "Failed to load activity"
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
}
