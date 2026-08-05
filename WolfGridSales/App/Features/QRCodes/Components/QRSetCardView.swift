import SwiftUI

/// Apple-style card view for displaying a QR Set
struct QRSetCardView: View {
    let qrSet: QRSet
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with icon and name
                HStack(spacing: 12) {
                    // QR Icon
                    Image(systemName: "qrcode")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.bgSecondary)
                        )
                    
                    // Set name
                    Text(qrSet.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                
                // Stats row
                HStack(spacing: 16) {
                    // Total codes
                    Label {
                        Text("\(qrSet.totalAddresses)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    } icon: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    if qrSet.variantCount > 0 {
                        // Variant count
                        Label {
                            Text("\(qrSet.variantCount) variants")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // Updated date
                    Text(updatedDateString)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.border.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var updatedDateString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: qrSet.updatedAt, relativeTo: Date())
    }
}

