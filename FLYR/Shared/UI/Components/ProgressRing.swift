import SwiftUI

// MARK: - Progress Ring Component

struct ProgressRing<Content: View>: View {
    let progress: Double // 0.0 to 1.0
    let size: CGFloat
    let strokeWidth: CGFloat
    let content: Content
    
    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    init(
        progress: Double,
        size: CGFloat = 60,
        strokeWidth: CGFloat = 6,
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
                .stroke(Color.border, lineWidth: strokeWidth)
                .frame(width: size, height: size)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    Color.accent,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90)) // Start from top
                .animation(
                    reduceMotion ? .reducedMotion : .flyrSpring,
                    value: animatedProgress
                )
            
            // Center content
            content
        }
        .onAppear {
            animatedProgress = reduceMotion ? progress : 0
            if !reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    animatedProgress = progress
                }
            }
        }
        .onChange(of: progress) { _, newValue in
            animatedProgress = reduceMotion ? newValue : animatedProgress
            if !reduceMotion {
                withAnimation(.flyrSpring) {
                    animatedProgress = newValue
                }
            }
        }
    }
}

// MARK: - Convenience Initializers

extension ProgressRing where Content == EmptyView {
    init(progress: Double, size: CGFloat = 60, strokeWidth: CGFloat = 6) {
        self.init(progress: progress, size: size, strokeWidth: strokeWidth) {
            EmptyView()
        }
    }
}

extension ProgressRing where Content == Text {
    init(
        progress: Double,
        size: CGFloat = 60,
        strokeWidth: CGFloat = 6,
        text: String
    ) {
        self.init(progress: progress, size: size, strokeWidth: strokeWidth) {
            Text(text)
                .font(.system(size: size * 0.25, weight: .semibold))
                .foregroundColor(.text)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Wrap content in a progress ring
    func progressRing(
        progress: Double,
        size: CGFloat = 60,
        strokeWidth: CGFloat = 6
    ) -> some View {
        ProgressRing(progress: progress, size: size, strokeWidth: strokeWidth) {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            ProgressRing(progress: 0.75, text: "75%")
            
            ProgressRing(progress: 0.5, size: 80, strokeWidth: 8) {
                Image(systemName: "checkmark")
                    .font(.title2)
                    .foregroundColor(.success)
            }
            
            ProgressRing(progress: 0.25, size: 100, strokeWidth: 10) {
                VStack(spacing: 4) {
                    Text("1,234")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.text)
                    Text("Scans")
                        .font(.caption)
                        .foregroundColor(.muted)
                }
            }
        }
        
        HStack(spacing: 16) {
            ProgressRing(progress: 0.0, text: "0%")
            ProgressRing(progress: 0.25, text: "25%")
            ProgressRing(progress: 0.5, text: "50%")
            ProgressRing(progress: 0.75, text: "75%")
            ProgressRing(progress: 1.0, text: "100%")
        }
    }
    .padding()
    .background(Color.bgSecondary)
}

