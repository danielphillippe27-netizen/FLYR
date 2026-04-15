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
                        .font(.flyrCaption)
                        .foregroundColor(.muted)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    CampaignTypeLabel(type: campaign.type, size: .small)

                    if let confidence = campaign.dataConfidence {
                        Text(confidence.label.title)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(confidenceForegroundColor(for: confidence.label))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(confidenceBackgroundColor(for: confidence.label))
                            .clipShape(Capsule())
                    }
                }
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
                    .font(.flyrCaption)
                
                Text("\(campaign.totalFlyers) addresses")
                    .font(.flyrCaption)
                    .foregroundColor(.muted)
                
                Spacer()
                
                Text(campaign.addressSource.displayName)
                    .font(.flyrCaption)
                    .foregroundColor(.muted)
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

    private func confidenceForegroundColor(for label: DataConfidenceLabel) -> Color {
        switch label {
        case .high:
            return .green
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }

    private func confidenceBackgroundColor(for label: DataConfidenceLabel) -> Color {
        switch label {
        case .high:
            return Color.green.opacity(0.12)
        case .medium:
            return Color.orange.opacity(0.12)
        case .low:
            return Color.red.opacity(0.12)
        }
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
