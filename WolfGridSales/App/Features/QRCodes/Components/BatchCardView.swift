import SwiftUI
import UIKit

/// Card view for displaying batch QR codes with PDF preview
struct BatchCardView: View {
    let batch: QRCodeBatch
    let onPreview: () -> Void
    let onExport: () -> Void
    let onPrint: () -> Void
    let onShare: () -> Void
    
    @State private var previewImage: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Batch Preview
            HStack(spacing: 16) {
                // PDF Preview Image
                VStack(spacing: 8) {
                    if let previewImage = previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 120, height: 160)
                            .background(Color.white)
                            .cornerRadius(12)
                    } else {
                        ProgressView()
                            .frame(width: 120, height: 160)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(batch.batchName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Label("\(batch.count) QR codes", systemImage: "qrcode")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        Text(batch.createdAt, style: .date)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
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
            loadPreviewImage()
        }
    }
    
    private func loadPreviewImage() {
        if let base64Image = batch.previewImage,
           let imageData = Data(base64Encoded: base64Image),
           let image = UIImage(data: imageData) {
            previewImage = image
        }
    }
}

