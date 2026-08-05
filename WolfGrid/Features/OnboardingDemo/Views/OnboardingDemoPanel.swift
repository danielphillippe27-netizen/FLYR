import SwiftUI

struct OnboardingDemoPanel: View {
    let state: OnboardingDemoState
    let items: [OnboardingDemoChecklistItem]
    let completedIDs: Set<String>
    let isSeeding: Bool
    let onDismiss: () -> Void
    let onTapItem: (OnboardingDemoChecklistItem) -> Void

    private var progressText: String {
        "\(completedIDs.count)/\(items.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Getting started")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.text)
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(progressText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.red)
                    .clipShape(Capsule())

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.muted)
                        .frame(width: 28, height: 28)
                        .background(Color.gray.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss getting started")
            }

            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        onTapItem(item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: completedIDs.contains(item.id) ? "checkmark.circle.fill" : item.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(completedIDs.contains(item.id) ? Color.green : Color.red)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.subtitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.muted)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if isSeeding && item.action == .createStarterCampaign {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.muted)
                            }
                        }
                        .padding(12)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSeeding && item.action == .createStarterCampaign)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 6)
    }

    private var subtitle: String {
        switch state.rolePath {
        case .soloOwner:
            return "Use a real editable starter farm, then create your own first campaign."
        case .teamOwner:
            return "Review the starter campaign, team work, leads, and reporting flow."
        case .member:
            return "Focus on assigned work, recording outcomes, leads, and your stats."
        }
    }
}
