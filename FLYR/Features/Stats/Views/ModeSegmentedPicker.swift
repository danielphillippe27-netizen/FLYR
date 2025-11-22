import SwiftUI

struct ModeSegmentedPicker: View {
    @Binding var selectedTab: StatsPageTab
    
    var body: some View {
        Picker("Stats View", selection: $selectedTab) {
            ForEach(StatsPageTab.allCases, id: \.self) { tab in
                Text(tab.rawValue)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }
}

#Preview {
    ModeSegmentedPicker(selectedTab: .constant(.leaderboard))
        .padding()
}



