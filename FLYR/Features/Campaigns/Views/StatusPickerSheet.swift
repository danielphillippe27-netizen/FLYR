import SwiftUI

/// Bottom sheet for selecting address status
struct StatusPickerSheet: View {
    let addressLabel: String
    let currentStatus: AddressStatus
    let onSelect: (AddressStatus) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Drag handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(addressLabel)
                        .font(.flyrHeadline)
                        .foregroundColor(.primary)
                    
                    Text("Update door status")
                        .font(.flyrSubheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                
                // Status options grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(AddressStatus.allCases, id: \.self) { status in
                            StatusButton(
                                status: status,
                                isSelected: status == currentStatus,
                                onTap: {
                                    onSelect(status)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Individual status button
private struct StatusButton: View {
    let status: AddressStatus
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: status.iconName)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(isSelected ? .white : status.tintColor)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(isSelected ? status.tintColor : status.tintColor.opacity(0.1))
                    )
                
                // Status name
                Text(status.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Description
                Text(status.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? status.tintColor.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? status.tintColor : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    StatusPickerSheet(
        addressLabel: "123 Main Street, Toronto, ON",
        currentStatus: .none,
        onSelect: { _ in }
    )
}

