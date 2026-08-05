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

    @State private var pressed = false
    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        ZStack {
            PitchYawRollEmblem()
                .frame(width: 34, height: 34)
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
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            let strokeWidth = min(size.width, size.height) * 0.085
            let lineStyle = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
            let color = Color.white

            let globeRadius = min(size.width, size.height) * 0.37
            let globeRect = CGRect(
                x: center.x - globeRadius,
                y: center.y - globeRadius,
                width: globeRadius * 2,
                height: globeRadius * 2
            )
            context.stroke(Path(ellipseIn: globeRect), with: .color(color), style: lineStyle)

            var globeLines = Path()
            globeLines.addEllipse(in: CGRect(
                x: center.x - globeRadius * 0.48,
                y: center.y - globeRadius,
                width: globeRadius * 0.96,
                height: globeRadius * 2
            ))
            globeLines.move(to: CGPoint(x: center.x - globeRadius, y: center.y))
            globeLines.addLine(to: CGPoint(x: center.x + globeRadius, y: center.y))
            globeLines.addEllipse(in: CGRect(
                x: center.x - globeRadius * 0.94,
                y: center.y - globeRadius * 0.43,
                width: globeRadius * 1.88,
                height: globeRadius * 0.86
            ))
            context.stroke(globeLines, with: .color(color), style: lineStyle)
        }
    }
}
