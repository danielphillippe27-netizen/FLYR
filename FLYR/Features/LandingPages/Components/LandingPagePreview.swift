import SwiftUI

/// Preview engine that switches between templates based on template_id
public struct LandingPagePreview: View {
    let page: LandingPageData
    let branding: LandingPageBranding?
    
    public init(page: LandingPageData, branding: LandingPageBranding? = nil) {
        self.page = page
        self.branding = branding
    }
    
    public var body: some View {
        Group {
            switch page.template {
            case .minimalBlack:
                LandingPageMinimalBlack(page: page, branding: branding)
            case .luxeCard:
                LandingPageLuxeCard(page: page, branding: branding)
            case .spotlight:
                LandingPageSpotlight(page: page, branding: branding)
            }
        }
    }
}

/// Preview wrapper for editor with real-time updates
public struct LandingPageEditorPreview: View {
    @Binding var pageData: LandingPageData
    let branding: LandingPageBranding?
    
    public init(pageData: Binding<LandingPageData>, branding: LandingPageBranding? = nil) {
        self._pageData = pageData
        self.branding = branding
    }
    
    public var body: some View {
        LandingPagePreview(page: pageData, branding: branding)
    }
}

