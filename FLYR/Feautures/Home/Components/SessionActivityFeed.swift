import SwiftUI

struct SessionActivityFeed: View {
    let sessions: [SessionRecord]
    var maxItems: Int = 5
    var onViewAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if sessions.isEmpty {
                emptyStateView
            } else {
                let displayed = Array(sessions.prefix(maxItems))
                ForEach(displayed.indices, id: \.self) { index in
                    RecentActivityRow(session: displayed[index])
                    if index < displayed.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
                if sessions.count > maxItems, let onViewAll = onViewAll {
                    Button(action: onViewAll) {
                        Text("View All")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.accentDefault)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 48))
                .foregroundColor(.muted)

            Text("No sessions yet")
                .font(.flyrHeadline)
                .foregroundColor(.text)

            Text("Start a session to see your activity here")
                .font(.flyrSubheadline)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
}

/// Compact row: icon (24pt) | activity type | count | time (right). No goal text in row.
struct RecentActivityRow: View {
    let session: SessionRecord

    private var duration: TimeInterval {
        guard let end = session.end_time else { return 0 }
        return end.timeIntervalSince(session.start_time)
    }

    /// Duration as "X min" or "Xh Y min" to avoid confusion with meters.
    private var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes) min"
        }
        return "\(minutes) min"
    }

    private var activityLabel: String {
        (session.goal_type ?? "flyers") == "flyers" ? "Flyers" : "Door Knock"
    }

    private var iconName: String {
        (session.goal_type ?? "flyers") == "flyers" ? "paperplane.fill" : "hand.raised.fill"
    }

    private var countDisplay: Int {
        session.completed_count ?? session.goal_amount ?? 0
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundColor(.accentDefault)
                .frame(width: 32, height: 32)

            Text(activityLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.text)

            Spacer()

            Text("\(countDisplay)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.text)

            Text(timeFormatter.string(from: session.start_time))
                .font(.system(size: 15))
                .foregroundColor(.muted)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    SessionActivityFeed(sessions: [], onViewAll: nil)
        .padding()
        .background(Color.bg)
}
