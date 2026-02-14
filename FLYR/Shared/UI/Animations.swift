import SwiftUI

// MARK: - Animation System

extension Animation {
    /// Micro-interactions: buttons, toggles, small state changes
    /// Duration: 120-200ms, easeInOut
    static let microInteraction = Animation.easeInOut(duration: 0.15)
    
    /// Screen transitions: push, modal, sheet presentations
    /// Duration: 240-320ms, spring with low bounciness
    static let transition = Animation.spring(response: 0.32, dampingFraction: 0.82, blendDuration: 0)
    
    /// Stagger delay for list items
    /// 20-40ms between items to imply order without feeling slow
    static let staggerDelay: Double = 0.03
    
    /// FLYR spring animation - equivalent to React Native Reanimated
    /// withSpring(1, { damping: 18, stiffness: 220 })
    static let flyrSpring = Animation.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    
    /// Reduced motion animation - instant for accessibility
    static let reducedMotion = Animation.linear(duration: 0)
}

// MARK: - Animation Utilities

extension View {
    /// Apply animation with reduced motion support
    func flyrAnimation(_ animation: Animation = .microInteraction) -> some View {
        self.animation(animation, value: UUID())
    }
    
    /// Apply staggered animation for list items
    func staggeredAnimation(delay: Double = 0) -> some View {
        self.animation(
            .flyrSpring.delay(delay),
            value: UUID()
        )
    }
    
    /// Check if reduced motion is enabled
    var isReducedMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}

// MARK: - Animation Environment

struct AnimationEnvironmentKey: EnvironmentKey {
    static let defaultValue: Animation = .microInteraction
}

extension EnvironmentValues {
    var flyrAnimation: Animation {
        get { self[AnimationEnvironmentKey.self] }
        set { self[AnimationEnvironmentKey.self] = newValue }
    }
}

// MARK: - View Extensions for Common Animations

extension View {
    /// Animate scale on press with haptic feedback
    func pressAnimation() -> some View {
        self.scaleEffect(1.0)
            .onTapGesture {
                HapticManager.lightImpact()
            }
    }
    
    /// Animate opacity change
    func fadeAnimation() -> some View {
        self.animation(.microInteraction, value: UUID())
    }
    
    /// Animate slide in from bottom
    func slideInAnimation(delay: Double = 0) -> some View {
        self.animation(.flyrSpring.delay(delay), value: UUID())
    }
    
    /// Apply scale effect on tap for button interactions
    func scaleEffectOnTap() -> some View {
        self.buttonStyle(ScaleOnTapButtonStyle())
    }
}

// MARK: - Button Styles

struct ScaleOnTapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

