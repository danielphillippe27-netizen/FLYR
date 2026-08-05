import SwiftUI

/// Stateless QR code list component
struct QRCodeList: View {
    let qrCodes: [QRCodeAddress]
    let onQRCodeTap: (QRCodeAddress) -> Void
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 160), spacing: 20)
            ], spacing: 20) {
                ForEach(qrCodes) { qrCode in
                    QRCard(qr: qrCode, onTap: {
                        onQRCodeTap(qrCode)
                    })
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 10)
        }
    }
}

