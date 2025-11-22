import SwiftUI

struct LeaderboardRow: View {
    let rank: Int
    let name: String
    let value: Double
    let isCurrentUser: Bool
    
    init(rank: Int, name: String, value: Double, isCurrentUser: Bool = false) {
        self.rank = rank
        self.name = name
        self.value = value
        self.isCurrentUser = isCurrentUser
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank
            Text("\(rank)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.muted)
                .frame(width: 40, alignment: .leading)
            
            // Name
            Text(name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.text)
                .lineLimit(1)
            
            Spacer()
            
            // Value (numeric only, no formatting)
            Text(formatValue(value))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.text)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.bg)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isCurrentUser ? Color(hex: "#FF5A4E").opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
    
    private func formatValue(_ value: Double) -> String {
        // Return numeric value only, no units
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        LeaderboardRow(rank: 1, name: "Daniel Phillippe", value: 6432)
        LeaderboardRow(rank: 2, name: "John Doe", value: 5234, isCurrentUser: true)
        LeaderboardRow(rank: 3, name: "Jane Smith", value: 4123.5)
    }
    .padding()
    .background(Color.bg)
}


