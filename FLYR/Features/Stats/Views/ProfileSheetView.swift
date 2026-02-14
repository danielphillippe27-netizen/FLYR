import SwiftUI
import Supabase

struct ProfileSheetView: View {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var statsVM = StatsViewModel()
    @StateObject private var leaderboardVM = LeaderboardViewModel()
    @Environment(\.dismiss) var dismiss
    
    @State private var showAccountSettings = false
    @State private var showNotifications = false
    @State private var profile: UserProfile?
    
    // Placeholder data - can be enhanced with actual profile service
    @State private var brokerage: String = "Your Brokerage"
    @State private var city: String = "Your City"
    
    // Weekly goal - fixed for now, can be made configurable
    private let weeklyGoal = 20
    
    private var displayName: String {
        profile?.displayName ?? (auth.user?.email).flatMap { $0.components(separatedBy: "@").first?.capitalized } ?? auth.user?.email ?? "User"
    }
    
    private var profileImageURL: String? {
        profile?.profileImageURL
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Sticky "You" Card
                        if let userID = auth.user?.id {
                            YouStickyCard(
                                rank: leaderboardVM.currentUserRank,
                                totalUsers: leaderboardVM.users.count,
                                weeklyConversations: statsVM.stats?.conversations ?? 0,
                                weeklyGoal: weeklyGoal,
                                avatarUrl: profileImageURL,
                                userName: displayName
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                        
                        // Personal Info Section
                        personalInfoSection
                            .padding(.horizontal, 20)
                        
                        // Stats Summary
                        statsSummarySection
                            .padding(.horizontal, 20)
                        
                        // Streaks Section
                        streaksSection
                            .padding(.horizontal, 20)
                        
                        // XP & Level Section
                        xpLevelSection
                            .padding(.horizontal, 20)
                        
                        // Settings Section
                        settingsSection
                            .padding(.horizontal, 20)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if let userID = auth.user?.id {
                    await statsVM.loadStats(for: userID)
                    await leaderboardVM.load()
                    await loadProfile(userID: userID)
                }
            }
        }
    }
    
    // MARK: - Personal Info Section
    
    private var personalInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personal Info")
                .font(AppFont.title(20))
                .foregroundColor(.text)
            
            VStack(spacing: 16) {
                // Profile photo
                ProfileAvatarView(
                    avatarUrl: profileImageURL,
                    name: displayName,
                    size: 80
                )
                .overlay(
                    Button {
                        // TODO: Implement photo editing
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.accentDefault)
                            .clipShape(Circle())
                    }
                    .offset(x: 30, y: 30)
                )
                
                // Name
                Text(displayName)
                    .font(.flyrTitle2)
                    .foregroundColor(.text)
                
                // Brokerage
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.muted)
                    Text(brokerage)
                        .foregroundColor(.text)
                }
                .font(.flyrBody)
                
                // City
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.muted)
                    Text(city)
                        .foregroundColor(.text)
                }
                .font(.flyrBody)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.bgSecondary)
            )
        }
    }
    
    // MARK: - Stats Summary Section
    
    private var statsSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stats Summary")
                .font(AppFont.title(20))
                .foregroundColor(.text)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatSummaryCard(
                    title: "Total Flyers",
                    value: "\(statsVM.stats?.flyers ?? 0)",
                    icon: "doc.text.fill",
                    color: .blue
                )
                
                StatSummaryCard(
                    title: "Total Leads",
                    value: "\(statsVM.stats?.leads_created ?? 0)",
                    icon: "star.fill",
                    color: .yellow
                )
                
                StatSummaryCard(
                    title: "Total Conversations",
                    value: "\(statsVM.stats?.conversations ?? 0)",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .purple
                )
                
                StatSummaryCard(
                    title: "Total Distance",
                    value: String(format: "%.1f km", statsVM.stats?.distance_walked ?? 0.0),
                    icon: "figure.walk",
                    color: .green
                )
            }
        }
    }
    
    // MARK: - Streaks Section
    
    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Streaks")
                .font(AppFont.title(20))
                .foregroundColor(.text)
            
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.flyrPrimary)
                    .font(.flyrTitle2)
                
                Text("\(statsVM.stats?.day_streak ?? 0)-day knocking streak")
                    .font(AppFont.heading(17))
                    .foregroundColor(.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.bgSecondary)
            )
        }
    }
    
    // MARK: - XP & Level Section
    
    private var xpLevelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("XP & Level")
                .font(AppFont.title(20))
                .foregroundColor(.text)
            
            let xp = statsVM.stats?.xp ?? 0
            let level = calculateLevel(from: xp)
            let xpForNextLevel = xpForLevel(level + 1)
            let xpForCurrentLevel = xpForLevel(level)
            let progress = Double(xp - xpForCurrentLevel) / Double(xpForNextLevel - xpForCurrentLevel)
            
            VStack(spacing: 12) {
                HStack {
                    Text("Level \(level)")
                        .font(.flyrTitle2Bold)
                        .foregroundColor(.text)
                    
                    Spacer()
                    
                    Text(levelTitle(for: level))
                        .font(AppFont.heading(17))
                        .foregroundColor(.muted)
                }
                
                // XP Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(xp) XP")
                            .font(.flyrSubheadline)
                            .foregroundColor(.muted)
                        
                        Spacer()
                        
                        Text("\(xpForNextLevel) XP")
                            .font(.flyrSubheadline)
                            .foregroundColor(.muted)
                    }
                    
                    ProgressView(value: progress)
                        .tint(.accentDefault)
                        .scaleEffect(x: 1, y: 2, anchor: .center)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.bgSecondary)
            )
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(AppFont.title(20))
                .foregroundColor(.text)
            
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "person.fill",
                    title: "Account",
                    action: { showAccountSettings = true }
                )
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    action: { showNotifications = true }
                )
                
                Divider()
                    .padding(.leading, 44)
                
                SettingsRow(
                    icon: "arrow.right.square.fill",
                    title: "Log out",
                    isDestructive: true,
                    action: {
                        Task {
                            await auth.signOut()
                            dismiss()
                        }
                    }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.bgSecondary)
            )
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadProfile(userID: UUID) async {
        do {
            let result: UserProfile = try await SupabaseManager.shared.client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            
            await MainActor.run {
                self.profile = result
            }
        } catch {
            // Profile might not exist yet, that's okay
            print("⚠️ Could not load profile: \(error.localizedDescription)")
        }
    }
    
    private func calculateLevel(from xp: Int) -> Int {
        // Simple level calculation: level = sqrt(xp / 100)
        return max(1, Int(sqrt(Double(xp) / 100.0)))
    }
    
    private func xpForLevel(_ level: Int) -> Int {
        return level * level * 100
    }
    
    private func levelTitle(for level: Int) -> String {
        switch level {
        case 1...3: return "Rookie"
        case 4...6: return "Field Assassin"
        case 7...10: return "Door Master"
        case 11...15: return "Lead Hunter"
        case 16...20: return "Conversation King"
        default: return "Legend"
        }
    }
}

// MARK: - Stat Summary Card

struct StatSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.flyrTitle3)
                .foregroundColor(color)
            
            Text(value)
                .font(.flyrTitle2Bold)
                .foregroundColor(.text)
            
            Text(title)
                .font(.flyrCaption)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary)
        )
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isDestructive ? .error : .muted)
                    .frame(width: 24)
                
                Text(title)
                    .font(.flyrBody)
                    .foregroundColor(isDestructive ? .error : .text)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.muted)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ProfileSheetView()
}

