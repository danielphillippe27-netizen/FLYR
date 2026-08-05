import SwiftUI

/// A horizontal progress bar component
struct ProgressBar: View {
    let value: Double // 0.0 to 1.0
    let height: CGFloat
    let trackColor: Color
    let fillColor: Color
    
    init(
        value: Double,
        height: CGFloat = 8,
        trackColor: Color = Color.black.opacity(0.2),
        fillColor: Color = Color.black.opacity(0.9)
    ) {
        self.value = max(0.0, min(1.0, value)) // Clamp to 0-1
        self.height = height
        self.trackColor = trackColor
        self.fillColor = fillColor
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(trackColor)
                    .frame(height: height)
                
                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * value, height: height)
                    .animation(.easeInOut(duration: 0.3), value: value)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ProgressBar(value: 0.0)
        ProgressBar(value: 0.25)
        ProgressBar(value: 0.5)
        ProgressBar(value: 0.75)
        ProgressBar(value: 1.0)
        
        // Custom colors
        ProgressBar(
            value: 0.6,
            height: 12,
            trackColor: .gray.opacity(0.3),
            fillColor: .blue
        )
    }
    .padding()
}
