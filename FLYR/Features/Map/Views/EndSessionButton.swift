import SwiftUI

struct EndSessionButton: View {
    @ObservedObject private var sessionManager = SessionManager.shared

    var body: some View {
        Button(action: {
            sessionManager.stop()
        }) {
            Text(sessionManager.isEndingSession ? "Ending..." : "End Session")
                .font(.flyrHeadline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.red)
                .clipShape(Capsule())
                .shadow(radius: 5)
        }
        .disabled(sessionManager.isEndingSession)
        .opacity(sessionManager.isEndingSession ? 0.7 : 1)
        .padding(.bottom, 40)
    }
}

