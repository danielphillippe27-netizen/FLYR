import SwiftUI
import CoreLocation

struct FarmDetailView: View {
    @StateObject private var viewModel: FarmDetailViewModel
    @State private var showCalendar = false
    @State private var showMap = false
    @State private var showAnalytics = false
    
    let farmId: UUID
    
    init(farmId: UUID) {
        self.farmId = farmId
        _viewModel = StateObject(wrappedValue: FarmDetailViewModel(farmId: farmId))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let farm = viewModel.farm {
                    // Farm Summary Card
                    FarmSummaryCard(farm: farm)
                        .padding(.horizontal, 16)
                    
                    // Upcoming Touches
                    if !viewModel.upcomingTouches.isEmpty {
                        SectionHeader(title: "Upcoming Touches", icon: "calendar")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.upcomingTouches.prefix(5)) { touch in
                            TouchRowView(touch: touch)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // Map Preview
                    if let polygon = farm.polygonCoordinates {
                        SectionHeader(title: "Farm Map", icon: "map")
                            .padding(.horizontal, 16)
                        
                        Button {
                            showMap = true
                        } label: {
                            FarmMapPreview(polygon: polygon)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Phases
                    if !viewModel.phases.isEmpty {
                        SectionHeader(title: "Phases", icon: "chart.bar")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.phases) { phase in
                            PhaseCard(phase: phase)
                                .padding(.horizontal, 16)
                        }
                    } else {
                        Button {
                            Task {
                                await viewModel.generatePhases()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                Text("Generate Phases")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Leads
                    if !viewModel.leads.isEmpty {
                        SectionHeader(title: "Leads", icon: "person.2")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.leads.prefix(5)) { lead in
                            LeadRowView(lead: lead)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    // Recommendations
                    if !viewModel.recommendations.isEmpty {
                        SectionHeader(title: "Recommendations", icon: "lightbulb")
                            .padding(.horizontal, 16)
                        
                        ForEach(viewModel.recommendations) { rec in
                            RecommendationCard(recommendation: rec)
                                .padding(.horizontal, 16)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(viewModel.farm?.name ?? "Farm")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showCalendar = true
                    } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                    
                    Button {
                        showMap = true
                    } label: {
                        Label("Map", systemImage: "map")
                    }
                    
                    Button {
                        showAnalytics = true
                    } label: {
                        Label("Analytics", systemImage: "chart.bar")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showCalendar) {
            if let farm = viewModel.farm {
                FarmCalendarView(farmId: farm.id)
            }
        }
        .sheet(isPresented: $showMap) {
            if let farm = viewModel.farm {
                FarmMapView(farmId: farm.id)
            }
        }
        .sheet(isPresented: $showAnalytics) {
            if let farm = viewModel.farm {
                FarmAnalyticsView(farmId: farm.id)
            }
        }
        .task {
            await viewModel.loadFarmData()
        }
        .refreshable {
            await viewModel.loadFarmData()
        }
    }
}

// MARK: - Farm Summary Card

struct FarmSummaryCard: View {
    let farm: Farm
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(farm.name)
                    .font(.flyrTitle2Bold)
                
                Spacer()
                
                Badge(text: farm.isActive ? "Active" : "Completed")
            }
            
            Text("\(farm.startDate, formatter: dateFormatter) - \(farm.endDate, formatter: dateFormatter)")
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Label("\(farm.frequency) touches/month", systemImage: "calendar")
                Spacer()
                Label("\(Int(farm.progress * 100))% complete", systemImage: "chart.pie")
            }
            .font(.flyrSubheadline)
            .foregroundStyle(.secondary)
            
            ProgressView(value: farm.progress)
                .tint(.red)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(title)
                .font(.flyrHeadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Touch Row View

struct TouchRowView: View {
    let touch: FarmTouch
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: touch.type.iconName)
                .foregroundColor(colorForTouchType(touch.type))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(touch.title)
                    .font(.flyrSubheadline)
                
                Text(touch.date, formatter: dateFormatter)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if touch.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    private func colorForTouchType(_ type: FarmTouchType) -> Color {
        switch type {
        case .flyer: return .blue
        case .doorKnock: return .green
        case .event: return .flyrPrimary
        case .newsletter: return .purple
        case .ad: return .yellow
        case .custom: return .gray
        }
    }
}

// MARK: - Phase Card

struct PhaseCard: View {
    let phase: FarmPhase
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(phase.phaseName)
                .font(.flyrHeadline)
            
            Text("\(phase.startDate, style: .date) - \(phase.endDate, style: .date)")
                .font(.flyrCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Lead Row View

struct LeadRowView: View {
    let lead: FarmLead
    
    var body: some View {
        HStack {
            Image(systemName: "person.circle")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(lead.name ?? "Unknown")
                    .font(.flyrSubheadline)
                
                Text(lead.leadSource.displayName)
                    .font(.flyrCaption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: FarmRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text(recommendation.title)
                    .font(.flyrHeadline)
            }
            
            Text(recommendation.detail)
                .font(.flyrSubheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.yellow.opacity(0.1))
        )
    }
}

// MARK: - Farm Map Preview

struct FarmMapPreview: View {
    let polygon: [CLLocationCoordinate2D]
    
    var body: some View {
        // Simple map preview placeholder
        // Full implementation would use Mapbox
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.systemGray5))
            .frame(height: 200)
            .overlay {
                VStack {
                    Image(systemName: "map")
                        .font(.flyrLargeTitle)
                        .foregroundStyle(.secondary)
                    Text("Tap to view full map")
                        .font(.flyrCaption)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

#Preview {
    NavigationStack {
        FarmDetailView(farmId: UUID())
    }
}

