import SwiftUI

/// Card component for displaying CampaignV2 in lists
struct CampaignV2Card: View {
    let campaign: CampaignV2
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(campaign.name)
                        .font(.subheading)
                        .foregroundColor(.text)
                        .lineLimit(2)
                    
                    Text("Created \(campaign.createdAt, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.muted)
                }
                
                Spacer()
                
                CampaignTypeLabel(type: campaign.type, size: .small)
            }
            
            // Progress
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress")
                        .font(.label)
                        .foregroundColor(.text)
                    
                    Spacer()
                    
                    Text("\(Int(campaign.progress * 100))%")
                        .font(.label)
                        .fontWeight(.medium)
                        .foregroundColor(.text)
                }
                
                ProgressBar(value: campaign.progress)
            }
            
            // Address count
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.muted)
                    .font(.caption)
                
                Text("\(campaign.addresses.count) addresses")
                    .font(.caption)
                    .foregroundColor(.muted)
                
                Spacer()
                
                if campaign.addressSource == .closestHome {
                    Text("Closest Home")
                        .font(.caption)
                        .foregroundColor(.muted)
                } else {
                    Text("Imported List")
                        .font(.caption)
                        .foregroundColor(.muted)
                }
            }
        }
        .padding(16)
        .background(Color.bgSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.border, lineWidth: 1)
        )
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CampaignV2Card(campaign: CampaignV2.mockCampaigns[0])
        CampaignV2Card(campaign: CampaignV2.mockCampaigns[1])
        CampaignV2Card(campaign: CampaignV2.mockCampaigns[2])
    }
    .padding()
    .background(Color.bg)
}
