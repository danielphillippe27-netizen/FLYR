import SwiftUI

/// Modal sheet showing Homes legend and map gesture hints. Shown when user taps the Info button on the Map tab.
struct MapGestureInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let homeLegendItems: [(color: Color, label: String)] = [
        (Color(red: 239/255, green: 68/255, blue: 68/255), "Untouched"),
        (Color(red: 34/255, green: 197/255, blue: 94/255), "Touched"),
        (Color(red: 59/255, green: 130/255, blue: 246/255), "Conversations"),
        (Color(red: 234/255, green: 179/255, blue: 8/255), "QR Scanned")
    ]

    private let gestures: [(icon: String, text: String)] = [
        ("hand.draw", "Pan: Drag with one finger"),
        ("hand.pinch", "Zoom: Pinch with two fingers"),
        ("arrow.up.and.down", "Tilt: Slide up with two fingers"),
        ("arrow.triangle.2.circlepath", "Rotate: Twist with two fingers")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Map Gestures")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.flyrTitle2)
                        .foregroundStyle(.secondary)
                }
            }

            // Map gestures (matches sheet title)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(gestures, id: \.text) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)
                        Text(item.text)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                }
            }

            Divider()

            // Homes legend (colour meaning for map markers) – vertical, same size as gestures
            VStack(alignment: .leading, spacing: 14) {
                Text("Homes")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                ForEach(Array(homeLegendItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 18, height: 18)
                            .frame(width: 28, alignment: .center)
                        Text(item.label)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    MapGestureInfoSheet()
}
