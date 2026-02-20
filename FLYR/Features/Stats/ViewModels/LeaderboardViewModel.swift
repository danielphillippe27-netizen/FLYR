import SwiftUI
import Combine
import Supabase

@MainActor
final class LeaderboardViewModel: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSort: LeaderboardSortBy = .flyers
    @Published var isRealTimeEnabled = false
    @Published var currentUserRank: Int?
    
    // New API properties
    @Published var users: [LeaderboardUser] = []
    @Published var selectedMetric: String = "conversations"
    @Published var selectedTimeframe: String = "weekly"
    
    // V3 Properties
    @Published var selectedTab: Int = 0 // 0 = Leaderboard, 1 = You
    @Published var metric: MetricType = .flyers
    @Published var timeRange: TimeRange = .monthly
    /// Global filter: All or My team (team/workspace name when present).
    @Published var scope: LeaderboardScope = .all

    private let leaderboardService = LeaderboardService.shared
    private let supabase = SupabaseManager.shared.client
    private var cancellables = Set<AnyCancellable>()

    /// Fetched from profiles table so "You" row shows real name, not email.
    @Published var currentUserProfile: UserProfile?
    /// Resolved signed URL for profile image (profile_images bucket) so "You" row shows photo.
    @Published var currentUserProfileImageURL: String?
    
    func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            // Check authentication - leaderboard requires authenticated users
            // But we can still try to load it even if not authenticated (might work with anon key)
            // The error will be more descriptive if auth is the issue
            
            entries = try await leaderboardService.fetchLeaderboard(sortBy: selectedSort)
            
            // Get current user rank if logged in
            if let user = AuthManager.shared.user {
                let userID = user.id
                currentUserRank = try await leaderboardService.getUserRank(
                    userID: userID,
                    sortBy: selectedSort
                )
            }
        } catch {
            // Provide more detailed error information
            var errorDetails = "Failed to load leaderboard"
            
            // Check for specific error types
            let errorString = String(describing: error)
            let errorDescription = error.localizedDescription
            
            // Check for authentication errors
            if errorString.contains("401") || errorString.contains("Unauthorized") || 
               errorString.contains("not authenticated") || errorString.contains("JWT") {
                errorDetails = "Please sign in to view the leaderboard"
            } else if errorString.contains("404") || errorString.contains("not found") ||
                      errorString.contains("function") || errorString.contains("get_leaderboard") {
                errorDetails = "Leaderboard service unavailable. Please try again later."
            } else if errorString.contains("network") || errorString.contains("connection") ||
                      errorString.contains("timeout") {
                errorDetails = "Network error. Please check your connection and try again."
            } else if !errorDescription.isEmpty && errorDescription != errorString {
                errorDetails = "Failed to load leaderboard: \(errorDescription)"
            } else {
                errorDetails = "Failed to load leaderboard: \(errorDescription)"
            }
            
            errorMessage = errorDetails
            
            // Enhanced logging for debugging
            print("❌ Error loading leaderboard:")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(errorDescription)")
            print("   Error string: \(errorString)")
            if let nsError = error as NSError? {
                print("   NSError domain: \(nsError.domain)")
                print("   NSError code: \(nsError.code)")
                print("   NSError userInfo: \(nsError.userInfo)")
            }
        }
    }
    
    func enableRealTimeUpdates() async {
        guard !isRealTimeEnabled else { return }
        
        isRealTimeEnabled = true
        
        do {
            try await leaderboardService.subscribeToLeaderboardUpdates(
                sortBy: selectedSort
            ) { [weak self] updatedEntries in
                Task { @MainActor in
                    self?.entries = updatedEntries
                }
            }
        } catch {
            errorMessage = "Failed to enable real-time updates: \(error.localizedDescription)"
            isRealTimeEnabled = false
            print("❌ Error subscribing to leaderboard: \(error)")
        }
    }
    
    func disableRealTimeUpdates() async {
        guard isRealTimeEnabled else { return }
        
        await leaderboardService.unsubscribeFromLeaderboard()
        isRealTimeEnabled = false
    }
    
    func changeSort(_ newSort: LeaderboardSortBy) async {
        selectedSort = newSort
        await disableRealTimeUpdates()
        await loadLeaderboard()
        if isRealTimeEnabled {
            await enableRealTimeUpdates()
        }
    }
    
    // Cleanup method to be called when view disappears
    func cleanup() {
        Task { @MainActor [weak self] in
            await self?.disableRealTimeUpdates()
        }
    }
    
    // MARK: - New API Methods
    
    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let result = try await leaderboardService.fetchLeaderboard(
                metric: selectedMetric,
                timeframe: selectedTimeframe
            )
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.users = result
            }
            
            // Update current user rank if logged in
            if let user = AuthManager.shared.user {
                let userIDString = user.id.uuidString
                currentUserRank = result.firstIndex(where: { $0.id == userIDString }).map { $0 + 1 }
            }
        } catch {
            var errorDetails = "Failed to load leaderboard"
            
            let errorString = String(describing: error)
            let errorDescription = error.localizedDescription
            
            if errorString.contains("401") || errorString.contains("Unauthorized") || 
               errorString.contains("not authenticated") || errorString.contains("JWT") {
                errorDetails = "Please sign in to view the leaderboard"
            } else if errorString.contains("404") || errorString.contains("not found") ||
                      errorString.contains("function") || errorString.contains("get_leaderboard") {
                errorDetails = "Leaderboard service unavailable. Please try again later."
            } else if errorString.contains("network") || errorString.contains("connection") ||
                      errorString.contains("timeout") {
                errorDetails = "Network error. Please check your connection and try again."
            } else if !errorDescription.isEmpty && errorDescription != errorString {
                errorDetails = "Failed to load leaderboard: \(errorDescription)"
            } else {
                errorDetails = "Failed to load leaderboard: \(errorDescription)"
            }
            
            errorMessage = errorDetails
            
            print("❌ Error loading leaderboard:")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(errorDescription)")
            print("   Error string: \(errorString)")
        }
    }
    
    // MARK: - V3 API Methods
    
    func fetchLeaderboard() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let result = try await leaderboardService.fetchLeaderboard(
                metric: metric.rawValue,
                timeframe: timeRange.rawValue
            )
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.users = result
            }
            
            // Update current user rank and load profile for "You" row (real name, not email)
            if let user = AuthManager.shared.user {
                let userIDString = user.id.uuidString
                currentUserRank = result.firstIndex(where: { $0.id == userIDString }).map { $0 + 1 }
                await loadCurrentUserProfile(userID: user.id)
            } else {
                currentUserProfile = nil
            }
        } catch {
            // Ignore cancellation (view disappeared or metric/timeframe changed); don't show or log error
            let nsError = error as NSError
            let isCancelled = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
                || error.localizedDescription.lowercased().contains("cancelled")
            if isCancelled { return }

            var errorDetails = "Failed to load leaderboard"

            let errorString = String(describing: error)
            let errorDescription = error.localizedDescription

            if errorString.contains("401") || errorString.contains("Unauthorized") ||
               errorString.contains("not authenticated") || errorString.contains("JWT") {
                errorDetails = "Please sign in to view the leaderboard"
            } else if errorString.contains("404") || errorString.contains("not found") ||
                      errorString.contains("function") || errorString.contains("get_leaderboard") {
                errorDetails = "Leaderboard service unavailable. Please try again later."
            } else if errorString.contains("network") || errorString.contains("connection") ||
                      errorString.contains("timeout") {
                errorDetails = "Network error. Please check your connection and try again."
            } else if !errorDescription.isEmpty && errorDescription != errorString {
                errorDetails = "Failed to load leaderboard: \(errorDescription)"
            } else {
                errorDetails = "Failed to load leaderboard: \(errorDescription)"
            }

            errorMessage = errorDetails

            print("❌ Error loading leaderboard:")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(errorDescription)")
            print("   Error string: \(errorString)")
        }
    }

    /// Load current user's profile so leaderboard "You" row shows name and photo from profiles.
    func loadCurrentUserProfile(userID: UUID) async {
        do {
            let result: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            currentUserProfile = result
            // Resolve profile image to signed URL so avatar can load (bucket is private)
            if let path = result.profileImageURL, !path.isEmpty {
                do {
                    let signedURL = try await supabase.storage
                        .from("profile_images")
                        .createSignedURL(path: path, expiresIn: 60 * 60 * 24 * 7)
                    currentUserProfileImageURL = signedURL.absoluteString
                } catch {
                    currentUserProfileImageURL = nil
                }
            } else {
                currentUserProfileImageURL = nil
            }
        } catch {
            currentUserProfile = nil
            currentUserProfileImageURL = nil
        }
    }
}

