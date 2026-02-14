import SwiftUI

struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var isLoading: Bool = false
    var style: ButtonStyle = .primary
    var action: () -> Void
    
    enum ButtonStyle {
        case primary
        case success
    }
    
    private var effectiveEnabled: Bool { enabled && !isLoading }
    
    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                        Text("Creating…")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .modifier(ButtonStyleModifier(enabled: effectiveEnabled, style: style))
    }
}

struct ButtonStyleModifier: ViewModifier {
    let enabled: Bool
    let style: PrimaryButton.ButtonStyle
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundStyle(enabled ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var backgroundColor: Color {
        if !enabled {
            return Color(.systemGray5)
        }
        
        switch style {
        case .primary:
            return Color.accentColor
        case .success:
            return Color.green
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PrimaryButton(title: "Find 25 Nearby", enabled: true, style: .primary) {
            print("Find tapped")
        }
        
        PrimaryButton(title: "Found 12 Homes", enabled: true, style: .success) {
            print("Found tapped")
        }
        
        PrimaryButton(title: "Create Campaign", enabled: false) {
            print("Create tapped")
        }
    }
    .padding()
}
