import SwiftUI

// MARK: - Gradient Progress Ring Component

struct GradientProgressRing<Content: View>: View {
    let progress: Double // 0.0 to 1.0
    let size: CGFloat
    let strokeWidth: CGFloat
    let content: Content
    
    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    // FLYR gradient colors: red → orange
    private let gradientColors = [
        Color(red: 1.0, green: 0.23, blue: 0.19), // FLYR red #FF3B30
        Color(red: 1.0, green: 0.62, blue: 0.04)  // Orange #FF9F0A
    ]
    
    init(
        progress: Double,
        size: CGFloat = 80,
        strokeWidth: CGFloat = 8,
        @ViewBuilder content: () -> Content
    ) {
        self.progress = max(0, min(1, progress)) // Clamp between 0 and 1
        self.size = size
        self.strokeWidth = strokeWidth
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.border.opacity(0.3), lineWidth: strokeWidth)
                .frame(width: size, height: size)
            
            // Progress circle with gradient
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradientColors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90)) // Start from top
                .shadow(color: gradientColors[0].opacity(0.3), radius: 4, x: 0, y: 2)
                .animation(
                    reduceMotion ? .reducedMotion : .spring(response: 0.6, dampingFraction: 0.8),
                    value: animatedProgress
                )
            
            // Center content
            content
        }
        .onAppear {
            animatedProgress = reduceMotion ? progress : 0
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        animatedProgress = progress
                    }
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            if !reduceMotion {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    animatedProgress = newValue
                }
            } else {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Convenience Initializers

extension GradientProgressRing where Content == EmptyView {
    init(progress: Double, size: CGFloat = 80, strokeWidth: CGFloat = 8) {
        self.init(progress: progress, size: size, strokeWidth: strokeWidth) {
            EmptyView()
        }
    }
}

extension GradientProgressRing where Content == Text {
    init(
        progress: Double,
        size: CGFloat = 80,
        strokeWidth: CGFloat = 8,
        text: String
    ) {
        self.init(progress: progress, size: size, strokeWidth: strokeWidth) {
            Text(text)
                .font(.flyrSystem(size: size * 0.2, weight: .semibold))
                .foregroundColor(.text)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        GradientProgressRing(progress: 0.65, size: 100, strokeWidth: 10, text: "65%")
        
        GradientProgressRing(progress: 0.3, size: 80, strokeWidth: 8) {
            VStack(spacing: 4) {
                Text("17")
                    .font(.flyrTitle2)
                    .fontWeight(.bold)
                    .foregroundColor(.text)
                Text("conversations")
                    .font(.flyrCaption)
                    .foregroundColor(.muted)
            }
        }
    }
    .padding()
    .background(Color.bg)
}


