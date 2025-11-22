import SwiftUI

// MARK: - Stat Pill Component

struct StatPill: View {
    let value: String
    let label: String
    let hasAccentHighlight: Bool
    let size: StatPillSize
    
    init(
        value: String,
        label: String,
        hasAccentHighlight: Bool = false,
        size: StatPillSize = .regular
    ) {
        self.value = value
        self.label = label
        self.hasAccentHighlight = hasAccentHighlight
        self.size = size
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(size.valueFont)
                .fontWeight(.semibold)
                .foregroundColor(hasAccentHighlight ? .accent : .text)
            
            Text(label)
                .font(size.labelFont)
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat Pill Size

enum StatPillSize {
    case compact
    case regular
    case large
    
    var valueFont: Font {
        switch self {
        case .compact:
            return .system(size: 16, weight: .semibold)
        case .regular:
            return .system(size: 20, weight: .semibold)
        case .large:
            return .system(size: 24, weight: .semibold)
        }
    }
    
    var labelFont: Font {
        switch self {
        case .compact:
            return .system(size: 11, weight: .regular)
        case .regular:
            return .system(size: 13, weight: .regular)
        case .large:
            return .system(size: 15, weight: .regular)
        }
    }
}

// MARK: - Stat Grid

struct StatGrid: View {
    let stats: [StatPill]
    let columns: Int
    
    init(stats: [StatPill], columns: Int = 3) {
        self.stats = stats
        self.columns = columns
    }
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 16) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                stat
                    .staggeredAnimation(delay: Double(index) * Animation.staggerDelay)
            }
        }
    }
}

// MARK: - View Extensions

extension View {
    /// Create a stat pill with the given value and label
    func statPill(
        value: String,
        label: String,
        hasAccentHighlight: Bool = false,
        size: StatPillSize = .regular
    ) -> some View {
        StatPill(
            value: value,
            label: label,
            hasAccentHighlight: hasAccentHighlight,
            size: size
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        // Individual stat pills
        HStack(spacing: 16) {
            StatPill(value: "1,234", label: "Total Flyers")
            StatPill(value: "456", label: "Scans", hasAccentHighlight: true)
            StatPill(value: "78", label: "Conversions")
        }
        
        // Different sizes
        HStack(spacing: 16) {
            StatPill(value: "12", label: "Today", size: .compact)
            StatPill(value: "89", label: "This Week", size: .regular)
            StatPill(value: "1,234", label: "All Time", hasAccentHighlight: true, size: .large)
        }
        
        // Stat grid
        StatGrid(stats: [
            StatPill(value: "1,234", label: "Total Flyers"),
            StatPill(value: "456", label: "Scans", hasAccentHighlight: true),
            StatPill(value: "78", label: "Conversions"),
            StatPill(value: "37%", label: "Conversion Rate"),
            StatPill(value: "12", label: "Active Routes"),
            StatPill(value: "5", label: "Completed")
        ])
    }
    .padding()
    .background(Color.bgSecondary)
}
