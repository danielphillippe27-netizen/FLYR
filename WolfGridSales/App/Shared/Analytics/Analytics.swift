import Foundation

final class Analytics {
    static let shared = Analytics()
    
    private init() {}
    
    // MARK: - Screen Tracking
    func trackScreen(_ screenName: String) {
        #if DEBUG
        print("📊 Analytics: Screen viewed - \(screenName)")
        #endif
        // TODO: Integrate with your analytics provider (Firebase, Mixpanel, etc.)
    }
    
    // MARK: - Event Tracking
    func trackEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        #if DEBUG
        print("📊 Analytics: Event - \(eventName)")
        if let params = parameters {
            print("   Parameters: \(params)")
        }
        #endif
        // TODO: Integrate with your analytics provider
    }
    
    // MARK: - User Properties
    func setUserProperty(_ value: String, forKey key: String) {
        #if DEBUG
        print("📊 Analytics: User property - \(key): \(value)")
        #endif
        // TODO: Integrate with your analytics provider
    }
    
    // MARK: - Campaign Events
    func trackCampaignCreated(campaignId: String, title: String) {
        trackEvent("campaign_created", parameters: [
            "campaign_id": campaignId,
            "title": title
        ])
    }
    
    func trackCampaignViewed(campaignId: String) {
        trackEvent("campaign_viewed", parameters: [
            "campaign_id": campaignId
        ])
    }
    
    func trackQRScanned(campaignId: String) {
        trackEvent("qr_scanned", parameters: [
            "campaign_id": campaignId
        ])
    }
    
    // MARK: - Auth Events
    func trackSignIn(method: String) {
        trackEvent("sign_in", parameters: [
            "method": method
        ])
    }
    
    func trackSignOut() {
        trackEvent("sign_out")
    }
    
    func trackSignUp(method: String) {
        trackEvent("sign_up", parameters: [
            "method": method
        ])
    }
}

// View extension for easy screen tracking
import SwiftUI

extension View {
    func trackScreen(_ screenName: String) -> some View {
        self.task {
            Analytics.shared.trackScreen(screenName)
        }
    }
}


