import SwiftUI

/// Empty state component for QR code creation
struct QREmptyState: View {
    let message: String
    
    init(message: String = "Create QR codes for your campaign or farm.") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
                .opacity(0.6)
            
            VStack(spacing: 8) {
                Text("No QR Codes")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(message)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}



