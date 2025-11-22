import SwiftUI

/// Apple Wallet-style card component for displaying CampaignV2 in lists
struct CampaignRowView: View {
    let campaign: CampaignV2
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
    
    private var progressPercentage: Int {
        Int(campaign.progress * 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Name and Badge
            HStack {
                Text(campaign.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                
                Spacer()
                
                Badge(text: campaign.type.title)
            }
            
            // Progress section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Spacer()
                    
                    Text("\(progressPercentage)%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.text)
                }
                
                ProgressView(value: campaign.progress)
                    .tint(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .shadow(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CampaignRowView(campaign: CampaignV2.mockCampaigns[0])
        CampaignRowView(campaign: CampaignV2.mockCampaigns[1])
        CampaignRowView(campaign: CampaignV2.mockCampaigns[2])
    }
    .padding()
    .background(Color.bgSecondary)
}

