import SwiftUI

// MARK: - Form Section Component

public struct FormSection<Content: View>: View {
    let title: String
    let content: Content
    
    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.primary)
            VStack(spacing: 10) { 
                content 
            }
        }
    }
}

// MARK: - Form Style Extensions

public extension View {
    /// Apple-style form container padding
    func formContainerPadding() -> some View {
        padding(.horizontal, 20).padding(.top, 8)
    }
    
    /// Apple-style form field styling
    func formField() -> some View {
        font(.system(size: 16))
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    /// Primary CTA button styling
    func primaryCTA(enabled: Bool = true) -> some View {
        self
            .font(.system(size: 17, weight: .semibold))
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(enabled ? Color.accentColor : Color(.systemGray5))
            .foregroundStyle(enabled ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
