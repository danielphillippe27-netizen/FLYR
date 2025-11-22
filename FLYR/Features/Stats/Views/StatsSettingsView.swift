import SwiftUI

struct StatsSettingsView: View {
    @ObservedObject var viewModel: LeaderboardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                Toggle("Real-time Updates (Pro)", isOn: Binding(
                    get: { viewModel.isRealTimeEnabled },
                    set: { enabled in
                        Task {
                            if enabled {
                                await viewModel.enableRealTimeUpdates()
                            } else {
                                await viewModel.disableRealTimeUpdates()
                            }
                        }
                    }
                ))
                .toggleStyle(.switch)
            } header: {
                Text("Leaderboard")
            } footer: {
                Text("Enable real-time updates to see leaderboard changes as they happen.")
            }
        }
        .navigationTitle("Stats Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    StatsSettingsView(viewModel: LeaderboardViewModel())
}

