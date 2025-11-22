import SwiftUI

// MARK: - Card Component

struct Card<Content: View>: View {
    let content: Content
    let padding: CardPadding
    let hasShadow: Bool
    let hasAccentBorder: Bool
    let cornerRadius: CGFloat
    
    init(
        padding: CardPadding = .regular,
        hasShadow: Bool = true,
        hasAccentBorder: Bool = false,
        cornerRadius: CGFloat = 6,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.padding = padding
        self.hasShadow = hasShadow
        self.hasAccentBorder = hasAccentBorder
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .padding(padding.value)
            .background(Color.bg)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        hasAccentBorder ? Color.accent : Color.clear,
                        lineWidth: hasAccentBorder ? 1 : 0
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: hasShadow ? Color.black.opacity(0.05) : Color.clear,
                radius: hasShadow ? 4 : 0,
                x: 0,
                y: hasShadow ? 2 : 0
            )
    }
}

// MARK: - Card Padding

enum CardPadding {
    case compact
    case regular
    case large
    
    var value: EdgeInsets {
        switch self {
        case .compact:
            return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .regular:
            return EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        case .large:
            return EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Wrap content in a card with default styling
    func card(
        padding: CardPadding = .regular,
        hasShadow: Bool = true,
        hasAccentBorder: Bool = false,
        cornerRadius: CGFloat = 6
    ) -> some View {
        Card(
            padding: padding,
            hasShadow: hasShadow,
            hasAccentBorder: hasAccentBorder,
            cornerRadius: cornerRadius
        ) {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Campaign Title")
                    .subheading()
                    .foregroundColor(.text)
                
                Text("This is a campaign description that explains what the campaign is about.")
                    .bodyText()
                    .foregroundColor(.muted)
                
                HStack {
                    Text("1,234")
                        .subheading()
                        .foregroundColor(.accent)
                    Text("Total Flyers")
                        .captionText()
                        .foregroundColor(.muted)
                    Spacer()
                }
            }
        }
        
        Card(hasAccentBorder: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("With Accent Border")
                    .subheading()
                    .foregroundColor(.text)
                
                Text("This card has an accent border to highlight important content.")
                    .bodyText()
                    .foregroundColor(.muted)
            }
        }
        
        Card(padding: .compact, hasShadow: false) {
            HStack {
                Text("Compact, No Shadow")
                    .labelText()
                    .foregroundColor(.text)
                Spacer()
                Text("→")
                    .foregroundColor(.muted)
            }
        }
    }
    .padding()
    .background(Color.bgSecondary)
}

