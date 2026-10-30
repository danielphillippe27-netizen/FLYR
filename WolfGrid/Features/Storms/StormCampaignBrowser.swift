import SwiftUI
import WebKit
import Supabase
import CoreLocation

/// Hosts the shared storm workbench, with the native app's current workspace and short-lived session.
struct StormCampaignBrowser: View {
    let initialCenter: CLLocationCoordinate2D
    let onCampaignCreated: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var workspace = WorkspaceContext.shared
    @State private var failure: String?
    @State private var reloadID = UUID()

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .top) {
            Group {
                if let failure {
                    ContentUnavailableView {
                        Label("Storms unavailable", systemImage: "cloud.bolt.rain")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Try Again") { self.failure = nil; reloadID = UUID() }
                    }
                } else if let workspaceId = workspace.workspaceId {
                    StormWebView(workspaceId: workspaceId, center: initialCenter, topInset: geometry.safeAreaInsets.top,
                                 onCampaign: onCampaignCreated, onFailure: { failure = $0 })
                        .id(reloadID)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Choose a workspace", systemImage: "person.2", description: Text("Select your workspace before opening Storms."))
                }
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close Storms")
                Spacer()

            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .onChange(of: workspace.workspaceId) { _, _ in dismiss() }
        }
        }
    }
}

private struct StormWebView: UIViewRepresentable {
    let workspaceId: UUID
    let center: CLLocationCoordinate2D
    let topInset: CGFloat
    let onCampaign: (UUID) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        guard let url = context.coordinator.pageURL, url.scheme == "https" else {
            DispatchQueue.main.async { onFailure("The Storms service address is unavailable.") }
            return web
        }
        web.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.authTask?.cancel()
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: StormWebView
        let pageURL: URL?
        var authTask: Task<Void, Never>?
        init(_ parent: StormWebView) {
            self.parent = parent
            var components = URLComponents(url: Config.backendAPIURL, resolvingAgainstBaseURL: false)
            components?.path = "/mobile/storms"
            components?.queryItems = [URLQueryItem(name: "chrome", value: "map"), URLQueryItem(name: "inset", value: String(Double(parent.topInset)))]
            components?.fragment = nil
            self.pageURL = components?.url
        }
        private func sameOrigin(_ url: URL?) -> Bool {
            guard let url, let pageURL else { return false }
            return url.scheme == pageURL.scheme && url.host == pageURL.host && url.port == pageURL.port
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "wolfgrid-storms" {
                decisionHandler(.cancel)
                guard action.sourceFrame.isMainFrame, sameOrigin(webView.url), webView.url?.path == "/mobile/storms" else { return }
                switch url.host {
                case "ready", "refresh": authenticate(webView, refresh: url.host == "refresh")
                case "campaign":
                    if let id = UUID(uuidString: String(url.path.dropFirst())) { parent.onCampaign(id) }
                default: break
                }
                return
            }
            // Keep account credentials and native navigation restricted to this dedicated page.
            decisionHandler(sameOrigin(url) && url.path == "/mobile/storms" && action.targetFrame?.isMainFrame != false ? .allow : .cancel)
        }
        private func authenticate(_ web: WKWebView, refresh: Bool) {
            authTask?.cancel()
            authTask = Task { [weak self, weak web] in
                guard let self, let web else { return }
                do {
                    let client = SupabaseManager.shared.client
                    let session = try await (refresh ? client.auth.refreshSession() : client.auth.session)
                    guard !Task.isCancelled, self.sameOrigin(web.url), WorkspaceContext.shared.workspaceId == self.parent.workspaceId else { return }
                    KeychainAuthStorage.saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken)
                    // Tokens travel only through the isolated in-memory page, never a URL, cookie, or disk cache.
                    let payload: [String: Any] = ["accessToken": session.accessToken,
                        "workspaceId": self.parent.workspaceId.uuidString.lowercased(),
                        "center": [self.parent.center.longitude, self.parent.center.latitude]]
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    guard let json = String(data: data, encoding: .utf8) else { return }
                    try await web.evaluateJavaScript("window.WolfGridStorms?.start(\(json));")
                } catch {
                    guard !Task.isCancelled else { return }
                    self.parent.onFailure("Could not connect to Storms. Check your connection and sign-in, then try again.")
                }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { parent.onFailure("Could not load Storms. Check your connection and try again.") }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { parent.onFailure("Storms could not finish loading. Please try again.") }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { parent.onFailure("The storm map closed unexpectedly. Tap Try Again to reopen it.") }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                parent.onFailure("Storms is not available on this server yet. Please try again later.")
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
        // Shared territory controls use confirm/prompt for rename and delete.
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "Storm territory", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Continue", style: .default) { _ in completionHandler(true) })
            guard let presenter = webView.window?.rootViewController else { completionHandler(false); return }
            var top = presenter
            while let presented = top.presentedViewController { top = presented }
            top.present(alert, animated: true)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: "Storm territory", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
            guard let presenter = webView.window?.rootViewController else { completionHandler(nil); return }
            var top = presenter
            while let presented = top.presentedViewController { top = presented }
            top.present(alert, animated: true)
        }
    }
}
