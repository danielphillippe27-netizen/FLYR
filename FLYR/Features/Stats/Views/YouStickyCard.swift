import SwiftUI

struct YouStickyCard: View {
    let rank: Int?
    let totalUsers: Int
    let weeklyConversations: Int
    let weeklyGoal: Int
    let avatarUrl: String?
    let userName: String
    
    private var progress: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1.0, Double(weeklyConversations) / Double(weeklyGoal))
    }
    
    private var remaining: Int {
        max(0, weeklyGoal - weeklyConversations)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Avatar
            ProfileAvatarView(
                avatarUrl: avatarUrl,
                name: userName,
                size: 60
            )
            
            // Rank
            if let rank = rank {
                Text("Your Rank: #\(rank) of \(totalUsers)")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundColor(.text)
            }
            
            // Weekly metric
            Text("\(weeklyConversations) conversations this week")
                .font(.system(.body, weight: .medium))
                .foregroundColor(.muted)
            
            // Progress ring
            GradientProgressRing(
                progress: progress,
                size: 100,
                strokeWidth: 10
            ) {
                VStack(spacing: 4) {
                    Text("\(weeklyConversations)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.text)
                    Text("of \(weeklyGoal)")
                        .font(.caption)
                        .foregroundColor(.muted)
                }
            }
            
            // Goal tracker
            if remaining > 0 {
                Text("\(remaining) left to hit your weekly goal.")
                    .font(.system(.subheadline))
                    .foregroundColor(.muted)
            } else {
                Text("🎉 You've reached your weekly goal!")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(.accentDefault)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        )
    }
}

#Preview {
    VStack {
        YouStickyCard(
            rank: 12,
            totalUsers: 248,
            weeklyConversations: 17,
            weeklyGoal: 20,
            avatarUrl: nil,
            userName: "John Doe"
        )
        .padding()
    }
    .background(Color.bg)
}


