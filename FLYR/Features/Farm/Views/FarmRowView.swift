import SwiftUI

/// Apple Wallet-style card component for displaying Farm in lists
struct FarmRowView: View {
    let farm: Farm
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
    
    private var progressPercentage: Int {
        Int(farm.progress * 100)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Name and Badge
            HStack {
                Text(farm.name)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundColor(.text)
                    .lineLimit(2)
                
                Spacer()
                
                Badge(text: "Farm")
            }
            
            // Created date
            Text("Created \(farm.createdAt, formatter: dateFormatter)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Progress section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Progress")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(progressPercentage)%")
                        .font(.subheadline)
                        .foregroundColor(.text)
                }
                
                ProgressView(value: farm.progress)
                    .tint(.red)
            }
            
            // Stats row
            HStack {
                Label("\(farm.frequency) touches/month", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.text)
                
                Spacer()
                
                if let areaLabel = farm.areaLabel {
                    Text(areaLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
        )
        .shadow(
            color: Color.black.opacity(0.5),
            radius: 8,
            x: 0,
            y: 2
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        FarmRowView(farm: Farm(
            id: UUID(),
            userId: UUID(),
            name: "Downtown Area",
            polygon: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 30),
            frequency: 2,
            createdAt: Date(),
            areaLabel: "Downtown"
        ))
    }
    .padding()
    .background(Color.bgSecondary)
}



