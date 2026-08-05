import SwiftUI

struct ContactFiltersView: View {
    @Binding var filterStatus: ContactStatus?
    @Binding var filterCampaignId: UUID?
    @Binding var filterFarmId: UUID?
    let onClear: () -> Void
    let hasActiveFilters: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Filters")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.text)
                
                Spacer()
                
                if hasActiveFilters {
                    Button("Clear All", action: onClear)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accent)
                }
            }
            
            // Status Filter
            VStack(alignment: .leading, spacing: 12) {
                Text("Status")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.text)
                
                HStack(spacing: 8) {
                    ForEach(ContactStatus.allCases, id: \.self) { status in
                        FilterChip(
                            text: status.displayName,
                            isSelected: filterStatus == status,
                            color: status.color
                        ) {
                            filterStatus = filterStatus == status ? nil : status
                        }
                    }
                }
            }
            
            // Campaign Filter (placeholder - would need campaign list)
            VStack(alignment: .leading, spacing: 12) {
                Text("Campaign")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.text)
                
                Text("Campaign filtering coming soon")
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
                    .padding(.vertical, 8)
            }
            
            // Farm Filter (placeholder - would need farm list)
            VStack(alignment: .leading, spacing: 12) {
                Text("Farm")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.text)
                
                Text("Farm filtering coming soon")
                    .font(.system(size: 13))
                    .foregroundColor(.muted)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(Color.bg)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let text: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : Color.gray.opacity(0.15))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ContactFiltersView(
        filterStatus: .constant(.hot),
        filterCampaignId: .constant(nil),
        filterFarmId: .constant(nil),
        onClear: {},
        hasActiveFilters: true
    )
    .background(Color.bgSecondary)
}





