import SwiftUI

struct MetricPickerView: View {
    @Binding var selectedSort: LeaderboardSortBy
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(LeaderboardSortBy.allCases, id: \.self) { metric in
                    MetricChip(
                        title: metric.displayName,
                        isSelected: selectedSort == metric
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedSort = metric
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
    }
}

struct MetricChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, weight: .semibold))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.red : Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MetricPickerView(selectedSort: .constant(.flyers))
        .padding()
}



