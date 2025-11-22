import SwiftUI

/// Stateless analytics summary card
struct QRAnalyticsCard: View {
    let summary: QRCodeAnalyticsSummary
    
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Summary")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("\(summary.totalScans)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.accent)
                        Text("Total Scans")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("\(summary.addressCount)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.accent)
                        Text("Addresses")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

