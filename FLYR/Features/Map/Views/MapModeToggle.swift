import SwiftUI

/// Apple-style segmented control for switching map modes
struct MapModeToggle: View {
    @Binding var mode: MapMode
    
    var body: some View {
        Picker("Map Mode", selection: $mode) {
            ForEach(MapMode.allCases, id: \.self) { mapMode in
                Text(mapMode.displayName)
                    .tag(mapMode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
}



