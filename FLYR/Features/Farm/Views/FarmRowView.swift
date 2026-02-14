import SwiftUI

/// Minimal grey-box list row for Farm (matches Start Session / campaign list style).
struct FarmRowView: View {
    let farm: Farm

    private var subtitleText: String {
        if let area = farm.areaLabel, !area.isEmpty {
            return area
        }
        return "\(farm.frequency) touches/month"
    }

    private var statusText: String? {
        if farm.isActive { return "Active" }
        if farm.isCompleted { return "Completed" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(farm.name)
                .font(.flyrHeadline)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                Text(subtitleText)
                    .font(.flyrCaption)
                    .foregroundColor(.secondary)
                if let status = statusText {
                    Text(status)
                        .font(.flyrCaption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            (farm.isActive ? Color.green : Color.gray).opacity(0.2)
                        )
                        .foregroundColor(farm.isActive ? .green : .gray)
                        .cornerRadius(4)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
        .contentShape(Rectangle())
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
