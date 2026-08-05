import SwiftUI
import CoreGraphics
import CoreLocation

enum MapCameraDragCalibration {
    static let minimumPitch: CGFloat = 0
    static let maximumPitch: CGFloat = 75
    static let bearingDegreesPerPoint: CGFloat = 0.45
    static let pitchDegreesPerPoint: CGFloat = 0.35

    static func bearing(base: CLLocationDirection, translation: CGSize) -> CLLocationDirection {
        CLLocationDirection(base + Double(translation.width * bearingDegreesPerPoint))
    }

    static func pitch(base: CGFloat, translation: CGSize) -> CGFloat {
        let proposed = base - translation.height * pitchDegreesPerPoint
        return min(max(proposed, minimumPitch), maximumPitch)
    }
}

struct MapCameraPitchBearingControl: View {
    var size: CGFloat = 52
    var onDragBegan: () -> Void = {}
    var onDragChanged: (CGSize) -> Void
    var onDragEnded: () -> Void = {}

    @State private var hasStartedDrag = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red)
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 3)

            MapCameraPitchBearingGlyph()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !hasStartedDrag {
                        hasStartedDrag = true
                        HapticManager.light()
                        onDragBegan()
                    }
                    onDragChanged(value.translation)
                }
                .onEnded { _ in
                    hasStartedDrag = false
                    onDragEnded()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Drag to rotate or tilt map")
    }
}

private struct MapCameraPitchBearingGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.44

        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius * 0.42,
            width: radius * 2,
            height: radius * 0.84
        ))

        path.move(to: CGPoint(x: center.x, y: center.y - radius * 1.03))
        path.addLine(to: CGPoint(x: center.x, y: center.y + radius * 1.03))

        path.move(to: CGPoint(x: center.x - radius * 0.74, y: center.y + radius * 0.42))
        path.addQuadCurve(
            to: CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.46),
            control: CGPoint(x: center.x - radius * 0.06, y: center.y - radius * 0.1)
        )

        path.move(to: CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.46))
        path.addLine(to: CGPoint(x: center.x + radius * 0.52, y: center.y - radius * 0.5))
        path.move(to: CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.46))
        path.addLine(to: CGPoint(x: center.x + radius * 0.68, y: center.y - radius * 0.22))

        path.move(to: CGPoint(x: center.x - radius * 0.95, y: center.y - radius * 0.05))
        path.addLine(to: CGPoint(x: center.x - radius * 1.18, y: center.y + radius * 0.1))
        path.move(to: CGPoint(x: center.x - radius * 0.95, y: center.y - radius * 0.05))
        path.addLine(to: CGPoint(x: center.x - radius * 1.18, y: center.y - radius * 0.2))

        return path
    }
}
