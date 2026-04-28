import SwiftUI

struct TeamSessionPanel: View {
    let teammates: [SharedCanvassingTeammate]

    private var liveCount: Int {
        teammates.filter { $0.freshness == .live && $0.presenceStatus == .active }.count
    }

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(liveCount == 1 ? "1 rep live" : "\(liveCount) reps live")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            }

            ForEach(teammates.prefix(4)) { teammate in
                HStack(spacing: 10) {
                    ProfileAvatarView(
                        avatarUrl: teammate.avatarURL,
                        name: teammate.displayName,
                        size: 28
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(teammate.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(subtitle(for: teammate))
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Circle()
                        .fill(indicatorColor(for: teammate))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 260, alignment: .leading)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
    }

    private func subtitle(for teammate: SharedCanvassingTeammate) -> String {
        if teammate.presenceStatus == .paused {
            return "Paused"
        }
        if teammate.freshness == .stale {
            return "Seen \(relativeFormatter.localizedString(for: teammate.updatedAt, relativeTo: Date()))"
        }
        return "Active now"
    }

    private func indicatorColor(for teammate: SharedCanvassingTeammate) -> Color {
        if teammate.presenceStatus == .paused {
            return Color.orange
        }
        if teammate.freshness == .stale {
            return Color.gray
        }
        return Color.green
    }
}
