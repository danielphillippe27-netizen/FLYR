import SwiftUI

/// Component for selecting a landing page from a list
struct LandingPagePicker: View {
    let pages: [LandingPage]
    @Binding var selectedId: UUID?
    let onSelect: (UUID?) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Landing Page")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            if pages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No landing pages available")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(pages) { page in
                    LandingPagePickerRow(
                        page: page,
                        isSelected: selectedId == page.id,
                        onTap: {
                            let newSelection = selectedId == page.id ? nil : page.id
                            selectedId = newSelection
                            onSelect(newSelection)
                        }
                    )
                }
            }
        }
    }
}

/// Individual landing page row
private struct LandingPagePickerRow: View {
    let page: LandingPage
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? Color(hex: "#FF584A") : .secondary)
                
                // Page info
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let type = page.type {
                        Text(type.capitalized)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
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

