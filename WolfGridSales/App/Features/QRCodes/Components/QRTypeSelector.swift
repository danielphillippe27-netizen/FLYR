import SwiftUI

/// Component for selecting QR type
struct QRTypeSelector: View {
    @Binding var selectedType: QRType
    let onSelect: (QRType) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QR Type")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(QRType.allCases, id: \.self) { type in
                    QRTypeRow(
                        type: type,
                        isSelected: selectedType == type,
                        onTap: {
                            selectedType = type
                            onSelect(type)
                        }
                    )
                }
            }
        }
    }
}

/// Individual QR type row
private struct QRTypeRow: View {
    let type: QRType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: type.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(hex: "#FF584A") : .secondary)
                    .frame(width: 32, height: 32)
                
                // Type info
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayLabel)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(type.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#FF584A"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "#FF584A").opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "#FF584A") : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}



