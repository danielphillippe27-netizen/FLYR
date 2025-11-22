import SwiftUI
import Supabase
import Combine

struct FLYRHomeView: View {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var viewModel = FLYRHomeViewModel()
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Profile Card
                    if let userId = auth.user?.id {
                        FLYRProfileCard(
                            stats: viewModel.stats,
                            profile: viewModel.profile
                        )
                    }
                    
                    // Activity Feed
                    SessionActivityFeed(sessions: viewModel.sessions)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.bgSecondary)
            .task {
                if let userId = auth.user?.id {
                    await viewModel.loadData(userId: userId)
                }
            }
        }
    }
}

@MainActor
class FLYRHomeViewModel: ObservableObject {
    @Published var sessions: [SessionRecord] = []
    @Published var stats: UserStats?
    @Published var profile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let sessionsAPI = SessionsAPI.shared
    private let statsService = StatsService.shared
    private let client = SupabaseManager.shared.client
    
    func loadData(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        
        async let sessionsTask = loadSessions(userId: userId)
        async let statsTask = loadStats(userId: userId)
        async let profileTask = loadProfile(userId: userId)
        
        await sessionsTask
        await statsTask
        await profileTask
    }
    
    private func loadSessions(userId: UUID) async {
        do {
            sessions = try await sessionsAPI.fetchUserSessions(userId: userId, limit: 10)
        } catch {
            print("❌ [FLYRHome] Failed to load sessions: \(error)")
            errorMessage = "Failed to load sessions"
        }
    }
    
    private func loadStats(userId: UUID) async {
        do {
            stats = try await statsService.fetchUserStats(userID: userId)
        } catch {
            print("❌ [FLYRHome] Failed to load stats: \(error)")
        }
    }
    
    private func loadProfile(userId: UUID) async {
        do {
            let result: UserProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            await MainActor.run {
                self.profile = result
            }
        } catch {
            // Profile might not exist yet, that's okay
            print("⚠️ [FLYRHome] Could not load profile: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        FLYRHomeView()
    }
}

