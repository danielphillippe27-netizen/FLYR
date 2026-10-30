import SwiftUI
import Foundation

struct MapPitchBearingDragEvent: Equatable {
    let id = UUID()
    let dragAmount: CGSize
}

struct FlyrMapPitchBearingControl: View {
    let onCameraDrag: (CGSize) -> Void
    var size: CGFloat = 52
    var height: CGFloat = 44
    var foregroundColor: Color = .white

    @State private var pressed = false
    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            PitchYawRollEmblem(color: foregroundColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
                .opacity(pressed ? 0.72 : 1)
                .scaleEffect(pressed ? 0.94 : 1)
                .shadow(color: .black.opacity(0.34), radius: 3, x: 0, y: 1)
        }
        .frame(width: size, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed {
                        pressed = true
                    }
                    let delta = CGSize(
                        width: value.translation.width - lastDragTranslation.width,
                        height: value.translation.height - lastDragTranslation.height
                    )
                    lastDragTranslation = value.translation
                    guard abs(delta.width) > 0.01 || abs(delta.height) > 0.01 else { return }
                    onCameraDrag(delta)
                }
                .onEnded { _ in
                    pressed = false
                    lastDragTranslation = .zero
                }
        )
        .accessibilityLabel("Drag to rotate or tilt map")
        .accessibilityHint("Drag horizontally to rotate the map and vertically to tilt it")
    }
}

private struct PitchYawRollEmblem: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let strokeWidth = min(size.width, size.height) * 0.085
            let lineStyle = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)

            // Two perpendicular rings: one facing the viewer and one lying flat.
            let radius = min(size.width, size.height) * 0.34
            var rings = Path()
            rings.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            rings.addEllipse(in: CGRect(
                x: center.x - radius * 1.3,
                y: center.y - radius * 0.36,
                width: radius * 2.6,
                height: radius * 0.72
            ))
            context.stroke(rings, with: .color(color), style: lineStyle)
        }
    }
}
