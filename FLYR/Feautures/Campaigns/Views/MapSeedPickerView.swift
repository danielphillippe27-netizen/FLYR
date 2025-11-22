import SwiftUI
import MapboxMaps
import CoreLocation

struct MapSeedPickerView: View {
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
        CountSlider(value: $count)
        Button {
          guard let c = center ?? initialCenter else { return }
          Task {
            let label = (try? await GeoAPI.shared.reverseAddressString(at: c)) ?? "Dropped Pin"
            onDone(c, count, label)
            dismiss()
          }
        } label: { Text("Use this location").frame(maxWidth: .infinity) }
        .buttonStyle(.borderedProminent)
      }
      .padding(16)
      .background(.ultraThinMaterial)
    }
    .navigationTitle("Pick on Map")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
    }
    .onAppear {
      center = initialCenter
    }
  }
}
