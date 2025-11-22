import SwiftUI

struct StatCard: View {
    let icon: String
    let color: Color
    let title: String
    let value: Any
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 28, weight: .medium))
            
            Text("\(formatValue(value))")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.text)
            
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.bgSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func formatValue(_ value: Any) -> String {
        if let intValue = value as? Int {
            return "\(intValue)"
        } else if let doubleValue = value as? Double {
            return String(format: "%.1f", doubleValue)
        } else {
            return "\(value)"
        }
    }
}





