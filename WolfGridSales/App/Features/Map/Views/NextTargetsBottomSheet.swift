import SwiftUI
import CoreLocation

/// Bottom sheet listing next target buildings sorted by proximity; tap to focus map, tap check to complete, swipe to undo
struct NextTargetsBottomSheet: View {
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
                .padding(.top, 8)

            HStack {
                Text("Next Targets")
                    .font(.flyrHeadline)
                Spacer()
                Text("\(sessionManager.remainingCount) remaining")
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }
            .padding()

            ScrollView {
                LazyVStack(spacing: 8) {
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
                .padding(.horizontal)
            }
        }
        .background(.ultraThinMaterial)
    }
}

struct TargetBuildingRow: Identifiable {
    let id: String
    let buildingId: String
    let address: String
    let distanceMeters: Double
    let centroid: CLLocationCoordinate2D
}

struct TargetBuildingRowView: View {
    let building: TargetBuildingRow
    let isCompleted: Bool
    let onTap: () -> Void
    let onComplete: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isCompleted ? .green : .gray)
                .font(.flyrTitle3)

            VStack(alignment: .leading, spacing: 2) {
                Text(building.address)
                    .font(.body)
                    .lineLimit(2)
                Text(distanceText)
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isCompleted {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(.flyrCaption)
                        .foregroundColor(.flyrPrimary)
                }
            } else {
                Button(action: onComplete) {
                    Image(systemName: "checkmark")
                        .padding(8)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(isCompleted ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var distanceText: String {
        if building.distanceMeters == .infinity || building.distanceMeters < 0 {
            return "—"
        }
        if building.distanceMeters >= 1000 {
            return String(format: "%.1f km away", building.distanceMeters / 1000)
        }
        return String(format: "%.0f m away", building.distanceMeters)
    }
}
