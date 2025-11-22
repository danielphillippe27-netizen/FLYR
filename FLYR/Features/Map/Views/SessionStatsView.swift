import SwiftUI

struct SessionStatsView: View {
    @ObservedObject var manager = SessionManager.shared
    
    var body: some View {
        HStack(spacing: 12) {
            StatItem(
                title: "Distance",
                value: String(format: "%.1f km", manager.distanceMeters / 1000.0)
            )
            
            StatItem(
                title: "Time",
                value: formatTime(manager.elapsedTime)
            )
            
            StatItem(
                title: manager.goalType.displayName,
                value: "\(manager.goalAmount)"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(title)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

