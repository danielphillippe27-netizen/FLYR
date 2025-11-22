import SwiftUI

struct SessionStartView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var goalType: GoalType = .flyers
    @State private var goalAmount: Int = 100
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                
                Picker("Goal", selection: $goalType) {
                    Text("Flyers").tag(GoalType.flyers)
                    Text("Door Knocks").tag(GoalType.knocks)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                VStack(spacing: 16) {
                    Stepper(value: $goalAmount, in: 10...1000, step: 10) {
                        Text("\(goalAmount) \(goalType == .flyers ? "Flyers" : "Knocks")")
                            .font(.title2.bold())
                    }
                    .padding(.horizontal)
                    
                    // Estimated time based on user's historical pace (placeholder)
                    Text("Estimated: \(estimateTime(goalAmount: goalAmount))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    SessionManager.shared.start(goalType: goalType, goalAmount: goalAmount)
                    dismiss()
                } label: {
                    Text("Start Session")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .padding()
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func estimateTime(goalAmount: Int) -> String {
        // Rough estimate: ~2 minutes per flyer/knock
        let estimatedMinutes = goalAmount * 2
        if estimatedMinutes < 60 {
            return "\(estimatedMinutes) minutes"
        } else {
            let hours = estimatedMinutes / 60
            let minutes = estimatedMinutes % 60
            return "\(hours)h \(minutes)m"
        }
    }
}


