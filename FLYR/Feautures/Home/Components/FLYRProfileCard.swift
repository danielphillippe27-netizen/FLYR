import SwiftUI
import Auth

struct FLYRProfileCard: View {
    let stats: UserStats?
    let profile: UserProfile?
    @StateObject private var auth = AuthManager.shared
    
    private var displayName: String {
        profile?.displayName ?? auth.user?.email?.components(separatedBy: "@").first?.capitalized ?? "User"
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
                        .font(.system(.title2, weight: .bold))
                        .foregroundColor(.text)
                    
                    // Streaks metric
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 14))
                        Text("\(dayStreak)")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundColor(.text)
                    }
                    
                    // Distance metric
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                            .foregroundColor(.accentDefault)
                            .font(.system(size: 14))
                        Text(formattedDistance)
                            .font(.system(.subheadline, weight: .medium))
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
                .font(.system(.headline, weight: .bold))
                .foregroundColor(.text)
            
            Text(label)
                .font(.system(.caption))
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

