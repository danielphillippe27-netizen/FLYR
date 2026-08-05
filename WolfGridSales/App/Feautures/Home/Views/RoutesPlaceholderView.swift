import SwiftUI

/// Placeholder for Routes: prompts user to create routes on desktop.
struct RoutesPlaceholderView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.secondary)
                .opacity(0.6)
            VStack(spacing: 12) {
                Text("No routes yet")
                    .font(.flyrHeadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text("Go on desktop to create a route")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        RoutesPlaceholderView()
    }
}
