import SwiftUI

extension Font {
    // MARK: - Typography Scale (Inter)
    
    /// Heading - 28pt semibold (weight 600)
    static let heading = AppFont.heading(28)
    
    /// Subheading - 20pt semibold (weight 600)
    static let subheading = AppFont.heading(20)
    
    /// Body - 16pt regular (weight 400)
    static let body = AppFont.body(16)
    
    /// Label/Button - 16pt medium (weight 500)
    static let label = AppFont.label(16)
    
    /// Caption - 13pt regular (weight 400)
    static let caption = AppFont.body(13)
    
    // MARK: - SwiftUI text styles (Inter) – use these for .largeTitle, .headline, etc.
    static let flyrLargeTitle = AppFont.title(34)
    static let flyrTitle = AppFont.title(28)
    static let flyrTitle2 = AppFont.heading(22)
    static let flyrTitle3 = AppFont.heading(20)
    static let flyrHeadline = AppFont.heading(17)
    static let flyrBody = AppFont.body(17)
    static let flyrCallout = AppFont.body(16)
    static let flyrSubheadline = AppFont.label(15)
    static let flyrFootnote = AppFont.body(13)
    static let flyrCaption = AppFont.body(12)
    static let flyrCaption2 = AppFont.body(11)
    /// Title2 with bold weight
    static let flyrTitle2Bold = AppFont.title(22)

    /// Inter font for arbitrary size/weight (replaces .font(.system(size:weight:))).
    static func flyrSystem(size: CGFloat, weight: Font.Weight) -> Font {
        switch weight {
        case .bold: return AppFont.title(size)
        case .semibold: return AppFont.heading(size)
        case .medium: return AppFont.label(size)
        case .light, .regular, .ultraLight, .thin: return AppFont.body(size)
        default: return AppFont.body(size)
        }
    }

    // MARK: - Legacy Support (Deprecated) – now Inter
    @available(*, deprecated, message: "Use .heading instead")
    static let heading1 = AppFont.title(32)

    @available(*, deprecated, message: "Use .heading instead")
    static let heading2 = AppFont.title(28)

    @available(*, deprecated, message: "Use .subheading instead")
    static let heading3 = AppFont.heading(24)

    @available(*, deprecated, message: "Use .subheading instead")
    static let heading4 = AppFont.heading(20)

    @available(*, deprecated, message: "Use .body instead")
    static let bodyLarge = AppFont.body(18)

    @available(*, deprecated, message: "Use .body instead")
    static let bodyRegular = AppFont.body(16)

    @available(*, deprecated, message: "Use .caption instead")
    static let bodySmall = AppFont.body(14)

    @available(*, deprecated, message: "Use .label instead")
    static let labelLarge = AppFont.label(16)

    @available(*, deprecated, message: "Use .label instead")
    static let labelRegular = AppFont.label(14)

    @available(*, deprecated, message: "Use .caption instead")
    static let labelSmall = AppFont.label(12)

    @available(*, deprecated, message: "Use .caption instead")
    static let captionSmall = AppFont.body(10)
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
        self.font(.flyrCaption)
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

