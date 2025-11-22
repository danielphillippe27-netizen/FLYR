import SwiftUI

extension Font {
    // MARK: - Typography Scale (SF Pro)
    
    /// Heading - 28pt semibold (weight 600)
    static let heading = Font.system(size: 28, weight: .semibold)
    
    /// Subheading - 20pt semibold (weight 600)
    static let subheading = Font.system(size: 20, weight: .semibold)
    
    /// Body - 16pt regular (weight 400)
    static let body = Font.system(size: 16, weight: .regular)
    
    /// Label/Button - 16pt medium (weight 500)
    static let label = Font.system(size: 16, weight: .medium)
    
    /// Caption - 13pt regular (weight 400)
    static let caption = Font.system(size: 13, weight: .regular)
    
    // MARK: - Legacy Support (Deprecated)
    
    @available(*, deprecated, message: "Use .heading instead")
    static let heading1 = Font.system(size: 32, weight: .bold)
    
    @available(*, deprecated, message: "Use .heading instead")
    static let heading2 = Font.system(size: 28, weight: .bold)
    
    @available(*, deprecated, message: "Use .subheading instead")
    static let heading3 = Font.system(size: 24, weight: .semibold)
    
    @available(*, deprecated, message: "Use .subheading instead")
    static let heading4 = Font.system(size: 20, weight: .semibold)
    
    @available(*, deprecated, message: "Use .body instead")
    static let bodyLarge = Font.system(size: 18, weight: .regular)
    
    @available(*, deprecated, message: "Use .body instead")
    static let bodyRegular = Font.system(size: 16, weight: .regular)
    
    @available(*, deprecated, message: "Use .caption instead")
    static let bodySmall = Font.system(size: 14, weight: .regular)
    
    @available(*, deprecated, message: "Use .label instead")
    static let labelLarge = Font.system(size: 16, weight: .medium)
    
    @available(*, deprecated, message: "Use .label instead")
    static let labelRegular = Font.system(size: 14, weight: .medium)
    
    @available(*, deprecated, message: "Use .caption instead")
    static let labelSmall = Font.system(size: 12, weight: .medium)
    
    @available(*, deprecated, message: "Use .caption instead")
    static let captionSmall = Font.system(size: 10, weight: .regular)
}

// MARK: - View Extensions

extension View {
    /// Apply heading typography
    func heading() -> some View {
        self.font(.heading)
    }
    
    /// Apply subheading typography
    func subheading() -> some View {
        self.font(.subheading)
    }
    
    /// Apply body typography
    func bodyText() -> some View {
        self.font(.body)
    }
    
    /// Apply label typography
    func labelText() -> some View {
        self.font(.label)
    }
    
    /// Apply caption typography
    func captionText() -> some View {
        self.font(.caption)
    }
    
    // MARK: - Legacy Support (Deprecated)
    
    @available(*, deprecated, message: "Use .heading() instead")
    func heading1() -> some View {
        self.font(.heading1)
    }
    
    @available(*, deprecated, message: "Use .heading() instead")
    func heading2() -> some View {
        self.font(.heading2)
    }
    
    @available(*, deprecated, message: "Use .subheading() instead")
    func heading3() -> some View {
        self.font(.heading3)
    }
}

