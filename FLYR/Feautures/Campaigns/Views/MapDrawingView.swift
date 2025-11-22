import SwiftUI
import MapboxMaps
import CoreLocation

struct MapDrawingView: View {
    let initialCenter: CLLocationCoordinate2D?
    @State private var center: CLLocationCoordinate2D?
    @State private var count: Int
    let onDone: (CLLocationCoordinate2D, Int, String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initialCenter: CLLocationCoordinate2D?, initialCount: Int = 100,
         onDone: @escaping (CLLocationCoordinate2D, Int, String) -> Void) {
        self.initialCenter = initialCenter
        _count = State(initialValue: initialCount)
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(initialViewport: .camera(center: initialCenter ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), zoom: 15))
                .onMapTapGesture { context in
                    center = context.coordinate
                }
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 16) {
                if let c = center {
                    Text("Lat: \(c.fmt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                CountSlider(value: $count)
                
                Button("Use This Location") {
                    Task { await useLocationTapped() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(center == nil)
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Draw on Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            center = initialCenter
        }
    }

    private func useLocationTapped() async {
        guard let c = center else { return }
        do {
            let label = try await GeoAPI.shared.reverseAddressString(at: c)
            onDone(c, count, label)
            dismiss()
        } catch {
            print("Reverse geocoding failed: \(error)")
            onDone(c, count, "Dropped Pin")
            dismiss()
        }
    }
}

extension CLLocationCoordinate2D {
    var fmt: String {
        "\(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))"
    }
}
