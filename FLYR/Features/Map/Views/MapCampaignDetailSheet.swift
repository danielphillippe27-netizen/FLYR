import SwiftUI

/// Persistent bottom sheet on the Map tab: selected campaign details + Start Session, or empty state with View Campaigns.
struct MapCampaignDetailSheet: View {
    let selectedCampaignId: UUID?
    let campaigns: [CampaignListItem]
    let onViewCampaigns: () -> Void
    let onStartSession: () -> Void

    private var selectedCampaign: CampaignListItem? {
        guard let id = selectedCampaignId else { return nil }
        return campaigns.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 6)
                .padding(.top, 8)

            if let campaign = selectedCampaign {
                campaignContent(campaign)
            } else {
                emptyStateContent
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    private func campaignContent(_ campaign: CampaignListItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(campaign.name)
                .font(.system(size: 20, weight: .semibold))

            if let count = campaign.addressCount {
                Text("\(count) addresses")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }

            Button(action: onStartSession) {
                Text("Start Session")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateContent: some View {
        VStack(spacing: 16) {
            Text("Select a campaign from the list or search for an address")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onViewCampaigns) {
                Text("View Campaigns")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Empty") {
    MapCampaignDetailSheet(
        selectedCampaignId: nil,
        campaigns: [],
        onViewCampaigns: {},
        onStartSession: {}
    )
}

#Preview("Selected") {
    let id = UUID()
    return MapCampaignDetailSheet(
        selectedCampaignId: id,
        campaigns: [
            CampaignListItem(id: id, name: "Summer Flyer", addressCount: 51)
        ],
        onViewCampaigns: {},
        onStartSession: {}
    )
}
