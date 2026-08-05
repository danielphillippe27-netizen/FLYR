import SwiftUI
import UIKit

/// Card view for displaying saved QR codes with Apple HIG styling
struct QRCardView: View {
    let qrCode: QRCode
    let entityName: String
    let addressCount: Int?
    let onPreview: () -> Void
    let onExport: () -> Void
    let onPrint: () -> Void
    let onShare: () -> Void
    
    @State private var qrImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // QR Code Preview
            HStack(spacing: 16) {
                // QR Code with Address Below
                VStack(spacing: 8) {
                    // QR Image
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .background(Color.white)
                            .cornerRadius(12)
                    } else {
                        ProgressView()
                            .frame(width: 120, height: 120)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    
                    // Address below QR code
                    if let addressName = qrCode.metadata?.entityName {
                        Text(addressName)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(width: 120)
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    // Show QR code name if set, otherwise show address/entity name
                    if let qrName = qrCode.metadata?.name, !qrName.isEmpty {
                        Text(qrName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        // Show address if available, otherwise entity name
                        if let addressName = qrCode.metadata?.entityName {
                            Text(addressName)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else {
                            Text(entityName)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        // Show address name if available (from metadata.entity_name)
                        if let addressName = qrCode.metadata?.entityName {
                            Text(addressName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        } else {
                            Text(entityName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                    }
                    
                    if let addressCount = addressCount {
                        Label("\(addressCount) addresses", systemImage: "mappin.circle")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Text(qrCode.createdAt, style: .date)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                        
                        if qrCode.metadata?.isPrinted == true {
                            Label("Printed", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 12) {
                QRActionButton(title: "Preview", icon: "eye", action: onPreview)
                QRActionButton(title: "Export", icon: "square.and.arrow.down", action: onExport)
                QRActionButton(title: "Print", icon: "printer", action: onPrint)
                QRActionButton(title: "Share", icon: "square.and.arrow.up", action: onShare)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            loadQRImage()
        }
    }
    
    private func loadQRImage() {
        if let base64Image = qrCode.qrImage,
           let imageData = Data(base64Encoded: base64Image),
           let image = UIImage(data: imageData) {
            qrImage = image
        } else if let image = QRCodeGenerator.generate(from: qrCode.qrUrl, size: CGSize(width: 200, height: 200)) {
            qrImage = image
        }
    }
}

struct QRActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .regular))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

