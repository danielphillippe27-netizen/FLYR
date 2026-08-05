import SwiftUI

/// Transparent checkered background (PNG-style) for share screens. Efficient: drawn once per layout.
struct CheckeredBackground: View {
    var squareSize: CGFloat = 24
    var color1: Color = .gray.opacity(0.35)
    var color2: Color = .gray.opacity(0.2)

    var body: some View {
        Canvas { context, size in
            let nx = Int(ceil(size.width / squareSize)) + 1
            let ny = Int(ceil(size.height / squareSize)) + 1
            for i in 0..<nx {
                for j in 0..<ny {
                    let rect = CGRect(
                        x: CGFloat(i) * squareSize,
                        y: CGFloat(j) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    let color = (i + j) % 2 == 0 ? color1 : color2
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    CheckeredBackground(squareSize: 24, color1: Color.gray.opacity(0.35), color2: Color.gray.opacity(0.2))
        .overlay(Text("Preview").foregroundColor(.white))
}
