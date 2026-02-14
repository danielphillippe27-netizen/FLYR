import SwiftUI

enum Timeframe: String, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case allTime = "all_time"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .allTime: return "All Time"
        }
    }
}

struct TimeFilterPicker: View {
    @Binding var selectedTimeframe: String
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Timeframe.allCases, id: \.self) { timeframe in
                    TimeChip(
                        title: timeframe.displayName,
                        isSelected: selectedTimeframe == timeframe.rawValue
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedTimeframe = timeframe.rawValue
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
    }
}

struct TimeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.flyrSubheadline)
                .foregroundColor(isSelected ? .white : .muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentDefault : Color.bgSecondary)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TimeFilterPicker(selectedTimeframe: .constant("weekly"))
        .padding()
}


