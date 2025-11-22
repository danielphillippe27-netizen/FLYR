import SwiftUI

struct PhaseDetailView: View {
    let phase: FarmPhase
    let touches: [FarmTouch]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Phase Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(phase.phaseName)
                        .font(.title2.weight(.bold))
                    
                    Text("\(phase.startDate, style: .date) - \(phase.endDate, style: .date)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // Metrics
                if let results = phase.results {
                    MetricsSection(results: results)
                        .padding(.horizontal)
                }
                
                // Touches
                if !touches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Touches")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ForEach(touches) { touch in
                            TouchRowView(touch: touch)
                                .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(phase.phaseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MetricsSection: View {
    let results: [String: AnyCodable]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)
            
            if let flyers = results["flyers_delivered"]?.value as? Int {
                MetricRow(label: "Flyers", value: "\(flyers)")
            }
            
            if let knocks = results["knocks"]?.value as? Int {
                MetricRow(label: "Door Knocks", value: "\(knocks)")
            }
            
            if let leads = results["leads"]?.value as? Int {
                MetricRow(label: "Leads", value: "\(leads)")
            }
            
            if let spend = results["spend"]?.value as? Double {
                MetricRow(label: "Spend", value: String(format: "$%.2f", spend))
            }
            
            if let roi = results["roi"]?.value as? Double {
                MetricRow(label: "ROI", value: String(format: "%.1fx", roi))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    NavigationStack {
        PhaseDetailView(
            phase: FarmPhase(
                farmId: UUID(),
                phaseName: "Awareness",
                startDate: Date(),
                endDate: Date().addingTimeInterval(60 * 60 * 24 * 60)
            ),
            touches: []
        )
    }
}



