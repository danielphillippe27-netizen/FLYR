import SwiftUI
import CoreLocation
import MapboxMaps

/// Debug view for Pro GPS Normalization Mode
/// Shows raw vs normalized points, active corridors, and rejection reasons
struct GPSNormalizationDebugView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var showRawPoints = true
    @State private var showNormalizedPoints = true
    @State private var showCorridors = true
    @State private var showOffsetLines = false
    
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
                    StatBox(title: "Normalized", value: "\(sessionManager.proGPSDebugNormalizedPointCount)")
                    StatBox(title: "Corridors", value: "\(sessionManager.debugCorridorCount)")
                    StatBox(title: "Active Side", value: sessionManager.debugActiveSide)
                    StatBox(title: "Street Fallback", value: "\(sessionManager.streetCoverageCandidateCount)")
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
                Toggle("Show Normalized Points", isOn: $showNormalizedPoints)
                Toggle("Show Corridors", isOn: $showCorridors)
                Toggle("Show Offset Lines", isOn: $showOffsetLines)
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
            
            // Campaign Road Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Campaign Road Status")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                HStack {
                    Image(systemName: sessionManager.debugRoadsLoaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(sessionManager.debugRoadsLoaded ? .green : .red)
                    Text(sessionManager.debugRoadsLoaded ? "Roads Loaded" : "No Roads")
                        .font(.caption)
                }
                
                if let source = sessionManager.debugRoadsSource {
                    Text("Source: \(source)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            VStack(alignment: .leading, spacing: 8) {
                Text("Visit Pipeline")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Accepted raw points: \(sessionManager.acceptedRawPointCount)")
                    .font(.caption)
                Text("Scored completions: \(sessionManager.scoredCompletionCount)")
                    .font(.caption)
                Text("Dwell completions: \(sessionManager.dwellCompletionCount)")
                    .font(.caption)
                Text("Avg match distance: \(sessionManager.debugAverageMatchedDistance)")
                    .font(.caption)
                Text("Same side / opposite side: \(sessionManager.sameSideMatchCount) / \(sessionManager.oppositeSideMatchCount)")
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
    var debugCorridorCount: Int {
        sessionRoadCorridors.count
    }
    
    var debugActiveSide: String {
        switch debugCurrentSideOfStreet {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .unknown:
            return "Unknown"
        case nil:
            return "None"
        }
    }
    
    var debugRecentRejections: [String] {
        recentRejectionEntries
    }

    var debugAverageMatchedDistance: String {
        guard matchedDistanceSampleCount > 0 else { return "--" }
        return String(format: "%.1fm", matchedDistanceTotalMeters / Double(matchedDistanceSampleCount))
    }
    
    var debugRoadsLoaded: Bool {
        isProNormalizationActive
    }
    
    var debugRoadsSource: String? {
        isProNormalizationActive ? "Campaign Cache" : nil
    }
}

// MARK: - Preview

#Preview {
    GPSNormalizationDebugView(sessionManager: SessionManager.shared)
}
