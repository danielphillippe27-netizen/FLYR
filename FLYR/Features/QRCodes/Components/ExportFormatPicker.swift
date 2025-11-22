import SwiftUI

/// Component for selecting export format
struct ExportFormatPicker: View {
    @Binding var selectedFormat: ExportFormat
    let onSelect: (ExportFormat) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Format")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    ExportFormatRow(
                        format: format,
                        isSelected: selectedFormat == format,
                        onTap: {
                            selectedFormat = format
                            onSelect(format)
                        }
                    )
                }
            }
        }
    }
}

/// Individual export format row
private struct ExportFormatRow: View {
    let format: ExportFormat
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: format.iconName)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(hex: "#FF584A") : .secondary)
                    .frame(width: 32, height: 32)
                
                // Format info
                VStack(alignment: .leading, spacing: 4) {
                    Text(format.displayLabel)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(format.description)
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



