import SwiftUI

/// Persistent top HUD for active building session: target/completed/remaining, elapsed time, distance, pace, controls
struct SessionHUDCard: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                StatColumn(title: "Target", value: "\(sessionManager.targetCount)")
                StatColumn(title: "Done", value: "\(sessionManager.completedCount)", color: .green)
                StatColumn(title: "Left", value: "\(sessionManager.remainingCount)", color: .flyrPrimary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: max(0, geometry.size.width * sessionManager.progressPercentage))
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                StatColumn(title: "Time", value: formatTime(sessionManager.elapsedTime))
                StatColumn(title: "Distance", value: String(format: "%.2f km", sessionManager.distanceMeters / 1000))
                StatColumn(title: "Pace", value: String(format: "%.1f/hr", pacePerHour()))
            }

            HStack(spacing: 12) {
                if sessionManager.isActive, !sessionManager.isPaused {
                    Button {
                        Task { await sessionManager.pause() }
                    } label: {
                        Label("Pause", systemImage: "pause.circle.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await sessionManager.stopBuildingSession() }
                    } label: {
                        Label("Finish", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else if sessionManager.isActive, sessionManager.isPaused {
                    Button {
                        Task { await sessionManager.resume() }
                    } label: {
                        Label("Resume", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let error = sessionManager.locationError {
                Text(error)
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.horizontal)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func pacePerHour() -> Double {
        guard sessionManager.elapsedTime > 0 else { return 0 }
        let hours = sessionManager.elapsedTime / 3600
        return hours > 0 ? Double(sessionManager.completedCount) / hours : 0
    }
}

struct StatColumn: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.flyrCaption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.flyrHeadline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}
