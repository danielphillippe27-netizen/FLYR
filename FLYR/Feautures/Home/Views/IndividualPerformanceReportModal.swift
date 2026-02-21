import SwiftUI

struct IndividualPerformanceReportModal: View {
    @Environment(\.colorScheme) private var colorScheme

    let reports: [IndividualPerformanceReport]
    let isLoading: Bool
    let errorMessage: String?
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.primary.opacity(0.12))

            content
        }
        .frame(maxWidth: 520)
        .frame(maxHeight: UIScreen.main.bounds.height * 0.78)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.24 : 0.12), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.28), radius: 24, x: 0, y: 12)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reports")
                    .font(.flyrTitle2)
                    .foregroundStyle(foreground)

                Text("Weekly, monthly, and yearly performance snapshots.")
                    .font(.flyrFootnote)
                    .foregroundStyle(foreground.opacity(0.75))
            }

            Spacer()

            Button(action: {
                HapticManager.light()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading reports...")
                    .font(.flyrFootnote)
                    .foregroundStyle(foreground.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 40)
        } else if let errorMessage {
            VStack(spacing: 14) {
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .font(.flyrBody)
                    .foregroundStyle(foreground)

                Button("Retry") {
                    HapticManager.light()
                    onRefresh()
                }
                .buttonStyle(.borderedProminent)
                .tint(.flyrPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 40)
        } else if reports.isEmpty {
            VStack(spacing: 10) {
                Text("No report yet")
                    .font(.flyrHeadline)
                    .foregroundStyle(foreground)

                Text("Your weekly, monthly, and yearly reports will appear here once generated.")
                    .font(.flyrFootnote)
                    .foregroundStyle(foreground.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 40)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(reports) { report in
                        IndividualReportCard(report: report)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
    }
}

private struct IndividualReportCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let report: IndividualPerformanceReport

    private struct MetricSpec: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    private let metricSpecs: [MetricSpec] = [
        .init(key: "doors_knocked", label: "Doors"),
        .init(key: "flyers_delivered", label: "Flyers"),
        .init(key: "conversations", label: "Convos"),
        .init(key: "leads_created", label: "Leads"),
        .init(key: "appointments_set", label: "Appts"),
        .init(key: "time_spent_seconds", label: "Time"),
        .init(key: "sessions_count", label: "Sessions"),
    ]

    private var foreground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var tileBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.white
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(periodTitle(report.period))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(foreground)

                Text(report.rangeLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(foreground.opacity(0.7))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(metricSpecs) { spec in
                    metricTile(spec: spec)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10), lineWidth: 1)
        )
    }

    private func metricTile(spec: MetricSpec) -> some View {
        let metric = metric(for: spec.key)
        let value = metric?.value ?? 0
        let delta = metric?.delta
        let trend = metric?.resolvedTrend ?? .flat

        return VStack(alignment: .leading, spacing: 3) {
            Text(spec.label)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(foreground.opacity(0.68))

            Text(formatMetricValue(key: spec.key, value: value))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(foreground)

            Text(formatDelta(delta))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(deltaColor(trend))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tileBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
        )
    }

    private func metric(for key: String) -> IndividualPerformanceMetric? {
        report.metrics.first(where: { $0.key == key })
    }

    private func periodTitle(_ period: IndividualReportPeriod) -> String {
        switch period {
        case .weekly: return "Weekly Report"
        case .monthly: return "Monthly Report"
        case .yearly: return "Yearly Report"
        }
    }

    private func formatMetricValue(key: String, value: Double) -> String {
        if key == "time_spent_seconds" {
            let total = max(0, Int(value.rounded()))
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(minutes)m"
        }

        return "\(Int(value.rounded()))"
    }

    private func formatDelta(_ delta: IndividualMetricDelta?) -> String {
        guard let delta else { return "flat" }

        let absValue = delta.abs ?? 0
        let sign = absValue > 0 ? "+" : absValue < 0 ? "-" : ""
        let absLabel = "\(sign)\(abs(Int(absValue.rounded())))"

        guard let pctValue = delta.pct else { return absLabel }

        let pctSign = pctValue > 0 ? "+" : pctValue < 0 ? "-" : ""
        let pctLabel = String(format: "%.1f", abs(pctValue))

        return "\(absLabel) (\(pctSign)\(pctLabel)%)"
    }

    private func deltaColor(_ trend: IndividualMetricTrend) -> Color {
        switch trend {
        case .up:
            return .success
        case .down:
            return .error
        case .flat:
            return foreground.opacity(0.64)
        }
    }
}
