import SwiftUI

enum MetricType: String, CaseIterable {
    case flyers = "flyers"
    case leads = "leads"
    case conversations = "conversations"
    case appointments = "appointments"
    case deals = "deals"
    case doorknocks = "doorknocks"
    case distance = "distance"
    
    var displayName: String {
        switch self {
        case .flyers: return "Flyers"
        case .leads: return "Leads"
        case .conversations: return "Conversations"
        case .appointments: return "Appointments"
        case .deals: return "Deals"
        case .doorknocks: return "Doorknocks"
        case .distance: return "Distance"
        }
    }
    
    // Get next metric in cycle
    func next() -> MetricType {
        let allCases = MetricType.allCases
        if let currentIndex = allCases.firstIndex(of: self),
           currentIndex < allCases.count - 1 {
            return allCases[currentIndex + 1]
        }
        return allCases[0]
    }
}

struct LeaderboardMetricSelector: View {
    @Binding var selected: String
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MetricType.allCases, id: \.rawValue) { metric in
                    MetricPill(
                        title: metric.displayName,
                        isSelected: selected == metric.rawValue
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selected = metric.rawValue
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
}

struct MetricPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : .text)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(hex: "#FF5A4E") : Color.bgSecondary)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    LeaderboardMetricSelector(selected: .constant("conversations"))
        .background(Color.black)
}

