import SwiftUI
import CoreLocation
import MapboxMaps

/// Debug view for the simplified live GPS session flow.
struct GPSNormalizationDebugView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var showRawPoints = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pro GPS Debug")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    // Dismiss
                }
            }
            .padding()
            .background(Color(.systemBackground))
            
            // Stats
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    StatBox(title: "Raw Points", value: "\(sessionManager.proGPSDebugRawPointCount)")
                    StatBox(title: "Dwell", value: "\(sessionManager.dwellCompletionCount)")
                    StatBox(title: "Pending -> OK", value: "\(sessionManager.pendingToConfirmedCount)")
                    StatBox(title: "Pending -> Fail", value: "\(sessionManager.pendingToFailedCount)")
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            
            // Toggles
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Raw Points", isOn: $showRawPoints)
            }
            .padding()
            
            // Recent rejections
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Rejections")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if sessionManager.debugRecentRejections.isEmpty {
                    Text("No recent rejections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sessionManager.debugRecentRejections.prefix(5), id: \.self) { rejection in
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text(rejection)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Visit Pipeline")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Accepted raw points: \(sessionManager.acceptedRawPointCount)")
                    .font(.caption)
                Text("Dwell completions: \(sessionManager.dwellCompletionCount)")
                    .font(.caption)

                if !sessionManager.recentVisitDebugMessages.isEmpty {
                    ForEach(sessionManager.recentVisitDebugMessages.prefix(4), id: \.self) { message in
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 70)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

// MARK: - SessionManager Debug Extensions

extension SessionManager {
    var debugRecentRejections: [String] {
        recentRejectionEntries
    }
}

// MARK: - Preview

#Preview {
    GPSNormalizationDebugView(sessionManager: SessionManager.shared)
}
