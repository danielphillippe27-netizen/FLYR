import SwiftUI
import WebKit

/// WebView wrapper for rendering landing pages
public struct LandingPageWebView: UIViewRepresentable {
    let url: URL
    
    public init(url: URL) {
        self.url = url
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    public func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate {
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Handle page load completion
        }
    }
}

/// SwiftUI wrapper for in-app landing page rendering
public struct LandingPageView: View {
    let pageData: LandingPageData
    let branding: LandingPageBranding?
    
    public init(pageData: LandingPageData, branding: LandingPageBranding? = nil) {
        self.pageData = pageData
        self.branding = branding
    }
    
    public var body: some View {
        LandingPagePreview(page: pageData, branding: branding)
    }
}

