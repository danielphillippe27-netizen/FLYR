import SwiftUI

struct LeaderboardHeaderView: View {
    @Binding var selectedPeriod: TimeRange
    
    var body: some View {
        VStack(spacing: 4) {
            Text("FLYR Global Leaderboard")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.text)
            
            Text("— \(selectedPeriod.displayName)")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

#Preview {
    VStack {
        LeaderboardHeaderView(selectedPeriod: .constant(.monthly))
        LeaderboardHeaderView(selectedPeriod: .constant(.weekly))
        LeaderboardHeaderView(selectedPeriod: .constant(.daily))
        LeaderboardHeaderView(selectedPeriod: .constant(.allTime))
    }
    .padding()
    .background(Color.bg)
}

