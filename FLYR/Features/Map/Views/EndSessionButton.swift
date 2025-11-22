import SwiftUI

struct EndSessionButton: View {
    var body: some View {
        Button(action: { 
            SessionManager.shared.stop()
        }) {
            Text("End Session")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color.red)
                .clipShape(Capsule())
                .shadow(radius: 5)
        }
        .padding(.bottom, 40)
    }
}


