import SwiftUI

struct SessionSummaryView: View {
    let distance: Double
    let time: TimeInterval
    let goalType: GoalType
    let goalAmount: Int
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("Session Complete")
                    .font(.largeTitle.bold())
                    .padding(.top, 20)
                
                VStack(spacing: 20) {
                    SummaryStat(
                        title: "Distance",
                        value: String(format: "%.2f km", distance / 1000.0),
                        icon: "figure.walk"
                    )
                    
                    SummaryStat(
                        title: "Time",
                        value: formatTime(time),
                        icon: "clock"
                    )
                    
                    SummaryStat(
                        title: "Goal",
                        value: "\(goalAmount) \(goalType.displayName)",
                        icon: "target"
                    )
                }
                .padding()
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Text("Done")
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
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

struct SummaryStat: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title2.bold())
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


