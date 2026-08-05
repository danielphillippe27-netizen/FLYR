import SwiftUI

struct LeaderboardHeaderView: View {
    @Binding var selectedPeriod: TimeRange
    
    private let accentRed = Color(hex: "#FF4F4F")
    
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Menu {
                ForEach(TimeRange.allCases, id: \.rawValue) { range in
                    Button(range.displayName) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedPeriod = range
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedPeriod.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(accentRed)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    VStack {
        LeaderboardHeaderView(selectedPeriod: .constant(.monthly))
        LeaderboardHeaderView(selectedPeriod: .constant(.weekly))
    }
    .padding()
    .background(Color.bg)
}
