import SwiftUI

struct SuccessMetricBar: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color
    let description: String?
    
    init(
        title: String,
        value: Double,
        icon: String,
        color: Color,
        description: String? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.description = description
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16, weight: .medium))
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.text)
                
                Spacer()
                
                Text("\(String(format: "%.1f", value))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.muted)
            }
            
            if let description = description {
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.muted)
            }
            
            ProgressView(value: min(value / 100.0, 1.0))
                .tint(color)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
        }
        .padding(.vertical, 4)
    }
}





