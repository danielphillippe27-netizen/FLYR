import SwiftUI

/// Uber-style bottom nav: icon above label, active adapts to color scheme, inactive = light gray, no separator.
struct UberStyleTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onCreate: () -> Void
    let recordHighlight: Bool // Session tab can use filled icon when campaign selected on map
    let accentColor: Color

    private enum Tab: Int, CaseIterable {
        case home = 0, record = 1, leads = 2, leaderboard = 3

        var title: String {
            switch self {
            case .home: return "Home"
            case .record: return "Session"
            case .leads: return "Leads"
            case .leaderboard: return "Leaderboard"
            }
        }

        func icon(selected: Bool, recordHighlight: Bool) -> String {
            switch self {
            case .home: return selected ? "house.fill" : "house"
            case .record:
                return recordHighlight ? "record.circle.fill" : (selected ? "record.circle.fill" : "record.circle")
            case .leads: return "tray.full.fill"
            case .leaderboard: return "trophy.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.home)
            tabItem(.record)
            UberCreateTabItem(action: onCreate)
            tabItem(.leads)
            tabItem(.leaderboard)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(barBackground)
    }

    private func tabItem(_ tab: Tab) -> some View {
        UberTabItem(
            title: tab.title,
            icon: tab.icon(selected: selectedIndex == tab.rawValue, recordHighlight: tab == .record && recordHighlight),
            isSelected: selectedIndex == tab.rawValue,
            selectedColor: selectedColor
        ) {
            onSelect(tab.rawValue)
        }
    }

    private var selectedColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var barBackground: Color {
        colorScheme == .dark ? .darkSurface : Color(uiColor: .systemBackground)
    }
}

private struct UberTabItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let selectedColor: Color
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
        return isSelected ? selectedColor : Color(.secondaryLabel)
    }
}

private struct UberCreateTabItem: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.red)
                    .clipShape(Circle())
                Text("Create")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Uber tab bar") {
    VStack {
        Spacer()
        UberStyleTabBar(selectedIndex: 0, onSelect: { _ in }, onCreate: {}, recordHighlight: false, accentColor: .accentColor)
    }
    .background(Color(.systemGroupedBackground))
}
