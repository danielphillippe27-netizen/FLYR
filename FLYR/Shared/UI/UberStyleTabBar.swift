import SwiftUI

/// Uber-style bottom nav: dark bar, icon above label, active = red, inactive = light gray, no separator.
struct UberStyleTabBar: View {
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let recordHighlight: Bool // Session tab highlighted (e.g. red) when campaign selected on map
    let accentColor: Color

    private enum Tab: Int, CaseIterable {
        case campaigns = 0, map = 1, record = 2, leads = 3, stats = 4, settings = 5

        var title: String {
            switch self {
            case .campaigns: return "Campaigns"
            case .map: return "Map"
            case .record: return "Session"
            case .leads: return "Leads"
            case .stats: return "Stats"
            case .settings: return "More"
            }
        }

        func icon(selected: Bool, recordHighlight: Bool) -> String {
            switch self {
            case .campaigns: return "scope"
            case .map: return "map"
            case .record:
                return recordHighlight ? "record.circle.fill" : (selected ? "record.circle.fill" : "record.circle")
            case .leads: return "tray.full.fill"
            case .stats: return "chart.bar.fill"
            case .settings: return "line.3.horizontal"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { tab in
                UberTabItem(
                    title: tab.title,
                    icon: tab.icon(selected: selectedIndex == tab.rawValue, recordHighlight: tab == .record && recordHighlight),
                    isSelected: selectedIndex == tab.rawValue,
                    useAccent: tab == .record && recordHighlight
                ) {
                    onSelect(tab.rawValue)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(UIColor.systemBackground))
    }
}

private struct UberTabItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let useAccent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(foregroundColor)
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if useAccent { return Color.red }
        return isSelected ? Color.red : Color(.secondaryLabel)
    }
}

#Preview("Uber tab bar") {
    VStack {
        Spacer()
        UberStyleTabBar(selectedIndex: 0, onSelect: { _ in }, recordHighlight: false, accentColor: .accentColor)
    }
    .background(Color(.systemGroupedBackground))
}
