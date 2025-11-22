import SwiftUI

// MARK: - Segmented Control Component

struct SegmentedControl<SelectionValue: Hashable>: View {
    let options: [SegmentedOption<SelectionValue>]
    @Binding var selection: SelectionValue
    
    @State private var indicatorOffset: CGFloat = 0
    @State private var indicatorWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    init(
        options: [SegmentedOption<SelectionValue>],
        selection: Binding<SelectionValue>
    ) {
        self.options = options
        self._selection = selection
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.bgSecondary)
                    .frame(height: 40)
                
                // Selection indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accent)
                    .frame(width: indicatorWidth, height: 32)
                    .offset(x: indicatorOffset)
                    .animation(
                        reduceMotion ? .reducedMotion : .flyrSpring,
                        value: indicatorOffset
                    )
                    .animation(
                        reduceMotion ? .reducedMotion : .flyrSpring,
                        value: indicatorWidth
                    )
                
                // Options
                HStack(spacing: 0) {
                    ForEach(options, id: \.value) { option in
                        Button(action: {
                            withAnimation(reduceMotion ? .reducedMotion : .flyrSpring) {
                                selection = option.value
                            }
                            HapticManager.lightImpact()
                        }) {
                            Text(option.title)
                                .font(.label)
                                .foregroundColor(selection == option.value ? .white : .text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .frame(height: 40)
        .onAppear {
            updateIndicator()
        }
        .onChange(of: selection) { _, _ in
            updateIndicator()
        }
    }
    
    private func updateIndicator() {
        guard let selectedIndex = options.firstIndex(where: { $0.value == selection }) else { return }
        
        let optionWidth = 1.0 / Double(options.count)
        let totalWidth = UIScreen.main.bounds.width - 40 // Approximate, will be updated by GeometryReader
        
        indicatorWidth = totalWidth * optionWidth - 8 // 8pt padding
        indicatorOffset = CGFloat(selectedIndex) * (totalWidth * optionWidth) + 4 // 4pt offset
    }
}

// MARK: - Segmented Option

struct SegmentedOption<Value: Hashable> {
    let title: String
    let value: Value
    
    init(_ title: String, value: Value) {
        self.title = title
        self.value = value
    }
}

// MARK: - Convenience Initializers

extension SegmentedControl where SelectionValue == String {
    init(
        options: [String],
        selection: Binding<String>
    ) {
        let segmentedOptions = options.map { SegmentedOption($0, value: $0) }
        self.init(options: segmentedOptions, selection: selection)
    }
}

extension SegmentedControl where SelectionValue == Int {
    init(
        options: [String],
        selection: Binding<Int>
    ) {
        let segmentedOptions = options.enumerated().map { index, title in
            SegmentedOption(title, value: index)
        }
        self.init(options: segmentedOptions, selection: selection)
    }
}

// MARK: - View Extension

extension View {
    /// Create a segmented control with string options
    func segmentedControl(
        options: [String],
        selection: Binding<String>
    ) -> some View {
        SegmentedControl(options: options, selection: selection)
    }
    
    /// Create a segmented control with custom options
    func segmentedControl<SelectionValue: Hashable>(
        options: [SegmentedOption<SelectionValue>],
        selection: Binding<SelectionValue>
    ) -> some View {
        SegmentedControl(options: options, selection: selection)
    }
}

// MARK: - Preview

#Preview {
    SegmentedControlPreview()
}

struct SegmentedControlPreview: View {
    @State private var selectedTab = "Today"
    @State private var selectedFilter = 0
    @State private var selectedStatus = CampaignStatus.active
    
    enum CampaignStatus: String, CaseIterable {
        case active = "active"
        case completed = "completed"
        case draft = "draft"
        
        var displayName: String {
            switch self {
            case .active: return "Active"
            case .completed: return "Completed"
            case .draft: return "Draft"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // String-based segmented control
            SegmentedControl(
                options: ["Today", "Week", "All Time"],
                selection: $selectedTab
            )
            .padding(.horizontal, 20)
            
            // Custom value segmented control
            SegmentedControl(
                options: ["Active", "Completed", "Draft"],
                selection: $selectedFilter
            )
            .padding(.horizontal, 20)
            
            // With custom options
            SegmentedControl(
                options: CampaignStatus.allCases.map { status in
                    SegmentedOption(status.displayName, value: status)
                },
                selection: $selectedStatus
            )
            .padding(.horizontal, 20)
            
            Text("Selected: \(selectedTab) | \(selectedFilter) | \(selectedStatus.displayName)")
                .bodyText()
                .foregroundColor(.muted)
        }
        .padding()
        .background(Color.bgSecondary)
    }
}
