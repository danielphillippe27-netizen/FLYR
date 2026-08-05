import SwiftUI

enum TimeRange: String, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case allTime = "all_time"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .allTime: return "All Time"
        }
    }
}

struct LeaderboardTimeSelector: View {
    @Binding var selected: TimeRange
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimeRange.allCases, id: \.rawValue) { range in
                    TimePill(
                        title: range.displayName,
                        isSelected: selected == range
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selected = range
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

struct TimePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.flyrSystem(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .text)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(hex: "#FF5A4E") : Color.bgSecondary)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LeaderboardTimeSelector(selected: .constant(.weekly))
        .background(Color.bg)
}


