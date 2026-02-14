import SwiftUI

/// Minimal grey-box list row for CampaignV2: name + house/door count (matches Start Session style).
struct CampaignRowView: View {
    let campaign: CampaignV2
    /// When set (e.g. duplicate names), show this instead of campaign.name in the title.
    var displayName: String?
    var onPlayTapped: (() -> Void)?

    private var titleText: String {
        displayName ?? campaign.name
    }

    private var progressPct: Int {
        campaign.progressPct
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.flyrHeadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Label("\(campaign.totalFlyers)", systemImage: "house.fill")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if campaign.status != .completed, onPlayTapped != nil {
                Button {
                    onPlayTapped?()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } else {
                Text("\(progressPct)%")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    List {
        CampaignRowView(campaign: CampaignV2.mockCampaigns[0], onPlayTapped: {})
        CampaignRowView(campaign: CampaignV2.mockCampaigns[1], onPlayTapped: {})
        CampaignRowView(campaign: CampaignV2.mockCampaigns[2], onPlayTapped: nil)
    }
    .listStyle(.plain)
}
