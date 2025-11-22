import SwiftUI
import CoreLocation
import Supabase

struct CreateFarmView: View {
    @StateObject private var viewModel = CreateFarmViewModel()
    @State private var showPolygonSelector = false
    @State private var showTouchPlanner = false
    @State private var createdFarm: Farm?
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        Form {
            Section("Farm Details") {
                TextField("Farm Name", text: $viewModel.name)
                    .textInputAutocapitalization(.words)
                
                TextField("Area Label (Optional)", text: $viewModel.areaLabel)
                    .textInputAutocapitalization(.words)
            }
            
            Section("Timeframe") {
                Picker("Duration", selection: $viewModel.timeframe) {
                    ForEach(CreateFarmViewModel.Timeframe.allCases) { timeframe in
                        Text(timeframe.displayName).tag(timeframe)
                    }
                }
                .onChange(of: viewModel.timeframe) { _, _ in
                    viewModel.calculateDates()
                }
                
                DatePicker("Start Date", selection: $viewModel.startDate, displayedComponents: .date)
                DatePicker("End Date", selection: $viewModel.endDate, displayedComponents: .date)
            }
            
            Section("Touch Frequency") {
                Picker("Touches Per Month", selection: $viewModel.frequency) {
                    ForEach(1...4, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }
            
            Section("Farm Boundary") {
                if let polygon = viewModel.polygon {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("\(polygon.count) points selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Change") {
                            showPolygonSelector = true
                        }
                    }
                } else {
                    Button {
                        showPolygonSelector = true
                    } label: {
                        HStack {
                            Image(systemName: "map")
                            Text("Select Farm Boundary")
                        }
                    }
                }
            }
            
            Section {
                Button {
                    Task {
                        await createFarm()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Create Farm")
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.isValid || viewModel.isSaving)
            }
        }
        .navigationTitle("New Farm")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPolygonSelector) {
            FarmPolygonSelectorView(polygon: $viewModel.polygon)
        }
        .navigationDestination(isPresented: $showTouchPlanner) {
            if let farm = createdFarm {
                FarmTouchPlannerView(farmId: farm.id)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
    
    private func createFarm() async {
        guard let userId = authManager.user?.id else {
            viewModel.errorMessage = "Not authenticated"
            return
        }
        
        do {
            let farm = try await viewModel.saveFarm(userId: userId)
            createdFarm = farm
            showTouchPlanner = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CreateFarmView()
            .environmentObject(AuthManager.shared)
    }
}

