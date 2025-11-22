import SwiftUI

/// Statistics card component for A/B test experiment
struct ABTestStatsCard: View {
    let stats: ExperimentScanStats
    let variantA: ExperimentVariant?
    let variantB: ExperimentVariant?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Statistics")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            
            // Scans
            StatRow(
                title: "Scans",
                variantAValue: stats.variantA_scans,
                variantBValue: stats.variantB_scans,
                winner: stats.winner,
                showWinner: stats.variantA_scans != stats.variantB_scans
            )
            
            // Unique Visitors
            StatRow(
                title: "Unique Visitors",
                variantAValue: stats.variantA_unique,
                variantBValue: stats.variantB_unique,
                winner: stats.winner,
                showWinner: stats.variantA_unique != stats.variantB_unique
            )
            
            // Conversions
            StatRow(
                title: "Conversions",
                variantAValue: stats.variantA_conversions,
                variantBValue: stats.variantB_conversions,
                winner: stats.winner,
                showWinner: stats.variantA_conversions != stats.variantB_conversions
            )
            
            // Conversion Rates
            if stats.variantA_scans > 0 || stats.variantB_scans > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conversion Rate")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Variant A")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text("\(Int(stats.variantA_conversionRate * 100))%")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(stats.winner == "A" ? Color(hex: "FF4B47") : .primary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Variant B")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Text("\(Int(stats.variantB_conversionRate * 100))%")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(stats.winner == "B" ? Color(hex: "FF4B47") : .primary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let title: String
    let variantAValue: Int
    let variantBValue: Int
    let winner: String?
    let showWinner: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Variant A")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("\(variantAValue)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(showWinner && winner == "A" ? Color(hex: "FF4B47") : .primary)
                        
                        if showWinner && winner == "A" {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "FF4B47"))
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Variant B")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        if showWinner && winner == "B" {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "FF4B47"))
                        }
                        
                        Text("\(variantBValue)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(showWinner && winner == "B" ? Color(hex: "FF4B47") : .primary)
                    }
                }
            }
        }
    }
}

#Preview {
    ABTestStatsCard(
        stats: ExperimentScanStats(
            variantA_scans: 150,
            variantB_scans: 120,
            variantA_unique: 100,
            variantB_unique: 85,
            variantA_conversions: 15,
            variantB_conversions: 10
        ),
        variantA: ExperimentVariant(
            id: UUID(),
            experimentId: UUID(),
            key: "A",
            urlSlug: "abc123"
        ),
        variantB: ExperimentVariant(
            id: UUID(),
            experimentId: UUID(),
            key: "B",
            urlSlug: "def456"
        )
    )
    .padding()
    .background(Color.bg)
}

