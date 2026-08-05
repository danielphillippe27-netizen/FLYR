import SwiftUI

/// Single stat tile for the horizontal Quick Stats row: icon, number, micro-label. Tappable to go to Stats.
struct QuickStatButton: View {
    let icon: String
    let value: String
    let label: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.accentDefault)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.text)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.muted)
            }
            .frame(width: 100, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack(spacing: 12) {
        QuickStatButton(icon: "flame.fill", value: "12", label: "Streak")
        QuickStatButton(icon: "figure.walk", value: "5.2", label: "km")
        QuickStatButton(icon: "trophy.fill", value: "3rd", label: "Rank")
    }
    .padding()
    .background(Color.bgSecondary)
}
