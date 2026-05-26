import SwiftUI

struct CampaignProvisionStatusBanner: View {
    let tracked: TrackedCampaignProvision
    var compact: Bool = false
    var onTap: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.flyrFootnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(tracked.statusText)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
            }

            Spacer(minLength: 8)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, compact ? 10 : 12)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private var title: String {
        switch tracked.state {
        case .queued:
            return "Queued: \(tracked.campaignName)"
        case .preparingMap:
            return "Preparing: \(tracked.campaignName)"
        case .optimizing:
            return "Optimizing: \(tracked.campaignName)"
        case .ready:
            return "Ready: \(tracked.campaignName)"
        case .needsAttention:
            return "Needs attention: \(tracked.campaignName)"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tracked.state {
        case .queued, .preparingMap, .optimizing:
            ProgressView()
                .controlSize(.small)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var borderColor: Color {
        switch tracked.state {
        case .ready:
            return .green
        case .needsAttention:
            return .orange
        default:
            return .accentColor
        }
    }
}
