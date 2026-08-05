import SwiftUI

struct OldCampaignDetailView: View {
    let campaign: Campaign
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Campaign Header
            VStack(alignment: .leading, spacing: 12) {
                Text(campaign.title)
                    .heading()
                    .foregroundColor(.text)
                
                if !campaign.description.isEmpty {
                    Text(campaign.description)
                        .bodyText()
                        .foregroundColor(.muted)
                }
                
                if let region = campaign.region {
                    Text("Region: \(region)")
                        .captionText()
                        .foregroundColor(.muted)
                }
            }
            
            // Stats Grid
            StatGrid(stats: [
                StatPill(value: "\(campaign.totalFlyers)", label: "Total Flyers"),
                StatPill(value: "\(campaign.scans)", label: "Scans", hasAccentHighlight: true),
                StatPill(value: "\(campaign.conversions)", label: "Conversions")
            ])
            .card()
            
            // Progress Ring
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Campaign Progress")
                        .subheading()
                        .foregroundColor(.text)
                    
                    Text("Track your campaign performance")
                        .captionText()
                        .foregroundColor(.muted)
                }
                
                Spacer()
                
                ProgressRing(
                    progress: Double(campaign.scans) / Double(campaign.totalFlyers),
                    text: "\(Int((Double(campaign.scans) / Double(campaign.totalFlyers)) * 100))%"
                )
            }
            .card()
            
            Spacer()
        }
        .padding()
        .navigationTitle("Campaign Details")
        .navigationBarTitleDisplayMode(.inline)
        .campaign(campaign) // Set campaign context for accent color
    }
}

#Preview {
    NavigationStack {
        OldCampaignDetailView(campaign: Campaign(
            id: UUID(),
            title: "Summer Sale Campaign",
            description: "Promote our summer sale with flyer distribution across downtown area",
            coverImageURL: nil,
            totalFlyers: 1000,
            scans: 250,
            conversions: 50,
            region: "San Francisco",
            userId: UUID(),
            accentColor: "#FF6B6B",
            createdAt: Date()
        ))
    }
}