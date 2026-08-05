import SwiftUI

struct RoutePlanDetailView: View {
    let routePlanId: UUID
    let assignment: RouteAssignmentSummary?

    @State private var detail: RoutePlanDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(routePlanId: UUID, assignment: RouteAssignmentSummary? = nil) {
        self.routePlanId = routePlanId
        self.assignment = assignment
    }

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Loading route...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, detail == nil {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text("Couldn’t load route details")
                        .font(.flyrHeadline)
                    Text(errorMessage)
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard(detail: detail)

                        if !detail.segments.isEmpty {
                            sectionTitle("Segments")
                            ForEach(detail.segments) { segment in
                                segmentRow(segment)
                            }
                        }

                        if !detail.stops.isEmpty {
                            sectionTitle("Stops")
                            ForEach(detail.stops) { stop in
                                stopRow(stop)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(detail?.name ?? assignment?.name ?? "Route")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: routePlanId) {
            await loadDetail()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func summaryCard(detail: RoutePlanDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.name)
                .font(.flyrHeadline)

            HStack(spacing: 12) {
                metricPill(icon: "mappin.and.ellipse", text: "\(detail.totalStops) stops")
                if let estMinutes = detail.estMinutes {
                    metricPill(icon: "clock", text: "\(estMinutes) min")
                }
                if let meters = detail.distanceMeters {
                    metricPill(icon: "figure.walk", text: formatDistance(meters))
                }
            }

            if let assignment {
                ProgressView(value: assignment.progressFraction)
                    .tint(.red)
                Text("\(assignment.completedStops)/\(max(assignment.totalStops, 0)) complete")
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }

    private func segmentRow(_ segment: RoutePlanSegment) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.streetName)
                    .font(.system(size: 15, weight: .semibold))
                Text(segmentSubtitle(segment))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(segment.stopCount)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.red)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func stopRow(_ stop: RoutePlanStop) -> some View {
        HStack(spacing: 10) {
            Text("\(stop.stopOrder)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.red)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(stop.displayAddress)
                    .font(.system(size: 14, weight: .medium))
                if let lat = stop.latitude, let lon = stop.longitude {
                    Text(String(format: "%.5f, %.5f", lat, lon))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func metricPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }

    private func segmentSubtitle(_ segment: RoutePlanSegment) -> String {
        let sideText = segment.side.replacingOccurrences(of: "_", with: " ").capitalized
        if let from = segment.fromHouse, let to = segment.toHouse {
            return "\(sideText) • \(from)-\(to)"
        }
        return sideText
    }

    private func formatDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000.0)
        }
        return "\(meters)m"
    }

    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            detail = try await RoutePlansAPI.shared.fetchRoutePlanDetail(routePlanId: routePlanId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RoutePlanDetailView(routePlanId: UUID())
    }
}
