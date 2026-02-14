import SwiftUI

private enum PodiumStyle {
    case gold   // #FFD700
    case silver // #C0C0C0
    case bronze // #CD7F32
    case none

    static func forRank(_ rank: Int) -> PodiumStyle {
        switch rank {
        case 1: return .gold
        case 2: return .silver
        case 3: return .bronze
        default: return .none
        }
    }

    var color: Color {
        switch self {
        case .gold: return Color(hex: "#FFD700")
        case .silver: return Color(hex: "#C0C0C0")
        case .bronze: return Color(hex: "#CD7F32")
        case .none: return Color.primary
        }
    }
}

struct LeaderboardRow: View {
    let rank: Int
    let avatarUrl: String?
    let name: String
    let subtitle: String?
    let value: Double
    let isCurrentUser: Bool
    let isActiveMetric: Bool

    init(
        rank: Int,
        avatarUrl: String? = nil,
        name: String,
        subtitle: String? = nil,
        value: Double,
        isCurrentUser: Bool = false,
        isActiveMetric: Bool = true
    ) {
        self.rank = rank
        self.avatarUrl = avatarUrl
        self.name = name
        self.subtitle = subtitle
        self.value = value
        self.isCurrentUser = isCurrentUser
        self.isActiveMetric = isActiveMetric
    }

    private static let accentRed = Color(hex: "#FF4F4F")
    private var podiumStyle: PodiumStyle { PodiumStyle.forRank(rank) }

    var body: some View {
        HStack(spacing: 12) {
            // Rank (with top 3 treatment)
            rankView
                .frame(width: 36, alignment: .leading)

            // Avatar
            ProfileAvatarView(avatarUrl: avatarUrl, name: name, size: 36)

            // Name + optional subtitle
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isCurrentUser {
                        Text("You")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Self.accentRed)
                            .cornerRadius(4)
                    }
                }
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Metric value (monospaced, red when active)
            Text(formatValue(value))
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundColor(isActiveMetric ? Self.accentRed : .text)
                .frame(minWidth: 44, alignment: .trailing)

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .background(rowBackground)
    }

    @ViewBuilder
    private var rankView: some View {
        switch rank {
        case 1:
            ZStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 20))
                    .foregroundColor(podiumStyle.color)
            }
        case 2, 3:
            ZStack {
                Circle()
                    .fill(podiumStyle.color.opacity(0.25))
                    .frame(width: 28, height: 28)
                Text("\(rank)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(podiumStyle.color)
            }
        default:
            Text("\(rank)")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(.muted)
        }
    }

    private var rowBackground: Color {
        if isCurrentUser {
            return Self.accentRed.opacity(0.08)
        }
        if rank <= 3 {
            return podiumStyle.color.opacity(0.06)
        }
        return Color.clear
    }

    private func formatValue(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }
}

#Preview {
    VStack(spacing: 0) {
        LeaderboardRow(rank: 1, name: "Alice", value: 420, isActiveMetric: true)
        LeaderboardRow(rank: 2, name: "Bob", subtitle: "260 flyers", value: 380, isCurrentUser: true, isActiveMetric: true)
        LeaderboardRow(rank: 3, name: "Carol", value: 350, isActiveMetric: true)
        LeaderboardRow(rank: 4, avatarUrl: nil, name: "Daniel Phillippe", subtitle: nil, value: 320, isActiveMetric: true)
    }
    .background(Color.bg)
}
