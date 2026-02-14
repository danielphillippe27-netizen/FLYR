import SwiftUI

/// Expandable/collapsible stats card for active building session (redesign replacement for SessionHUDCard layout).
struct StatsCardView: View {
    @ObservedObject var sessionManager: SessionManager
    @Binding var isExpanded: Bool
    @Binding var dragOffset: CGFloat

    var body: some View {
        Group {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.horizontal)
    }

    private var expandedContent: some View {
        VStack(spacing: 12) {
            // Drag handle hint
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)

            // Doors (target homes)
            Text("Doors")
                .font(.flyrCaption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                StatMetric(title: "Target", value: "\(sessionManager.targetCount)")
                StatMetric(title: "Done", value: "\(sessionManager.completedCount)", color: .green)
                StatMetric(title: "Left", value: "\(sessionManager.remainingCount)", color: .flyrPrimary)
            }

            // Progress bar (how close to hitting target homes)
            Text("Progress toward target")
                .font(.flyrCaption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green)
                        .frame(width: max(0, geometry.size.width * sessionManager.progressPercentage))
                }
            }
            .frame(height: 8)

            // Time & distance
            HStack(spacing: 16) {
                StatMetric(title: "Time", value: sessionManager.formattedElapsedTime)
                StatMetric(title: "Distance", value: sessionManager.formattedDistance)
                StatMetric(title: "Pace", value: sessionManager.formattedPace)
            }

            StatusLegendCompact(
                targetCount: sessionManager.targetCount,
                doneCount: sessionManager.completedCount,
                remainingCount: sessionManager.remainingCount
            )

            if let error = sessionManager.locationError {
                Text(error)
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var collapsedContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionManager.formattedElapsedTime)
                    .font(.flyrHeadline)
                Text("\(sessionManager.completedCount)/\(sessionManager.targetCount) · \(sessionManager.formattedPace)")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Stat metric (single value + label)
struct StatMetric: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.flyrCaption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.flyrHeadline)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Compact status legend (Target / Done / Left)
struct StatusLegendCompact: View {
    let targetCount: Int
    let doneCount: Int
    let remainingCount: Int

    var body: some View {
        HStack(spacing: 12) {
            StatusDot(label: "Target", count: targetCount, color: .primary)
            StatusDot(label: "Done", count: doneCount, color: .green)
            StatusDot(label: "Left", count: remainingCount, color: .flyrPrimary)
        }
        .font(.flyrCaption)
    }
}

struct StatusDot: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label): \(count)")
                .foregroundColor(.secondary)
        }
    }
}
