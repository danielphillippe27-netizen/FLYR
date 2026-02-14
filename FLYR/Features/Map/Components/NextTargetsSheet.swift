import SwiftUI
import CoreLocation

/// Redesigned sheet for next targets: same data and callbacks as NextTargetsBottomSheet, with improved presentation.
struct NextTargetsSheet: View {
    @ObservedObject var sessionManager: SessionManager
    let buildingCentroids: [String: CLLocation]
    let targetBuildings: [String]
    let addressLabels: [String: String]
    let onBuildingTapped: (String) -> Void
    let onCompleteTapped: (String) -> Void
    let onUndoTapped: (String) -> Void

    private var sortedRows: [TargetBuildingRow] {
        guard let userLocation = sessionManager.currentLocation else {
            return targetBuildings.map { id in
                TargetBuildingRow(
                    id: id,
                    buildingId: id,
                    address: addressLabels[id] ?? "Building",
                    distanceMeters: .infinity,
                    centroid: CLLocationCoordinate2D(latitude: 0, longitude: 0)
                )
            }
        }
        return targetBuildings
            .map { id -> TargetBuildingRow? in
                let centroid = buildingCentroids[id]
                let coord = centroid?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                let distance = centroid.map { userLocation.distance(from: $0) } ?? .infinity
                return TargetBuildingRow(
                    id: id,
                    buildingId: id,
                    address: addressLabels[id] ?? "Building",
                    distanceMeters: distance,
                    centroid: coord
                )
            }
            .compactMap { $0 }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 6)
                .padding(.top, 12)

            HStack {
                Text("Next Targets")
                    .font(.flyrTitle2Bold)
                Spacer()
                Text("\(sessionManager.remainingCount) remaining")
                    .font(.flyrSubheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if sortedRows.isEmpty {
                        Text("No target buildings for this session")
                            .font(.flyrSubheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else {
                        ForEach(sortedRows) { row in
                            TargetBuildingRowView(
                                building: row,
                                isCompleted: sessionManager.completedBuildings.contains(row.buildingId),
                                onTap: { onBuildingTapped(row.buildingId) },
                                onComplete: { onCompleteTapped(row.buildingId) },
                                onUndo: { onUndoTapped(row.buildingId) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(.ultraThinMaterial)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
