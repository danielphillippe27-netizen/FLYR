import SwiftUI

/// Mission Control hero: active session (progress + Resume/End) or idle (Start Session / Browse Campaigns).
struct CampaignHeroCard: View {
    @ObservedObject var sessionManager: SessionManager
    var onStartSession: () -> Void
    var onResumeSession: () -> Void
    var onBrowseCampaigns: (() -> Void)?

    private let heroRed = Color(hex: "#FF4F4F")

    private var hasActiveBuildingSession: Bool {
        sessionManager.sessionId != nil && sessionManager.campaignId != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasActiveBuildingSession {
                activeSessionContent
            } else {
                idleContent
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
        )
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Active session

    private var activeSessionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session live")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.muted)
                Text("•")
                    .foregroundColor(.muted)
                Text(formatElapsed(sessionManager.elapsedTime))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(sessionManager.completedCount)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.text)
                Text("/ \(sessionManager.targetCount) doors")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.muted)
            }

            progressBar(progress: sessionManager.progressPercentage)

            HStack(spacing: 12) {
                Button {
                    onResumeSession()
                } label: {
                    Text("Resume Session")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.borderedProminent)
                .tint(heroRed)

                if sessionManager.isActive, !sessionManager.isPaused {
                    Button {
                        Task { await sessionManager.pause() }
                    } label: {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.muted)
                    }
                }
            }

            Button {
                Task { await sessionManager.stopBuildingSession() }
            } label: {
                Text("End Session")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.muted)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Idle (no active session)

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WEEKLY GOAL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)

            Text("Start a session to track doors and flyers.")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.muted)

            Button(action: onStartSession) {
                HStack {
                    Text("Start Session")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(heroRed)

            if let onBrowse = onBrowseCampaigns {
                Button(action: onBrowse) {
                    Text("Browse Campaigns")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.muted)
                }
            }
        }
    }

    // MARK: - Helpers

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 6)
                    .fill(heroRed)
                    .frame(width: max(0, geometry.size.width * progress), height: 12)
            }
        }
        .frame(height: 12)
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d elapsed", hours, minutes, seconds)
        }
        return String(format: "%d:%02d elapsed", minutes, seconds)
    }
}

#Preview("Idle") {
    CampaignHeroCard(
        sessionManager: SessionManager.shared,
        onStartSession: {},
        onResumeSession: {},
        onBrowseCampaigns: {}
    )
    .padding()
    .background(Color.bgSecondary)
}
