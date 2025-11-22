import SwiftUI
import UIKit

/// Variant card component showing URL and actions for A/B test variant
struct ABTestVariantCard: View {
    let variant: ExperimentVariant
    let onCopyURL: () -> Void
    let onDownloadPNG: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Variant \(variant.key)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Use this URL in Design \(variant.key)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // URL Display
            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Text(variant.fullURL)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(Color.bgSecondary)
                    .cornerRadius(8)
            }
            
            // Actions
            HStack(spacing: 12) {
                Button(action: onCopyURL) {
                    Label("Copy URL", systemImage: "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.bgSecondary)
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                
                Button(action: onDownloadPNG) {
                    Label("Download QR PNG", systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "FF4B47"))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
    }
}

#Preview {
    ABTestVariantCard(
        variant: ExperimentVariant(
            id: UUID(),
            experimentId: UUID(),
            key: "A",
            urlSlug: "abc123def456"
        ),
        onCopyURL: {},
        onDownloadPNG: {}
    )
    .padding()
    .background(Color.bg)
}

