import SwiftUI

// MARK: - Primary Button Style
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Color.accent)
            .cornerRadius(6) // 4-6pt radii per spec
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(reduceMotion ? .reducedMotion : .microInteraction, value: configuration.isPressed)
            .onTapGesture {
                HapticManager.lightImpact()
            }
    }
}

// MARK: - Secondary Button Style
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label)
            .foregroundColor(.accent)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accent, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(reduceMotion ? .reducedMotion : .microInteraction, value: configuration.isPressed)
            .onTapGesture {
                HapticManager.lightImpact()
            }
    }
}

// MARK: - Destructive Button Style
struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label)
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Color.error)
            .cornerRadius(6)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(reduceMotion ? .reducedMotion : .microInteraction, value: configuration.isPressed)
            .onTapGesture {
                HapticManager.lightImpact()
            }
    }
}

// MARK: - Ghost Button Style (minimal, text-only)
struct GhostButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.label)
            .foregroundColor(.accent)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(reduceMotion ? .reducedMotion : .microInteraction, value: configuration.isPressed)
            .onTapGesture {
                HapticManager.lightImpact()
            }
    }
}

// MARK: - View Extensions
extension View {
    /// Primary button with accent background
    func primaryButton() -> some View {
        self.buttonStyle(PrimaryButtonStyle())
    }
    
    /// Secondary button with accent border
    func secondaryButton() -> some View {
        self.buttonStyle(SecondaryButtonStyle())
    }
    
    /// Destructive button with error background
    func destructiveButton() -> some View {
        self.buttonStyle(DestructiveButtonStyle())
    }
    
    /// Ghost button - minimal text-only style
    func ghostButton() -> some View {
        self.buttonStyle(GhostButtonStyle())
    }
}

