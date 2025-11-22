import SwiftUI
import SafariServices
import AuthenticationServices

/// OAuth view wrapper using SFSafariViewController for in-app OAuth flows
struct OAuthView: UIViewControllerRepresentable {
    let provider: IntegrationProvider
    let userId: UUID
    let onComplete: (Result<String, Error>) -> Void
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        // Build OAuth URL based on provider
        let authURL: URL
        
        switch provider {
        case .hubspot:
            // HubSpot OAuth URL
            let clientId = "YOUR_HUBSPOT_CLIENT_ID" // This should come from config/env
            let redirectURI = "flyr://oauth"
            let scopes = "contacts"
            let urlString = "https://app.hubspot.com/oauth/authorize?client_id=\(clientId)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&scope=\(scopes)"
            guard let url = URL(string: urlString) else {
                fatalError("Invalid HubSpot OAuth URL")
            }
            authURL = url
            
        case .monday:
            // Monday.com OAuth URL
            let clientId = "YOUR_MONDAY_CLIENT_ID" // This should come from config/env
            let redirectURI = "flyr://oauth"
            let scopes = "boards:read boards:write"
            let urlString = "https://auth.monday.com/oauth2/authorize?client_id=\(clientId)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes)"
            guard let url = URL(string: urlString) else {
                fatalError("Invalid Monday.com OAuth URL")
            }
            authURL = url
            
        default:
            fatalError("OAuth not supported for provider: \(provider)")
        }
        
        let safariVC = SFSafariViewController(url: authURL)
        safariVC.preferredControlTintColor = .systemBlue
        safariVC.dismissButtonStyle = .close
        
        return safariVC
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

/// Helper to get OAuth URLs from environment/config
/// In production, these should be stored in Config or environment variables
struct OAuthURLBuilder {
    static func hubSpotAuthURL() -> URL? {
        // TODO: Get from Config or environment
        let clientId = "YOUR_HUBSPOT_CLIENT_ID"
        let redirectURI = "flyr://oauth"
        let scopes = "contacts"
        let urlString = "https://app.hubspot.com/oauth/authorize?client_id=\(clientId)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&scope=\(scopes)"
        return URL(string: urlString)
    }
    
    static func mondayAuthURL() -> URL? {
        // TODO: Get from Config or environment
        let clientId = "YOUR_MONDAY_CLIENT_ID"
        let redirectURI = "flyr://oauth"
        let scopes = "boards:read boards:write"
        let urlString = "https://auth.monday.com/oauth2/authorize?client_id=\(clientId)&redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)&scope=\(scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes)"
        return URL(string: urlString)
    }
}


