import SwiftUI

/// A/B Test creation view
/// Allows users to create a new experiment with campaign and landing page selection
struct ABTestCreateView: View {
    @StateObject private var hook = UseABTestCreate()
    @Environment(\.dismiss) private var dismiss
    @State private var createdExperiment: Experiment?
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Experiment Name
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Experiment Name")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        TextField("e.g., Home Value Page Test", text: $hook.experimentName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 17))
                    }
                    
                    // Campaign Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Campaign")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if hook.isLoadingCampaigns {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("Campaign", selection: $hook.selectedCampaignId) {
                                Text("Select a campaign")
                                    .tag(nil as UUID?)
                                
                                ForEach(hook.campaigns) { campaign in
                                    Text(campaign.title)
                                        .tag(campaign.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    // Landing Page Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Landing Page")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        if hook.isLoadingLandingPages {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Picker("Landing Page", selection: $hook.selectedLandingPageId) {
                                Text("Select a landing page")
                                    .tag(nil as UUID?)
                                
                                ForEach(hook.landingPages) { landingPage in
                                    Text(landingPage.name)
                                        .tag(landingPage.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    // Create Button
                    Button {
                        Task {
                            do {
                                let experiment = try await hook.createExperiment()
                                createdExperiment = experiment
                                // Navigate to detail view
                                dismiss()
                            } catch {
                                // Error is handled by hook.errorMessage
                            }
                        }
                    } label: {
                        HStack {
                            if hook.isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Create Experiment")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(hook.canCreate ? Color(hex: "FF4B47") : Color(.systemGray4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!hook.canCreate || hook.isCreating)
                }
                .padding(20)
            }
        }
        .navigationTitle("Create A/B Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .task {
            await hook.loadCampaigns()
            await hook.loadLandingPages()
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

#Preview {
    NavigationStack {
        ABTestCreateView()
    }
}

