import SwiftUI

struct LeaderboardErrorView: View {
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.flyrPrimary)
                .font(.system(size: 48))
            
            Text("Can't Load Leaderboard")
                .font(.flyrHeadline)
            
            Text("The data couldn't be loaded. Please try again.")
                .font(.flyrSubheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .frame(height: 44)
            .cornerRadius(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LeaderboardErrorView {
        print("Retry tapped")
    }
    .padding()
}



