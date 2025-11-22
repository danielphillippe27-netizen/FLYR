import SwiftUI

/// A/B Tests list view
/// Shows all experiments with navigation to detail view
struct ABTestsListView: View {
    @StateObject private var hook = UseABTestsList()
    @State private var showCreateView = false
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            if hook.isLoading {
                ProgressView("Loading experiments...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hook.experiments.isEmpty {
                EmptyState(
                    illustration: "circle.grid.2x2",
                    title: "No A/B Tests",
                    message: "Create your first A/B test experiment to compare QR code performance"
                )
            } else {
                List {
                    ForEach(hook.experiments) { experiment in
                        NavigationLink {
                            ABTestDetailView(experimentId: experiment.id)
                        } label: {
                            ABTestExperimentRow(experiment: experiment, campaignName: hook.getCampaignName(for: experiment))
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let experiment = hook.experiments[index]
                            Task {
                                await hook.deleteExperiment(id: experiment.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("A/B Tests")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateView = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                }
            }
        }
        .task {
            await hook.loadExperiments()
        }
        .sheet(isPresented: $showCreateView) {
            NavigationStack {
                ABTestCreateView()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { hook.errorMessage != nil },
            set: { if !$0 { hook.errorMessage = nil } }
        )) {
            Button("OK") {
                hook.errorMessage = nil
            }
        } message: {
            if let error = hook.errorMessage {
                Text(error)
            }
        }
    }
}

// MARK: - Experiment Row

private struct ABTestExperimentRow: View {
    let experiment: Experiment
    let campaignName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(experiment.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                ABTestStatusPill(status: experiment.status)
            }
            
            Text(campaignName)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        ABTestsListView()
    }
}

