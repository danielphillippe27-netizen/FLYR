import SwiftUI

struct MapStyleToggleButton: View {
    @Binding var mapStyleMode: MapStyle
    
    var body: some View {
        Button {
            cycleMapStyle()
        } label: {
            Image(systemName: mapStyleMode.iconName)
                .font(.title2)
                .foregroundColor(.white)
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
        .contextMenu {  // long press = popover
            ForEach(MapStyle.allCases) { style in
                Button {
                    mapStyleMode = style
                } label: {
                    Label(style.title, systemImage: style.iconName)
                }
            }
        }
    }
    
    private func cycleMapStyle() {
        let all = MapStyle.allCases
        if let index = all.firstIndex(of: mapStyleMode) {
            let next = (index + 1) % all.count
            mapStyleMode = all[next]
        }
    }
}


