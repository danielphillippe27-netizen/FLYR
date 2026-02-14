import SwiftUI

private let barAccent = Color(hex: "#FF4F4F")

struct CompactStatRow: View {
    let icon: String
    let label: String
    let progress: Double
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(barAccent)
                .frame(width: 24, height: 20, alignment: .center)

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.text)

            Spacer(minLength: 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barAccent)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 6)

            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(.text)
                .lineLimit(1)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .frame(minHeight: 52)
    }
}

#Preview {
    VStack(spacing: 8) {
        CompactStatRow(icon: "door.left.hand.open", label: "Doors", progress: 0.6, value: "124")
        CompactStatRow(icon: "doc.text", label: "Flyers", progress: 0.45, value: "89")
    }
    .padding()
    .background(Color.bg)
}
