import SwiftUI

/// Session tools bar: Pause/Resume only. Stats and Finish are in the map overlay; Next targets removed for now.
struct BottomActionBar: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var showingTargets: Bool
    @Binding var statsExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            if sessionManager.isActive, !sessionManager.isPaused {
                Button {
                    Task { await sessionManager.pause() }
                } label: {
                    Label("Pause", systemImage: "pause.circle.fill")
                        .font(.flyrSubheadline)
                }
                .buttonStyle(.bordered)
            } else if sessionManager.isActive, sessionManager.isPaused {
                Button {
                    Task { await sessionManager.resume() }
                } label: {
                    Label("Resume", systemImage: "play.circle.fill")
                        .font(.flyrSubheadline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
    }
}
