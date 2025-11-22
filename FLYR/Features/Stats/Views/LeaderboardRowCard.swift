import SwiftUI

struct LeaderboardRowCard: View {
    let entry: LeaderboardEntry
    let selectedSort: LeaderboardSortBy
    let currentUserID: UUID?
    
    var isCurrentUser: Bool {
        currentUserID == entry.user_id
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("\(entry.rank)")
                .font(.system(.body, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 32, alignment: .leading)
            
            // Name
            Text(entry.user_email)
                .font(.system(.body, weight: .semibold))
                .foregroundColor(isCurrentUser ? .red : .primary)
                .lineLimit(1)
            
            Spacer()
            
            // Value
            Text(entry.value(for: selectedSort))
                .font(.system(.body, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        LeaderboardRowCard(
            entry: LeaderboardEntry(
                id: UUID(),
                user_id: UUID(),
                user_email: "user@example.com",
                flyers: 100,
                conversations: 50,
                leads: 10,
                distance: 5.5,
                time_minutes: 120,
                day_streak: 5,
                best_streak: 10,
                rank: 1,
                updated_at: ""
            ),
            selectedSort: .flyers,
            currentUserID: nil
        )
        .background(Material.regular)
        .cornerRadius(20)
        
        LeaderboardRowCard(
            entry: LeaderboardEntry(
                id: UUID(),
                user_id: UUID(),
                user_email: "another@example.com",
                flyers: 80,
                conversations: 40,
                leads: 8,
                distance: 4.2,
                time_minutes: 90,
                day_streak: 3,
                best_streak: 7,
                rank: 2,
                updated_at: ""
            ),
            selectedSort: .flyers,
            currentUserID: nil
        )
        .background(Material.regular)
        .cornerRadius(20)
    }
    .padding()
}

