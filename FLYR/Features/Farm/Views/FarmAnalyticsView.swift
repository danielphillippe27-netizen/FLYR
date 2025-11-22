import SwiftUI

struct FarmAnalyticsView: View {
    @StateObject private var viewModel: FarmAnalyticsViewModel
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
        _viewModel = StateObject(wrappedValue: FarmAnalyticsViewModel(farmId: farmId))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let funnel = viewModel.funnelData {
                        FunnelCard(data: funnel)
                    }
                    
                    if !viewModel.touchEffectiveness.isEmpty {
                        TouchEffectivenessCard(data: viewModel.touchEffectiveness)
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.calculateFunnel()
                await viewModel.analyzeTouchTypes()
            }
        }
    }
}

struct FunnelCard: View {
    let data: FunnelData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Funnel")
                .font(.headline)
            
            FunnelRow(label: "Touches", value: data.touches)
            FunnelRow(label: "Completed", value: data.completedTouches)
            FunnelRow(label: "Scans", value: data.scans)
            FunnelRow(label: "Leads", value: data.leads)
            FunnelRow(label: "Appointments", value: data.appointments)
            FunnelRow(label: "Listings", value: data.listings)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct FunnelRow: View {
    let label: String
    let value: Int
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
        }
    }
}

struct TouchEffectivenessCard: View {
    let data: [TouchEffectiveness]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Touch Effectiveness")
                .font(.headline)
            
            ForEach(data, id: \.type) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.type.displayName)
                        Spacer()
                        Text("\(item.leads) leads")
                            .fontWeight(.semibold)
                    }
                    ProgressView(value: item.completionRate)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    FarmAnalyticsView(farmId: UUID())
}



