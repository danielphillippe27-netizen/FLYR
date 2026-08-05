import SwiftUI

/// Segmented picker for selecting between Campaigns and Farms
struct QRSourcePicker: View {
    @Binding var selectedSource: QRSourceType
    
    var body: some View {
        Picker("Source", selection: $selectedSource) {
            ForEach(QRSourceType.allCases, id: \.self) { source in
                Text(source.displayName).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Source type for QR code creation
enum QRSourceType: String, CaseIterable {
    case campaigns = "Campaigns"
    case farms = "Farms"
}

