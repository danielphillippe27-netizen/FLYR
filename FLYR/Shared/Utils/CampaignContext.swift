import SwiftUI

// MARK: - Campaign Context

@Observable
class CampaignContext {
    var currentCampaign: Campaign?
    
    /// Dynamic accent color based on current campaign
    var accentColor: Color {
        if let campaign = currentCampaign,
           let accentHex = campaign.accentColor {
            return Color(hex: accentHex)
        }
        return Color.accentDefault
    }
    
    /// Set the current campaign
    func setCampaign(_ campaign: Campaign?) {
        currentCampaign = campaign
    }
    
    /// Clear the current campaign
    func clearCampaign() {
        currentCampaign = nil
    }
}

// MARK: - Environment Key

struct CampaignContextKey: EnvironmentKey {
    static let defaultValue = CampaignContext()
}

extension EnvironmentValues {
    var campaignContext: CampaignContext {
        get { self[CampaignContextKey.self] }
        set { self[CampaignContextKey.self] = newValue }
    }
}

// MARK: - Campaign Accent Environment Key

struct CampaignAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentDefault
}

extension EnvironmentValues {
    var campaignAccent: Color {
        get { self[CampaignAccentKey.self] }
        set { self[CampaignAccentKey.self] = newValue }
    }
}

// MARK: - View Extensions

extension View {
    /// Set the campaign context for this view and its children
    func campaignContext(_ context: CampaignContext) -> some View {
        self.environment(\.campaignContext, context)
            .environment(\.campaignAccent, context.accentColor)
    }
    
    /// Set a specific campaign and update the context
    func campaign(_ campaign: Campaign?) -> some View {
        let accentColor: Color = {
            if let campaign = campaign,
               let accentHex = campaign.accentColor {
                return Color(hex: accentHex)
            }
            return Color.accentDefault
        }()
        
        let context = CampaignContext()
        context.setCampaign(campaign)
        
        return self
            .environment(\.campaignContext, context)
            .environment(\.campaignAccent, accentColor)
    }
}

// MARK: - Campaign Context Provider

struct CampaignContextProvider<Content: View>: View {
    let content: Content
    @State private var context = CampaignContext()
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .environment(\.campaignContext, context)
            .environment(\.campaignAccent, context.accentColor)
    }
}

// MARK: - Preview

#Preview {
    CampaignContextProvider {
        VStack(spacing: 20) {
            // Default accent color
            Text("Default Accent")
                .foregroundColor(.accent)
                .font(.title)
            
            // Campaign with custom accent
            let customCampaign = Campaign(
                id: UUID(),
                title: "Custom Campaign",
                description: "A campaign with custom accent color",
                coverImageURL: nil,
                totalFlyers: 1000,
                scans: 250,
                conversions: 50,
                region: "San Francisco",
                userId: UUID(),
                accentColor: "#FF6B6B", // Custom red accent
                createdAt: Date()
            )
            
            VStack {
                Text("Custom Accent")
                    .foregroundColor(.accent)
                    .font(.title)
                
                Text("Campaign: \(customCampaign.title)")
                    .bodyText()
                    .foregroundColor(.text)
                
                Button("Set Campaign") {
                    // This would set the campaign context
                }
                .primaryButton()
            }
            .campaign(customCampaign)
        }
        .padding()
        .background(Color.bgSecondary)
    }
}
