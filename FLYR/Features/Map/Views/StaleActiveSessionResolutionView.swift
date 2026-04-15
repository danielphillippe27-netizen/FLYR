import SwiftUI

/// Shown when an active session is restored after a long time (forgot to end). User must resume live tracking or end and save so leaderboard rollups can count the session.
struct StaleActiveSessionResolutionView: View {
    @ObservedObject var sessionManager: SessionManager

    private var elapsedText: String {
        let t = sessionManager.elapsedTime
        let h = Int(t) / 3600
        let m = Int(t) / 60 % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.flyrPrimary)

                Text("Session still open")
                    .font(.flyrHeadline)
                    .foregroundStyle(Color.text)
                    .multilineTextAlignment(.center)

                Text(
                    "This session started \(elapsedText) ago and was never ended. Resume to keep tracking, or end it now so your doors count on the leaderboard."
                )
                .font(.flyrSubheadline)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

                VStack(spacing: 12) {
                    Button {
                        Task { await sessionManager.resumeStaleRestoredSession() }
                    } label: {
                        Text("Resume session")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.flyrPrimary)

                    Button {
                        Task { await sessionManager.stopBuildingSession() }
                    } label: {
                        Text("End & save session")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.bg)
            )
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    StaleActiveSessionResolutionView(sessionManager: SessionManager.shared)
}
