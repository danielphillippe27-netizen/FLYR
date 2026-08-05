import SwiftUI

/// A reusable badge component with capsule styling
struct Badge: View {
    var text: String
    var backgroundColor: Color = Color.green.opacity(0.25)
    var foregroundColor: Color = .green
    
    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        Badge(text: "Flyer")
        Badge(text: "Door Knock")
        Badge(text: "Event")
    }
    .padding()
    .background(Color.bgSecondary)
}

