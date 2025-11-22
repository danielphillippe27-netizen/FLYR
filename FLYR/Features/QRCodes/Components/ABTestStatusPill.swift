import SwiftUI

/// Status pill component for A/B test experiments
struct ABTestStatusPill: View {
    let status: String
    
    var body: some View {
        Text(statusText)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusBackgroundColor)
            .clipShape(Capsule())
    }
    
    private var statusText: String {
        switch status.lowercased() {
        case "draft":
            return "DRAFT"
        case "running":
            return "RUNNING"
        case "completed":
            return "COMPLETED"
        default:
            return status.uppercased()
        }
    }
    
    private var statusColor: Color {
        switch status.lowercased() {
        case "draft":
            return .secondary
        case "running":
            return Color(hex: "FF4B47")
        case "completed":
            return .green
        default:
            return .secondary
        }
    }
    
    private var statusBackgroundColor: Color {
        switch status.lowercased() {
        case "draft":
            return Color.secondary.opacity(0.15)
        case "running":
            return Color(hex: "FF4B47").opacity(0.15)
        case "completed":
            return Color.green.opacity(0.15)
        default:
            return Color.secondary.opacity(0.15)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ABTestStatusPill(status: "draft")
        ABTestStatusPill(status: "running")
        ABTestStatusPill(status: "completed")
    }
    .padding()
    .background(Color.bg)
}

