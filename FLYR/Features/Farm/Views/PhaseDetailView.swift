import SwiftUI

struct CycleDetailView: View {
    let cycle: FarmCycle
    let touches: [FarmTouch]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cycle Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(cycle.cycleName)
                        .font(.flyrTitle2Bold)

                    Text("\(cycle.startDate, style: .date) - \(cycle.endDate, style: .date)")
                        .font(.flyrSubheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // Metrics
                if let results = cycle.results {
                    MetricsSection(results: results)
                        .padding(.horizontal)
                }
                
                // Touches
                if !touches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Touches")
                            .font(.flyrHeadline)
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
        .navigationTitle(cycle.cycleName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MetricsSection: View {
    let results: [String: AnyCodable]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.flyrHeadline)
            
            if let flyers = results["flyers_delivered"]?.value as? Int {
                MetricRow(label: "Flyers", value: "\(flyers)")
            }
            
            if let knocks = results["knocks"]?.value as? Int {
                MetricRow(label: "Door Knock", value: "\(knocks)")
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
        CycleDetailView(
            cycle: FarmCycle(
                farmId: UUID(),
                cycleNumber: 1,
                startDate: Date(),
                endDate: Date().addingTimeInterval(60 * 60 * 24 * 60),
                touchCount: 0,
                completedTouchCount: 0
            ),
            touches: []
        )
    }
}

