import SwiftUI

/// A capsule badge showing campaign type
struct CampaignTypeLabel: View {
    let type: CampaignType
    let size: Size
    
    enum Size {
        case small
        case medium
        case large
        
        var fontSize: Font {
            switch self {
            case .small: return .caption
            case .medium: return .label
            case .large: return .subheading
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .medium: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .large: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
            }
        }
    }
    
    init(type: CampaignType, size: Size = .medium) {
        self.type = type
        self.size = size
    }
    
    var body: some View {
        Text(type.title)
            .font(size.fontSize)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(size.padding)
            .background(backgroundColor)
            .cornerRadius(16)
    }
    
    private var backgroundColor: Color {
        switch type {
        case .flyer: return .green
        case .doorKnock: return .blue
        case .event: return .flyrPrimary
        case .survey: return .purple
        case .gift: return .pink
        case .popBy: return .cyan
        case .openHouse: return .brown
        case .letters: return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            CampaignTypeLabel(type: .flyer, size: .small)
            CampaignTypeLabel(type: .doorKnock, size: .medium)
            CampaignTypeLabel(type: .event, size: .large)
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Small")
            CampaignTypeLabel(type: .flyer, size: .small)
            
            Text("Medium")
            CampaignTypeLabel(type: .doorKnock, size: .medium)
            
            Text("Large")
            CampaignTypeLabel(type: .event, size: .large)
        }
    }
    .padding()
}
