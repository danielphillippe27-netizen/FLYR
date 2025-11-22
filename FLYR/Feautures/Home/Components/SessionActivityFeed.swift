import SwiftUI

struct SessionActivityFeed: View {
    let sessions: [SessionRecord]
    @StateObject private var auth = AuthManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sessions.isEmpty {
                emptyStateView
            } else {
                ForEach(sessions, id: \.id) { session in
                    SessionRowView(session: session)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 48))
                .foregroundColor(.muted)
            
            Text("No sessions yet")
                .font(.headline)
                .foregroundColor(.text)
            
            Text("Start a session to see your activity here")
                .font(.subheadline)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
}

struct SessionRowView: View {
    let session: SessionRecord
    
    private var duration: TimeInterval {
        session.end_time.timeIntervalSince(session.start_time)
    }
    
    private var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    private var formattedDistance: String {
        let km = session.distance_meters / 1000.0
        if km >= 1.0 {
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", session.distance_meters)
        }
    }
    
    private var goalTypeDisplay: String {
        session.goal_type == "flyers" ? "Flyers" : "Door Knocks"
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentDefault.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: session.goal_type == "flyers" ? "paperplane.fill" : "hand.raised.fill")
                    .foregroundColor(.accentDefault)
                    .font(.system(size: 20))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(goalTypeDisplay)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundColor(.text)
                    
                    Spacer()
                    
                    Text(formattedDistance)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundColor(.muted)
                }
                
                HStack {
                    Text("Goal: \(session.goal_amount)")
                        .font(.system(.subheadline))
                        .foregroundColor(.muted)
                    
                    Text("•")
                        .foregroundColor(.muted)
                    
                    Text(formattedDuration)
                        .font(.system(.subheadline))
                        .foregroundColor(.muted)
                }
                
                Text(dateFormatter.string(from: session.start_time))
                    .font(.system(.caption))
                    .foregroundColor(.muted)
            }
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

#Preview {
    SessionActivityFeed(sessions: [])
        .padding()
        .background(Color.bg)
}

