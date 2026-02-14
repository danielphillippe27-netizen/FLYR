import SwiftUI
struct FLYRProfileCard: View {
    let stats: UserStats?
    let profile: UserProfile?
    @StateObject private var auth = AuthManager.shared
    
    private var displayName: String {
        profile?.displayName ?? (auth.user?.email).flatMap { $0.components(separatedBy: "@").first?.capitalized } ?? auth.user?.email ?? "User"
    }
    
    private var avatarUrl: String? {
        profile?.profileImageURL ?? profile?.avatarURL
    }
    
    private var weeklyDistance: Double {
        stats?.distance_walked ?? 0.0
    }
    
    private var formattedDistance: String {
        String(format: "%.1f km", weeklyDistance)
    }
    
    private var dayStreak: Int {
        stats?.day_streak ?? 0
    }
    
    var body: some View {
        HStack(spacing: 16) {
            ProfileAvatarView(
                avatarUrl: avatarUrl,
                name: displayName,
                size: 60
            )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(displayName)
                        .font(.flyrTitle2Bold)
                        .foregroundColor(.text)
                    
                    // Streaks metric
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.flyrPrimary)
                            .font(.system(size: 14))
                        Text("\(dayStreak)")
                            .font(.flyrSubheadline)
                            .foregroundColor(.text)
                    }
                    
                    // Distance metric
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.accentDefault)
                            .font(.system(size: 14))
                        Text(formattedDistance)
                            .font(.flyrSubheadline)
                            .foregroundColor(.text)
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .shadow(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

struct ProfileStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentDefault)
            
            Text(value)
                .font(AppFont.title(17))
                .foregroundColor(.text)
            
            Text(label)
                .font(.flyrCaption)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    FLYRProfileCard(stats: nil, profile: nil)
        .padding()
        .background(Color.bg)
}

