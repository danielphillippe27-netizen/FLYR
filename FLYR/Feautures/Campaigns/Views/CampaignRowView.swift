import SwiftUI

/// Minimal grey-box list row for CampaignV2: name + house/door count (matches Start Session style).
struct CampaignRowView: View {
    let campaign: CampaignV2
    /// When set (e.g. duplicate names), show this instead of campaign.name in the title.
    var displayName: String?
    var buildingProgressPercent: Int?
    var isAssigned = false
    var onPlayTapped: (() -> Void)?
    var isSelectionMode = false
    var isSelected = false

    private var titleText: String {
        displayName ?? campaign.name
    }

    private var progressPct: Int {
        campaign.progressPct
    }

    private var isBuilding: Bool {
        buildingProgressPercent != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.flyrHeadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isAssigned {
                    Label("Assigned to you", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityLabel("Assigned to you")
                }

                if let buildingProgressPercent {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Building... \(buildingProgressPercent)%")
                            .font(.flyrCaption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Label("\(campaign.totalFlyers)", systemImage: "house.fill")
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isSelectionMode {
                Text(isSelected ? "Selected" : "Select")
                    .font(.flyrCaption)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            } else if isBuilding {
                ProgressView()
                    .controlSize(.small)
            } else if campaign.status != .completed, onPlayTapped != nil {
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
