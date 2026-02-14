import SwiftUI

/// Stateless scan history item component
struct QRScanItem: View {
    let scan: QRCodeScan
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.scannedAt, style: .relative)
                    .font(.flyrSubheadline)
                    .foregroundColor(.primary)
                
                if let device = scan.deviceInfo {
                    Text(device)
                        .font(.flyrCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "qrcode.viewfinder")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

